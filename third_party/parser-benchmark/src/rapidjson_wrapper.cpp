#include "rapidjson/document.h"
#include "rapidjson/reader.h"
#include "rapidjson/memorystream.h"

extern "C" bool benchmark_rapidjson_dom(const char *ptr, size_t len) {
    rapidjson::Document d;
    d.Parse(ptr, len);
    return !d.HasParseError();
}

struct NullHandler {
    bool Null() { return true; }
    bool Bool(bool b) { return true; }
    bool Int(int i) { return true; }
    bool Uint(unsigned u) { return true; }
    bool Int64(int64_t i) { return true; }
    bool Uint64(uint64_t u) { return true; }
    bool Double(double d) { return true; }
    bool RawNumber(const char* str, rapidjson::SizeType length, bool copy) { return true; }
    bool String(const char* str, rapidjson::SizeType length, bool copy) { return true; }
    bool StartObject() { return true; }
    bool Key(const char* str, rapidjson::SizeType length, bool copy) { return true; }
    bool EndObject(rapidjson::SizeType memberCount) { return true; }
    bool StartArray() { return true; }
    bool EndArray(rapidjson::SizeType elementCount) { return true; }
};

extern "C" bool benchmark_rapidjson_sax(const char *ptr, size_t len) {
    rapidjson::Reader reader;
    rapidjson::MemoryStream ss(ptr, len);
    NullHandler handler;
    return reader.Parse(ss, handler);
}
