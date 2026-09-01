/* JSON throughput through the Galley C API: no AST, no procedures, no
 * error recovery. Parses languages/json/samples/code-02.json 10 times
 * on one session and reports bytes/s. */
#define _POSIX_C_SOURCE 200809L

#include <galley.h>

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#ifndef GALLEY_SOURCE_DIR
#define GALLEY_SOURCE_DIR "../.."
#endif

static const char kInput[] = "languages/json/samples/code-02.json";
static const int kDefaultIterations = 10;

static char *read_file(const char *path, size_t *out_len) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) return NULL;
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return NULL;
    }
    long size = ftell(file);
    if (size < 0) {
        fclose(file);
        return NULL;
    }
    if (fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }
    char *buffer = malloc((size_t)size + 1);
    if (buffer == NULL) {
        fclose(file);
        return NULL;
    }
    size_t read = fread(buffer, 1, (size_t)size, file);
    fclose(file);
    if (read != (size_t)size) {
        free(buffer);
        return NULL;
    }
    buffer[size] = '\0';
    *out_len = (size_t)size;
    return buffer;
}

static void print_u64(const char *label, unsigned long long n) {
    char digits[32];
    const int len = snprintf(digits, sizeof digits, "%llu", n);
    fputs(label, stdout);
    fputs(": ", stdout);
    for (int i = 0; i < len; ++i) {
        if (i > 0 && (len - i) % 3 == 0) putchar(',');
        putchar(digits[i]);
    }
    putchar('\n');
}

static unsigned long long now_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (unsigned long long)ts.tv_sec * 1000000000ULL +
           (unsigned long long)ts.tv_nsec;
}

static int join_under(char *buffer, size_t size, const char *root, const char *relative) {
    const int n = snprintf(buffer, size, "%s/%s", root, relative);
    return n > 0 && (size_t)n < size;
}

static int file_exists(const char *path) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) return 0;
    fclose(file);
    return 1;
}

static const char *resolve_input(const char *requested, char *buffer, size_t size) {
    if (requested != NULL) return requested;

    const char *checkout = getenv("GALLEY_CHECKOUT");
    if (checkout != NULL && checkout[0] != '\0') {
        if (join_under(buffer, size, checkout, kInput) && file_exists(buffer)) return buffer;
    }
    if (!join_under(buffer, size, GALLEY_SOURCE_DIR, kInput)) return NULL;
    return buffer;
}

int main(int argc, char **argv) {
    char default_path[4096];
    const char *path = resolve_input(argc > 1 ? argv[1] : NULL, default_path, sizeof default_path);
    int iterations = kDefaultIterations;
    if (argc > 2) {
        iterations = atoi(argv[2]);
        if (iterations < 1) {
            fprintf(stderr, "iterations must be >= 1\n");
            return 1;
        }
    }

    size_t length = 0;
    char *input = path == NULL ? NULL : read_file(path, &length);
    if (input == NULL) {
        fprintf(stderr, "failed to read %s\n", kInput);
        return 1;
    }

    GalleySession *session = galley_session_create();
    if (session == NULL) {
        fprintf(stderr, "failed to create a parser session\n");
        free(input);
        return 1;
    }

    long long parsed = galley_parse(session, input, length);
    if (parsed < 0 || (size_t)parsed != length) {
        fprintf(stderr, "warmup parse failed: %s (%lld)\n",
                galley_status_string(parsed), parsed);
        galley_session_destroy(session);
        free(input);
        return 1;
    }

    unsigned long long start = now_ns();
    for (int i = 0; i < iterations; ++i) {
        parsed = galley_parse(session, input, length);
        if (parsed < 0 || (size_t)parsed != length) {
            fprintf(stderr, "parse failed at iteration %d: %s (%lld)\n",
                    i, galley_status_string(parsed), parsed);
            galley_session_destroy(session);
            free(input);
            return 1;
        }
    }
    unsigned long long elapsed = now_ns() - start;
    unsigned long long total = (unsigned long long)length * (unsigned long long)iterations;
    unsigned long long bps = elapsed == 0 ? 0 : total * 1000000000ULL / elapsed;

    printf("input: %s\n", kInput);
    print_u64("bytes", length);
    print_u64("iterations", (unsigned long long)iterations);
    print_u64("parsed_bytes", total);
    print_u64("duration_ns", elapsed);
    print_u64("bytes_per_second", bps);

    galley_session_destroy(session);
    free(input);
    return 0;
}
