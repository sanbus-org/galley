#include "simdjson/simdjson.h"

// Validate: use the ondemand API which lazily validates structure without
// materialising a DOM. We iterate top-level values to force stage-2 parsing
// of the structural skeleton, but skip deep object/array content.
extern "C" bool benchmark_simdjson_validate(const char *input_ptr, size_t input_len) {
    auto view = simdjson::padded_string_view(input_ptr, input_len, input_len + simdjson::SIMDJSON_PADDING);
    simdjson::ondemand::parser parser;
    simdjson::ondemand::document doc;
    if (parser.iterate(view).get(doc)) return false;
    for (auto val : doc) {
        if (val.error()) return false;
    }
    return true;
}

// DOM: use the dom::parser which always builds the full internal tape
// (stage 1 structural indexing + stage 2 full parse → DOM element tree).
extern "C" bool benchmark_simdjson_dom(const char *input_ptr, size_t input_len) {
    auto view = simdjson::padded_string_view(input_ptr, input_len, input_len + simdjson::SIMDJSON_PADDING);
    simdjson::dom::parser parser;
    simdjson::dom::element doc;
    auto error = parser.parse(view).get(doc);
    return error == simdjson::error_code::SUCCESS;
}
