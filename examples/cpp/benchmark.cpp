// JSON throughput through the Galley C API: no AST, no procedures, no
// error recovery. Parses languages/json/samples/code-01.json 50,000 times
// on one session and reports bytes/s.
#include <galley.h>

#include <chrono>
#include <cstddef>
#include <cstdio>
#include <cstdlib>

namespace {

constexpr const char *kLogicalInput = "languages/json/samples/code-01.json";
constexpr int kDefaultIterations = 50000;

char *readFile(const char *path, std::size_t *out_len) {
    FILE *file = std::fopen(path, "rb");
    if (file == nullptr) return nullptr;
    if (std::fseek(file, 0, SEEK_END) != 0) {
        std::fclose(file);
        return nullptr;
    }
    const long size = std::ftell(file);
    if (size < 0) {
        std::fclose(file);
        return nullptr;
    }
    if (std::fseek(file, 0, SEEK_SET) != 0) {
        std::fclose(file);
        return nullptr;
    }
    char *buffer = static_cast<char *>(std::malloc(static_cast<std::size_t>(size) + 1));
    if (buffer == nullptr) {
        std::fclose(file);
        return nullptr;
    }
    const std::size_t read = std::fread(buffer, 1, static_cast<std::size_t>(size), file);
    std::fclose(file);
    if (read != static_cast<std::size_t>(size)) {
        std::free(buffer);
        return nullptr;
    }
    buffer[size] = '\0';
    *out_len = static_cast<std::size_t>(size);
    return buffer;
}

#ifndef GALLEY_JSON_SAMPLE
#define GALLEY_JSON_SAMPLE "../../languages/json/samples/code-01.json"
#endif

void printU64(const char *label, unsigned long long n) {
    char digits[32];
    const int len = std::snprintf(digits, sizeof digits, "%llu", n);
    std::fputs(label, stdout);
    std::fputs(": ", stdout);
    for (int i = 0; i < len; ++i) {
        if (i > 0 && (len - i) % 3 == 0) std::putchar(',');
        std::putchar(digits[i]);
    }
    std::putchar('\n');
}

}  // namespace

int main(int argc, char *argv[]) {
    const char *path = GALLEY_JSON_SAMPLE;
    int iterations = kDefaultIterations;
    if (argc > 1) path = argv[1];
    if (argc > 2) {
        iterations = std::atoi(argv[2]);
        if (iterations < 1) {
            std::fprintf(stderr, "iterations must be >= 1\n");
            return 1;
        }
    }

    std::size_t length = 0;
    char *input = readFile(path, &length);
    if (input == nullptr) {
        std::fprintf(stderr, "failed to read %s\n", kLogicalInput);
        return 1;
    }

    GalleySession *session = galley_session_create();
    if (session == nullptr) {
        std::fprintf(stderr, "failed to create a parser session\n");
        std::free(input);
        return 1;
    }

    long long parsed = galley_parse(session, input, length);
    if (parsed < 0 || static_cast<std::size_t>(parsed) != length) {
        std::fprintf(stderr, "warmup parse failed: %s (%lld)\n",
                     galley_status_string(parsed), parsed);
        galley_session_destroy(session);
        std::free(input);
        return 1;
    }

    const auto start = std::chrono::steady_clock::now();
    for (int i = 0; i < iterations; ++i) {
        parsed = galley_parse(session, input, length);
        if (parsed < 0 || static_cast<std::size_t>(parsed) != length) {
            std::fprintf(stderr, "parse failed at iteration %d: %s (%lld)\n",
                         i, galley_status_string(parsed), parsed);
            galley_session_destroy(session);
            std::free(input);
            return 1;
        }
    }
    const auto elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(
                             std::chrono::steady_clock::now() - start)
                             .count();
    const unsigned long long total =
        static_cast<unsigned long long>(length) * static_cast<unsigned long long>(iterations);
    const unsigned long long ns = elapsed < 0 ? 0 : static_cast<unsigned long long>(elapsed);
    const unsigned long long bps = ns == 0 ? 0 : total * 1000000000ULL / ns;

    std::printf("input: %s\n", kLogicalInput);
    printU64("bytes", length);
    printU64("iterations", static_cast<unsigned long long>(iterations));
    printU64("parsed_bytes", total);
    printU64("duration_ns", ns);
    printU64("bytes_per_second", bps);

    galley_session_destroy(session);
    std::free(input);
    return 0;
}
