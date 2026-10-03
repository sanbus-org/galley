/* Concurrency test for the Galley C ABI: two parsers, two sessions each,
 * four threads parsing at the same time.
 *
 * Two parsers are two separately built libraries (the keyvalue grammar and
 * the second shared fixture grammar), each loaded with dlopen so their
 * identical symbol names stay apart. Each session carries its own handle and
 * its own enabled hook set. The first hook of every parse waits at a
 * four-way barrier, so the test passes only if all four parses are in flight
 * at once, then every worker's hook calls are compared with a sequential run
 * of the same session configuration. A hook that fired on the wrong thread,
 * for the wrong handle, or not at all shows up as a count mismatch.
 *
 * Usage: test_concurrency <first-library> <second-library>
 */
#include <galley.h>

#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAX_HOOKS 32
#define STRESS_ROUNDS 200
#define BARRIER_TIMEOUT_SECONDS 20

static int failures = 0;
static int ran = 0;

#define CHECK(condition)                                                     \
    do {                                                                     \
        ++ran;                                                               \
        if (!(condition)) {                                                  \
            ++failures;                                                      \
            printf("not ok %d %s:%d: %s\n", ran, __FILE__, __LINE__, #condition); \
        } else {                                                             \
            printf("ok %d %s\n", ran, #condition);                            \
        }                                                                    \
    } while (0)

typedef struct Library {
    void *image;
    GalleySession *(*session_create)(void);
    void (*session_destroy)(GalleySession *);
    long long (*parse)(GalleySession *, const char *, size_t);
    long long (*root_node)(GalleySession *, GalleyNodeAddress *, unsigned long long *);
    long long (*set_hooks)(GalleySession *, GalleyHookDispatch, void *, const unsigned char *, size_t);
    size_t (*hooks_count)(void);
    const char *(*hook_name_data)(size_t);
    size_t (*hook_name_length)(size_t);
    size_t count;
} Library;

static void *load_symbol(void *image, const char *name) {
    void *symbol = dlsym(image, name);
    if (symbol == NULL) printf("missing symbol %s: %s\n", name, dlerror());
    return symbol;
}

static int load_library(Library *library, const char *path) {
    library->image = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (library->image == NULL) {
        printf("cannot load %s: %s\n", path, dlerror());
        return 0;
    }
    *(void **)&library->session_create = load_symbol(library->image, "galley_session_create");
    *(void **)&library->session_destroy = load_symbol(library->image, "galley_session_destroy");
    *(void **)&library->parse = load_symbol(library->image, "galley_parse");
    *(void **)&library->root_node = load_symbol(library->image, "galley_root_node");
    *(void **)&library->set_hooks = load_symbol(library->image, "galley_session_set_hooks");
    *(void **)&library->hooks_count = load_symbol(library->image, "galley_hooks_count");
    *(void **)&library->hook_name_data = load_symbol(library->image, "galley_hooks_name_data");
    *(void **)&library->hook_name_length = load_symbol(library->image, "galley_hooks_name_length");
    if (library->session_create == NULL || library->session_destroy == NULL || library->parse == NULL ||
        library->root_node == NULL || library->set_hooks == NULL || library->hooks_count == NULL || library->hook_name_data == NULL ||
        library->hook_name_length == NULL) {
        return 0;
    }
    library->count = library->hooks_count();
    return 1;
}

/* Index of the named hook, or the count when the library has none. */
static size_t hook_index(const Library *library, const char *name) {
    size_t length = strlen(name);
    for (size_t index = 0; index < library->count; ++index) {
        if (library->hook_name_length(index) == length &&
            memcmp(library->hook_name_data(index), name, length) == 0) {
            return index;
        }
    }
    return library->count;
}

typedef struct Barrier {
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    int needed;
    int arrived;
} Barrier;

/* Returns 1 once `needed` threads have arrived, 0 on timeout. A bounded wait
 * turns "the parses ran one after another" into a failure, not a hang. */
static int barrier_wait(Barrier *barrier) {
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += BARRIER_TIMEOUT_SECONDS;
    int arrived_together = 1;
    pthread_mutex_lock(&barrier->mutex);
    if (++barrier->arrived == barrier->needed) pthread_cond_broadcast(&barrier->condition);
    while (barrier->arrived < barrier->needed) {
        if (pthread_cond_timedwait(&barrier->condition, &barrier->mutex, &deadline) == ETIMEDOUT) {
            arrived_together = 0;
            break;
        }
    }
    pthread_mutex_unlock(&barrier->mutex);
    return arrived_together;
}

typedef struct Worker {
    const Library *library;
    const char *input;
    size_t input_length;
    unsigned char enabled[MAX_HOOKS];
    GalleySession *session;
    Barrier *barrier;
    pthread_t thread;
    unsigned calls[MAX_HOOKS];
    unsigned wrong_thread;
    int waited;
    int arrived_together;
    long long set_hooks_during_parse;
    long long parse_status;
} Worker;

static void dispatch(void *handle, unsigned int index, void *args) {
    Worker *worker = (Worker *)handle;
    (void)args;
    if (!pthread_equal(pthread_self(), worker->thread)) ++worker->wrong_thread;
    if (index < MAX_HOOKS) ++worker->calls[index];
    if (worker->barrier != NULL && !worker->waited) {
        worker->waited = 1;
        worker->arrived_together = barrier_wait(worker->barrier);
        /* Still inside the parse: changing hooks must be refused. */
        worker->set_hooks_during_parse =
            worker->library->set_hooks(worker->session, dispatch, worker, worker->enabled, worker->library->count);
    }
}

static void *parse_on_thread(void *argument) {
    Worker *worker = (Worker *)argument;
    worker->thread = pthread_self();
    worker->parse_status = worker->library->parse(worker->session, worker->input, worker->input_length);
    return NULL;
}

/* `pairs` key:value pairs of the keyvalue grammar: k0:0,k1:1,... */
static char *keyvalue_input(size_t pairs, size_t *length) {
    size_t capacity = pairs * 24 + 1;
    char *buffer = (char *)malloc(capacity);
    size_t used = 0;
    for (size_t i = 0; i < pairs; ++i) {
        used += (size_t)snprintf(buffer + used, capacity - used, "%sk%zu:%zu", i == 0 ? "" : ",", i, i % 97);
    }
    *length = used;
    return buffer;
}

/* `words` plus-separated words of the second grammar: wordabc+wordabc+... */
static char *word_input(size_t words, size_t *length) {
    size_t capacity = words * 16 + 1;
    char *buffer = (char *)malloc(capacity);
    size_t used = 0;
    for (size_t i = 0; i < words; ++i) {
        used += (size_t)snprintf(buffer + used, capacity - used, "%sword", i == 0 ? "" : "+");
    }
    *length = used;
    return buffer;
}

static void set_enabled_all(Worker *worker) {
    memset(worker->enabled, 0, sizeof worker->enabled);
    for (size_t index = 0; index < worker->library->count; ++index) worker->enabled[index] = 1;
}

static void set_enabled_only(Worker *worker, const char *name) {
    memset(worker->enabled, 0, sizeof worker->enabled);
    size_t index = hook_index(worker->library, name);
    if (index < worker->library->count) worker->enabled[index] = 1;
}

static int configure(Worker *worker) {
    worker->session = worker->library->session_create();
    if (worker->session == NULL) return 0;
    return worker->library->set_hooks(worker->session, dispatch, worker, worker->enabled, worker->library->count) == galley_ok;
}

static int same_calls(const Worker *left, const Worker *right) {
    return memcmp(left->calls, right->calls, sizeof left->calls) == 0;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        printf("usage: %s <first-library> <second-library>\n", argv[0]);
        return 2;
    }
    Library first;
    Library second;
    memset(&first, 0, sizeof first);
    memset(&second, 0, sizeof second);
    if (!load_library(&first, argv[1]) || !load_library(&second, argv[2])) return 2;

    CHECK(first.count > 0 && second.count > 0);
    CHECK(first.count != second.count);
    CHECK(first.count <= MAX_HOOKS && second.count <= MAX_HOOKS);
    CHECK(hook_index(&first, "hook_print") < first.count);
    CHECK(hook_index(&second, "hook_tally") < second.count);
    CHECK(hook_index(&first, "hook_tally") == first.count);
    CHECK(hook_index(&second, "hook_print") == second.count);
    CHECK(first.hook_name_data(first.count) == NULL && first.hook_name_length(first.count) == 0);

    size_t first_length = 0;
    size_t second_length = 0;
    char *first_input = keyvalue_input(150, &first_length);
    char *second_input = word_input(150, &second_length);

    /* Two sessions per parser, each with its own enabled set. */
    Worker workers[4];
    memset(workers, 0, sizeof workers);
    const Library *libraries[4] = {&first, &first, &second, &second};
    for (int i = 0; i < 4; ++i) {
        workers[i].library = libraries[i];
        workers[i].input = i < 2 ? first_input : second_input;
        workers[i].input_length = i < 2 ? first_length : second_length;
    }
    set_enabled_all(&workers[0]);
    set_enabled_only(&workers[1], "hook_print");
    set_enabled_all(&workers[2]);
    set_enabled_only(&workers[3], "reduction_Word");

    /* Sequential reference run: the same configuration, one thread, fresh
     * sessions. */
    Worker reference[4];
    memcpy(reference, workers, sizeof reference);
    int configured = 1;
    for (int i = 0; i < 4; ++i) {
        reference[i].barrier = NULL;
        configured = configure(&reference[i]) && configured;
        parse_on_thread(&reference[i]);
    }
    CHECK(configured);
    for (int i = 0; i < 4; ++i) {
        CHECK(reference[i].parse_status > 0);
        CHECK(reference[i].wrong_thread == 0);
    }
    /* The reference is not vacuous, and the enabled sets really differ. */
    CHECK(reference[0].calls[hook_index(&first, "hook_print")] == 150);
    CHECK(reference[1].calls[hook_index(&first, "hook_print")] == 150);
    CHECK(reference[0].calls[hook_index(&first, "reduction_Pair")] > 0);
    CHECK(reference[1].calls[hook_index(&first, "reduction_Pair")] == 0);
    CHECK(reference[2].calls[hook_index(&second, "hook_tally")] == 150);
    CHECK(reference[3].calls[hook_index(&second, "hook_tally")] == 0);
    CHECK(reference[3].calls[hook_index(&second, "reduction_Word")] == 150);

    /* Concurrent run: all four parses held at one barrier. */
    Barrier barrier;
    pthread_mutex_init(&barrier.mutex, NULL);
    pthread_cond_init(&barrier.condition, NULL);
    barrier.needed = 4;
    barrier.arrived = 0;
    int created = 1;
    for (int i = 0; i < 4; ++i) {
        workers[i].barrier = &barrier;
        workers[i].set_hooks_during_parse = 0;
        created = configure(&workers[i]) && created;
    }
    CHECK(created);
    for (int i = 0; i < 4; ++i) pthread_create(&workers[i].thread, NULL, parse_on_thread, &workers[i]);
    for (int i = 0; i < 4; ++i) pthread_join(workers[i].thread, NULL);
    for (int i = 0; i < 4; ++i) {
        CHECK(workers[i].parse_status == reference[i].parse_status);
        CHECK(workers[i].arrived_together);
        CHECK(workers[i].wrong_thread == 0);
        CHECK(same_calls(&workers[i], &reference[i]));
        CHECK(workers[i].set_hooks_during_parse == galley_error_session_in_use);
    }

    /* Between parses: replacing hooks keeps the published result valid,
     * malformed requests are refused, and an empty set silences every hook. */
    {
        static const unsigned silent[MAX_HOOKS];
        Worker *idle = &workers[1];
        const Library *library = idle->library;
        GalleyNodeAddress root = GALLEY_INVALID_NODE;
        unsigned long long generation = 0;
        CHECK(library->root_node(idle->session, &root, &generation) == galley_ok);
        CHECK(root != GALLEY_INVALID_NODE);
        CHECK(library->set_hooks(idle->session, dispatch, idle, idle->enabled, library->count) == galley_ok);
        GalleyNodeAddress same_root = GALLEY_INVALID_NODE;
        unsigned long long same_generation = 0;
        CHECK(library->root_node(idle->session, &same_root, &same_generation) == galley_ok);
        CHECK(same_root == root && same_generation == generation);
        CHECK(library->set_hooks(NULL, dispatch, idle, idle->enabled, library->count) == galley_error_null_argument);
        CHECK(library->set_hooks(idle->session, dispatch, idle, idle->enabled, library->count - 1) == galley_error_null_argument);
        CHECK(library->set_hooks(idle->session, dispatch, idle, NULL, library->count) == galley_error_null_argument);
        CHECK(library->set_hooks(idle->session, dispatch, idle, NULL, 0) == galley_ok);
        idle->barrier = NULL;
        memset(idle->calls, 0, sizeof idle->calls);
        parse_on_thread(idle);
        CHECK(idle->parse_status == reference[1].parse_status);
        CHECK(memcmp(idle->calls, silent, sizeof silent) == 0);
        CHECK(library->set_hooks(idle->session, dispatch, idle, idle->enabled, library->count) == galley_ok);
    }

    /* Stress: the same four sessions parse again and again with no barrier;
     * every round must reproduce the reference counts. */
    int stable = 1;
    for (int round = 0; round < STRESS_ROUNDS; ++round) {
        for (int i = 0; i < 4; ++i) {
            workers[i].barrier = NULL;
            memset(workers[i].calls, 0, sizeof workers[i].calls);
            workers[i].wrong_thread = 0;
            pthread_create(&workers[i].thread, NULL, parse_on_thread, &workers[i]);
        }
        for (int i = 0; i < 4; ++i) pthread_join(workers[i].thread, NULL);
        for (int i = 0; i < 4; ++i) {
            if (workers[i].parse_status != reference[i].parse_status || workers[i].wrong_thread != 0 ||
                !same_calls(&workers[i], &reference[i])) {
                stable = 0;
            }
        }
    }
    CHECK(stable);

    for (int i = 0; i < 4; ++i) {
        workers[i].library->session_destroy(workers[i].session);
        reference[i].library->session_destroy(reference[i].session);
    }
    free(first_input);
    free(second_input);
    printf("%d tests, %d failures\n", ran, failures);
    return failures == 0 ? 0 : 1;
}
