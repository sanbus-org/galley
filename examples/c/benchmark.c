/* JSON throughput through the Galley C API: no AST, no procedures, no
 * error recovery. Parses languages/json/samples/code-01.json 50,000 times
 * on one session and reports bytes/s. */
#define _POSIX_C_SOURCE 200809L

#include <galley.h>

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static const char *kLogicalInput = "languages/json/samples/code-01.json";
static const int kDefaultIterations = 50000;

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

#ifndef GALLEY_JSON_SAMPLE
#define GALLEY_JSON_SAMPLE "../../languages/json/samples/code-01.json"
#endif

int main(int argc, char **argv) {
    const char *path = GALLEY_JSON_SAMPLE;
    int iterations = kDefaultIterations;
    if (argc > 1) path = argv[1];
    if (argc > 2) {
        iterations = atoi(argv[2]);
        if (iterations < 1) {
            fprintf(stderr, "iterations must be >= 1\n");
            return 1;
        }
    }

    size_t length = 0;
    char *input = read_file(path, &length);
    if (input == NULL) {
        fprintf(stderr, "failed to read %s\n", kLogicalInput);
        return 1;
    }

    GalleySession *session = galley_session_create();
    if (session == NULL) {
        fprintf(stderr, "failed to create a parser session\n");
        free(input);
        return 1;
    }

    long long parsed = galley_parse_sentinel(session, input);
    if (parsed < 0 || (size_t)parsed != length) {
        fprintf(stderr, "warmup parse failed: %s (%lld)\n",
                galley_status_string(parsed), parsed);
        galley_session_destroy(session);
        free(input);
        return 1;
    }

    unsigned long long start = now_ns();
    for (int i = 0; i < iterations; ++i) {
        parsed = galley_parse_sentinel(session, input);
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

    printf("input: %s\n", kLogicalInput);
    print_u64("bytes", length);
    print_u64("iterations", (unsigned long long)iterations);
    print_u64("parsed_bytes", total);
    print_u64("duration_ns", elapsed);
    print_u64("bytes_per_second", bps);

    galley_session_destroy(session);
    free(input);
    return 0;
}
