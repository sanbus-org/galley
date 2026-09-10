/*
 * Node NAPI addon wrapping bindings/c/galley.h: the single FFI boundary for
 * the Node runtime. TypeScript implements FfiPort through this addon.
 *
 * Loading: `load(parserPath)` dlopens nothing itself for required symbols
 * (this object links the parser library, like any C consumer); it opens a
 * dl handle on the same path solely to probe the optional JS-shim symbols
 * (`galley_install_js_dispatch_id`, `galley_js_procedure_*`), which stay
 * null on libraries that predate them. The returned object binds every
 * function to that library; dispatch installs are per library path.
 *
 * Hooks: parse runs on the JS thread, so the parser callback re-enters JS
 * with napi_call_function in the same thread. Same-thread reentrancy across
 * libraries nests parses; a frame stack carries each parse's function and
 * receiver while one handle scope covers the outermost parse. A pending
 * JS exception after a hook is cleared so a throwing hook never aborts the
 * parse.
 */

#define NAPI_VERSION 8

#include <dlfcn.h>
#include <node_api.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "galley.h"

/* ------------------------------------------------------------------ */
/* Small result helpers.                                               */
/* ------------------------------------------------------------------ */

#define CHECK(call)          \
  do {                       \
    if ((call) != napi_ok) { \
      return NULL;           \
    }                        \
  } while (0)

/* Tolerant integer readers: BigInt when exact, Number otherwise (koffi
 * accepted both spellings, and the TypeScript side mixes them). Anything
 * else is a TypeError. */
static bool get_u64(napi_env env, napi_value value, uint64_t *out) {
  napi_valuetype type;
  if (napi_typeof(env, value, &type) != napi_ok) return false;
  if (type == napi_bigint) {
    bool lossless = false;
    if (napi_get_value_bigint_uint64(env, value, out, &lossless) != napi_ok || !lossless) {
      napi_throw_type_error(env, NULL, "expected uint64");
      return false;
    }
    return true;
  }
  if (type == napi_number) {
    double number = 0;
    if (napi_get_value_double(env, value, &number) != napi_ok) {
      napi_throw_type_error(env, NULL, "expected integer");
      return false;
    }
    *out = (uint64_t)number;
    return true;
  }
  napi_throw_type_error(env, NULL, "expected integer");
  return false;
}

static bool get_i64(napi_env env, napi_value value, int64_t *out) {
  napi_valuetype type;
  if (napi_typeof(env, value, &type) != napi_ok) return false;
  if (type == napi_bigint) {
    bool lossless = false;
    if (napi_get_value_bigint_int64(env, value, out, &lossless) != napi_ok || !lossless) {
      napi_throw_type_error(env, NULL, "expected int64");
      return false;
    }
    return true;
  }
  if (type == napi_number) {
    double number = 0;
    if (napi_get_value_double(env, value, &number) != napi_ok) {
      napi_throw_type_error(env, NULL, "expected integer");
      return false;
    }
    *out = (int64_t)number;
    return true;
  }
  napi_throw_type_error(env, NULL, "expected integer");
  return false;
}

static bool get_i32(napi_env env, napi_value value, int32_t *out) {
  uint64_t wide = 0;
  if (!get_u64(env, value, &wide)) return false;
  *out = (int32_t)wide;
  return true;
}

static bool get_u32(napi_env env, napi_value value, uint32_t *out) {
  uint64_t wide = 0;
  if (!get_u64(env, value, &wide)) return false;
  *out = (uint32_t)wide;
  return true;
}

/* Reads a JS string as UTF-8 bytes (malloc'd, caller frees). */
static bool get_utf8(napi_env env, napi_value value, char **out_data, size_t *out_len) {
  size_t needed = 0;
  if (napi_get_value_string_utf8(env, value, NULL, 0, &needed) != napi_ok) {
    napi_throw_type_error(env, NULL, "expected string");
    return false;
  }
  char *data = (char *)malloc(needed + 1);
  if (data == NULL) {
    napi_throw_error(env, NULL, "out of memory");
    return false;
  }
  size_t written = 0;
  if (napi_get_value_string_utf8(env, value, data, needed + 1, &written) != napi_ok) {
    free(data);
    return false;
  }
  *out_data = data;
  *out_len = written;
  return true;
}

static napi_value make_u64(napi_env env, uint64_t value) {
  napi_value out;
  if (napi_create_bigint_uint64(env, value, &out) != napi_ok) return NULL;
  return out;
}

static napi_value make_i64(napi_env env, int64_t value) {
  napi_value out;
  if (napi_create_bigint_int64(env, value, &out) != napi_ok) return NULL;
  return out;
}

static napi_value make_i32(napi_env env, int32_t value) {
  napi_value out;
  if (napi_create_int32(env, value, &out) != napi_ok) return NULL;
  return out;
}

static napi_value make_u32(napi_env env, uint32_t value) {
  napi_value out;
  if (napi_create_uint32(env, value, &out) != napi_ok) return NULL;
  return out;
}

/* Copies (data, len) into a Buffer, or null when data is NULL. */
static napi_value make_buffer_or_null(napi_env env, const char *data, size_t len) {
  if (data == NULL) {
    napi_value null_value;
    if (napi_get_null(env, &null_value) != napi_ok) return NULL;
    return null_value;
  }
  void *copied = NULL;
  napi_value buffer;
  if (napi_create_buffer_copy(env, len, data, &copied, &buffer) != napi_ok) return NULL;
  return buffer;
}

/* Copies a NUL-terminated string, or null when the pointer is NULL. */
static napi_value make_string_or_null(napi_env env, const char *text) {
  if (text == NULL) {
    napi_value null_value;
    if (napi_get_null(env, &null_value) != napi_ok) return NULL;
    return null_value;
  }
  napi_value out;
  if (napi_create_string_utf8(env, text, NAPI_AUTO_LENGTH, &out) != napi_ok) return NULL;
  return out;
}

/* ------------------------------------------------------------------ */
/* Per-library state.                                                  */
/* ------------------------------------------------------------------ */

typedef void (*dispatch_id_fn)(void (*target)(uint32_t id, void *args));
typedef void (*dispatch_name_fn)(void (*target)(const char *name, size_t name_len, void *args));

typedef struct Lib {
  void *probe;
  dispatch_id_fn install_id;
  dispatch_name_fn install_name;
  uint32_t (*procedure_count)(void);
  void *(*procedure_name_ptr)(uint32_t index);
  size_t (*procedure_name_len)(uint32_t index);
  int (*procedure_enable)(const char *name, size_t name_len);
  void (*procedure_clear)(void);
  napi_ref id_callback;
  napi_ref name_callback;
  napi_ref dispatch_ref;
  // Every bound name, verified against the probe handle at load so a
  // header/binary skew fails here naming the symbol.
  const char *bound_names[192];
  int bound_count;
} Lib;

/* One parse frame per nesting level; a single handle scope covers the
 * outermost parse while each level keeps its own function and receiver. */
#define MAX_PARSE_DEPTH 32

typedef struct ParseFrame {
  napi_value function;
  napi_value receiver;
  napi_handle_scope scope;
  bool owns_scope;
} ParseFrame;

static ParseFrame parse_frames[MAX_PARSE_DEPTH + 1];
static int parse_depth = 0;

static void clear_pending(napi_env env) {
  bool pending = false;
  if (napi_is_exception_pending(env, &pending) != napi_ok || !pending) return;
  napi_value thrown;
  napi_get_and_clear_last_exception(env, &thrown);
  (void)thrown;
}

static void dispatch_call(napi_env env, uint32_t id, const char *name, size_t name_len,
                          void *args, bool by_id) {
  if (parse_depth == 0) return;
  ParseFrame *frame = &parse_frames[parse_depth - 1];
  napi_value argv[2];
  napi_value result;
  if (by_id) {
    if (napi_create_uint32(env, id, &argv[0]) != napi_ok) return;
  } else {
    if (napi_create_string_utf8(env, name, name_len, &argv[0]) != napi_ok) return;
  }
  if (napi_create_bigint_uint64(env, (uint64_t)(uintptr_t)args, &argv[1]) != napi_ok) return;
  if (napi_call_function(env, frame->receiver, frame->function, 2, argv, &result) != napi_ok) {
    clear_pending(env);
    return;
  }
  clear_pending(env);
}

/* Installed into the parser library; unmarshals to dispatch_call. The
 * active parse frame selects the library whose hooks are firing, so nested
 * parses across libraries dispatch to the right receiver. */
static napi_env active_env = NULL;

static void id_trampoline(uint32_t id, void *args) {
  if (active_env == NULL) return;
  dispatch_call(active_env, id, NULL, 0, args, true);
}

static void name_trampoline(const char *name, size_t name_len, void *args) {
  if (active_env == NULL) return;
  dispatch_call(active_env, 0, name, name_len, args, false);
}

/* Runs the parse body inside a frame carrying this library's dispatcher.
 * Libraries without an installed dispatcher (C procedures) skip framing. */
typedef long long (*parse_body_fn)(void *state);

static long long with_parse_frame(napi_env env, Lib *lib, parse_body_fn body, void *state) {
  napi_ref callback = lib->dispatch_ref;
  if (callback == NULL) return body(state);
  long long status;
  if (parse_depth > MAX_PARSE_DEPTH) {
    napi_handle_scope scope;
    napi_value function;
    napi_value receiver;
    if (napi_open_handle_scope(env, &scope) != napi_ok) return -8;
    if (napi_get_reference_value(env, callback, &function) != napi_ok) {
      napi_close_handle_scope(env, scope);
      return -8;
    }
    if (napi_get_undefined(env, &receiver) != napi_ok) {
      napi_close_handle_scope(env, scope);
      return -8;
    }
    parse_depth++;
    parse_frames[MAX_PARSE_DEPTH].function = function;
    parse_frames[MAX_PARSE_DEPTH].receiver = receiver;
    active_env = env;
    status = body(state);
    active_env = parse_depth > 1 ? env : NULL;
    napi_close_handle_scope(env, scope);
    parse_depth--;
    return status;
  }
  bool outermost = parse_depth == 0;
  ParseFrame *frame = &parse_frames[parse_depth];
  if (outermost) {
    if (napi_open_handle_scope(env, &frame->scope) != napi_ok) return -8;
    frame->owns_scope = true;
  } else {
    frame->owns_scope = false;
  }
  if (napi_get_reference_value(env, callback, &frame->function) != napi_ok) {
    if (outermost) napi_close_handle_scope(env, frame->scope);
    return -8;
  }
  if (napi_get_undefined(env, &frame->receiver) != napi_ok) {
    if (outermost) napi_close_handle_scope(env, frame->scope);
    return -8;
  }
  parse_depth++;
  active_env = env;
  status = body(state);
  parse_depth--;
  active_env = parse_depth > 0 ? env : NULL;
  if (frame->owns_scope) napi_close_handle_scope(env, frame->scope);
  return status;
}

/* ------------------------------------------------------------------ */
/* Method binding plumbing.                                            */
/* ------------------------------------------------------------------ */

typedef napi_value (*Method)(napi_env env, Lib *lib, size_t argc, napi_value *argv);

typedef struct Binding {
  Lib *lib;
  Method method;
} Binding;

static napi_value thunk(napi_env env, napi_callback_info info) {
  void *data = NULL;
  size_t argc = 0;
  if (napi_get_cb_info(env, info, &argc, NULL, NULL, &data) != napi_ok) return NULL;
  Binding *binding = (Binding *)data;
  napi_value stack[8];
  napi_value *argv = stack;
  napi_value *heap = NULL;
  if (argc > 8) {
    heap = (napi_value *)malloc(argc * sizeof(napi_value));
    if (heap == NULL) {
      napi_throw_error(env, NULL, "out of memory");
      return NULL;
    }
    argv = heap;
  }
  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok) {
    free(heap);
    return NULL;
  }
  napi_value out = binding->method(env, binding->lib, argc, argv);
  free(heap);
  return out;
}

/* Binds name on obj to method with this library. Binding records live as
 * long as the process (one set per loaded library path, like the dl
 * handle they belong to). */
static bool bind(napi_env env, napi_value obj, Lib *lib, const char *name, Method method,
                 const char *symbol) {
  Binding *binding = (Binding *)malloc(sizeof(Binding));
  if (binding == NULL) {
    napi_throw_error(env, NULL, "out of memory");
    return false;
  }
  binding->lib = lib;
  binding->method = method;
  napi_value function;
  if (napi_create_function(env, name, NAPI_AUTO_LENGTH, thunk, binding, &function) != napi_ok) {
    free(binding);
    return false;
  }
  if (napi_set_named_property(env, obj, name, function) != napi_ok) return false;
  if (lib->bound_count >= 192) {
    napi_throw_error(env, NULL, "too many bound functions");
    return false;
  }
  // symbol is the parser-library export to verify (NULL means the api
  // name is the export name, as for every galley_* function).
  lib->bound_names[lib->bound_count++] = symbol == NULL ? name : symbol;
  return true;
}

static bool bind_null(napi_env env, napi_value obj, const char *name) {
  napi_value null_value;
  if (napi_get_null(env, &null_value) != napi_ok) return false;
  if (napi_set_named_property(env, obj, name, null_value) != napi_ok) return false;
  return true;
}

/* ------------------------------------------------------------------ */
/* Argument readers.                                                   */
/* ------------------------------------------------------------------ */

static bool session_arg(napi_env env, size_t argc, napi_value *argv, GalleySession **out) {
  if (argc < 1) {
    napi_throw_type_error(env, NULL, "expected session");
    return false;
  }
  uint64_t address = 0;
  if (!get_u64(env, argv[0], &address)) return false;
  *out = (GalleySession *)(uintptr_t)address;
  return true;
}

static bool args_arg(napi_env env, size_t argc, napi_value *argv, void **out) {
  if (argc < 1) {
    napi_throw_type_error(env, NULL, "expected args");
    return false;
  }
  uint64_t address = 0;
  if (!get_u64(env, argv[0], &address)) return false;
  *out = (void *)(uintptr_t)address;
  return true;
}

static napi_value make_null(napi_env env) {
  napi_value null_value;
  if (napi_get_null(env, &null_value) != napi_ok) return NULL;
  return null_value;
}

/* (data, len) out-pair with a status gate: negative fails, NULL data fails. */
static napi_value out_bytes(napi_env env, long long status, const char *data, size_t len) {
  if (status < 0) return make_null(env);
  return make_buffer_or_null(env, data, len);
}

static napi_value out_string(napi_env env, long long status, const char *data, size_t len) {
  if (status < 0 || data == NULL) return make_null(env);
  napi_value out;
  if (napi_create_string_utf8(env, data, len, &out) != napi_ok) return NULL;
  return out;
}

/* NUL-terminated out-string with a nonzero-status gate (diagnostic text). */
static napi_value message_or_null(napi_env env, long long status, const char *text) {
  if (status != 0) return make_null(env);
  return make_string_or_null(env, text);
}

static napi_value pair_u64_or_null(napi_env env, long long status, uint64_t first, uint64_t second) {
  if (status < 0) return make_null(env);
  napi_value pair;
  napi_value first_value = make_u64(env, first);
  napi_value second_value = make_u64(env, second);
  if (first_value == NULL || second_value == NULL) return NULL;
  if (napi_create_array_with_length(env, 2, &pair) != napi_ok) return NULL;
  if (napi_set_element(env, pair, 0, first_value) != napi_ok) return NULL;
  if (napi_set_element(env, pair, 1, second_value) != napi_ok) return NULL;
  return pair;
}

static napi_value pair_u32_or_null(napi_env env, long long status, uint32_t first, uint32_t second) {
  if (status < 0) return make_null(env);
  napi_value pair;
  napi_value first_value = make_u32(env, first);
  napi_value second_value = make_u32(env, second);
  if (first_value == NULL || second_value == NULL) return NULL;
  if (napi_create_array_with_length(env, 2, &pair) != napi_ok) return NULL;
  if (napi_set_element(env, pair, 0, first_value) != napi_ok) return NULL;
  if (napi_set_element(env, pair, 1, second_value) != napi_ok) return NULL;
  return pair;
}

static napi_value pair_string_or_null(napi_env env, long long status, const char *variable,
                                      size_t variable_len, const char *message, size_t message_len) {
  if (status < 0 || variable == NULL || message == NULL) return make_null(env);
  napi_value pair;
  napi_value variable_value;
  napi_value message_value;
  if (napi_create_string_utf8(env, variable, variable_len, &variable_value) != napi_ok) return NULL;
  if (napi_create_string_utf8(env, message, message_len, &message_value) != napi_ok) return NULL;
  if (napi_create_array_with_length(env, 2, &pair) != napi_ok) return NULL;
  if (napi_set_element(env, pair, 0, variable_value) != napi_ok) return NULL;
  if (napi_set_element(env, pair, 1, message_value) != napi_ok) return NULL;
  return pair;
}

/* ------------------------------------------------------------------ */
/* Repetitive getters via X-macros: one mapping of the C ABI.          */
/* ------------------------------------------------------------------ */

#define NO_ARG_I64(cfn)                                                                    \
  static napi_value method_##cfn(napi_env env, Lib *lib, size_t argc, napi_value *argv) {   \
    (void)lib;                                                                             \
    (void)argc;                                                                            \
    (void)argv;                                                                            \
    return make_i64(env, (int64_t)cfn());                                                  \
  }

#define NO_ARG_U64(cfn)                                                                    \
  static napi_value method_##cfn(napi_env env, Lib *lib, size_t argc, napi_value *argv) {   \
    (void)lib;                                                                             \
    (void)argc;                                                                            \
    (void)argv;                                                                            \
    return make_u64(env, (uint64_t)cfn());                                                 \
  }

#define NO_ARG_INT(cfn)                                                                    \
  static napi_value method_##cfn(napi_env env, Lib *lib, size_t argc, napi_value *argv) {   \
    (void)lib;                                                                             \
    (void)argc;                                                                            \
    (void)argv;                                                                            \
    return make_i32(env, (int32_t)cfn());                                                  \
  }

#define SESS_U64(cfn)                                                                      \
  static napi_value method_##cfn(napi_env env, Lib *lib, size_t argc, napi_value *argv) {   \
    (void)lib;                                                                             \
    GalleySession *session = NULL;                                                         \
    if (!session_arg(env, argc, argv, &session)) return NULL;                              \
    return make_u64(env, (uint64_t)cfn(session));                                          \
  }

#define SESS_I64(cfn)                                                                      \
  static napi_value method_##cfn(napi_env env, Lib *lib, size_t argc, napi_value *argv) {   \
    (void)lib;                                                                             \
    GalleySession *session = NULL;                                                         \
    if (!session_arg(env, argc, argv, &session)) return NULL;                              \
    return make_i64(env, (int64_t)cfn(session));                                           \
  }

#define SESS_INT(cfn)                                                                      \
  static napi_value method_##cfn(napi_env env, Lib *lib, size_t argc, napi_value *argv) {   \
    (void)lib;                                                                             \
    GalleySession *session = NULL;                                                         \
    if (!session_arg(env, argc, argv, &session)) return NULL;                              \
    return make_i32(env, (int32_t)cfn(session));                                           \
  }

#define SESS_NODE_U64(cfn)                                                                 \
  static napi_value method_##cfn(napi_env env, Lib *lib, size_t argc, napi_value *argv) {   \
    (void)lib;                                                                             \
    GalleySession *session = NULL;                                                         \
    if (!session_arg(env, argc, argv, &session)) return NULL;                              \
    if (argc < 2) {                                                                        \
      napi_throw_type_error(env, NULL, "expected node");                                   \
      return NULL;                                                                         \
    }                                                                                      \
    uint64_t node = 0;                                                                     \
    if (!get_u64(env, argv[1], &node)) return NULL;                                        \
    return make_u64(env, (uint64_t)cfn(session, (GalleyNodeAddress)node));                 \
  }

#define SESS_NODE_I64(cfn)                                                                 \
  static napi_value method_##cfn(napi_env env, Lib *lib, size_t argc, napi_value *argv) {   \
    (void)lib;                                                                             \
    GalleySession *session = NULL;                                                         \
    if (!session_arg(env, argc, argv, &session)) return NULL;                              \
    if (argc < 2) {                                                                        \
      napi_throw_type_error(env, NULL, "expected node");                                   \
      return NULL;                                                                         \
    }                                                                                      \
    uint64_t node = 0;                                                                     \
    if (!get_u64(env, argv[1], &node)) return NULL;                                        \
    return make_i64(env, (int64_t)cfn(session, (GalleyNodeAddress)node));                  \
  }

#define SESS_NODE_INT(cfn)                                                                 \
  static napi_value method_##cfn(napi_env env, Lib *lib, size_t argc, napi_value *argv) {   \
    (void)lib;                                                                             \
    GalleySession *session = NULL;                                                         \
    if (!session_arg(env, argc, argv, &session)) return NULL;                              \
    if (argc < 2) {                                                                        \
      napi_throw_type_error(env, NULL, "expected node");                                   \
      return NULL;                                                                         \
    }                                                                                      \
    uint64_t node = 0;                                                                     \
    if (!get_u64(env, argv[1], &node)) return NULL;                                        \
    return make_i32(env, (int32_t)cfn(session, (GalleyNodeAddress)node));                  \
  }

#define SESS_NODE_U32(cfn)                                                                 \
  static napi_value method_##cfn(napi_env env, Lib *lib, size_t argc, napi_value *argv) {   \
    (void)lib;                                                                             \
    GalleySession *session = NULL;                                                         \
    if (!session_arg(env, argc, argv, &session)) return NULL;                              \
    if (argc < 2) {                                                                        \
      napi_throw_type_error(env, NULL, "expected node");                                   \
      return NULL;                                                                         \
    }                                                                                      \
    uint64_t node = 0;                                                                     \
    if (!get_u64(env, argv[1], &node)) return NULL;                                        \
    return make_u32(env, (uint32_t)cfn(session, (GalleyNodeAddress)node));                 \
  }

#define SESS_INDEX_I64(cfn)                                                                \
  static napi_value method_##cfn(napi_env env, Lib *lib, size_t argc, napi_value *argv) {   \
    (void)lib;                                                                             \
    GalleySession *session = NULL;                                                         \
    if (!session_arg(env, argc, argv, &session)) return NULL;                              \
    if (argc < 2) {                                                                        \
      napi_throw_type_error(env, NULL, "expected index");                                  \
      return NULL;                                                                         \
    }                                                                                      \
    uint64_t index = 0;                                                                    \
    if (!get_u64(env, argv[1], &index)) return NULL;                                       \
    return make_i64(env, (int64_t)cfn(session, index));                                    \
  }

#define ARGS_PTR(cfn)                                                                      \
  static napi_value method_##cfn(napi_env env, Lib *lib, size_t argc, napi_value *argv) {   \
    (void)lib;                                                                             \
    void *args = NULL;                                                                     \
    if (!args_arg(env, argc, argv, &args)) return NULL;                                    \
    return make_u64(env, (uint64_t)(uintptr_t)cfn(args));                                  \
  }

#define ARGS_U64(cfn)                                                                      \
  static napi_value method_##cfn(napi_env env, Lib *lib, size_t argc, napi_value *argv) {   \
    (void)lib;                                                                             \
    void *args = NULL;                                                                     \
    if (!args_arg(env, argc, argv, &args)) return NULL;                                    \
    return make_u64(env, (uint64_t)cfn(args));                                            \
  }

#define ARGS_I64(cfn)                                                                      \
  static napi_value method_##cfn(napi_env env, Lib *lib, size_t argc, napi_value *argv) {   \
    (void)lib;                                                                             \
    void *args = NULL;                                                                     \
    if (!args_arg(env, argc, argv, &args)) return NULL;                                    \
    return make_i64(env, (int64_t)cfn(args));                                             \
  }

#define ARGS_U32(cfn)                                                                      \
  static napi_value method_##cfn(napi_env env, Lib *lib, size_t argc, napi_value *argv) {   \
    (void)lib;                                                                             \
    void *args = NULL;                                                                     \
    if (!args_arg(env, argc, argv, &args)) return NULL;                                    \
    return make_u32(env, (uint32_t)cfn(args));                                            \
  }

NO_ARG_I64(galley_parser_type)
NO_ARG_I64(galley_error_recovery_mode)
NO_ARG_INT(galley_has_ast)
NO_ARG_INT(galley_has_procedures)
NO_ARG_INT(galley_allows_no_ast_tree_procedures)
NO_ARG_INT(galley_source_retention_enabled)
NO_ARG_INT(galley_has_position_tracking)
NO_ARG_INT(galley_has_input_streaming)
NO_ARG_INT(galley_uses_verbatim)
NO_ARG_INT(galley_stack_overflow_recovery_available)
NO_ARG_U64(galley_symbol_count)
NO_ARG_U64(galley_variable_count)

SESS_U64(galley_node_count)
SESS_U64(galley_node_capacity)
SESS_U64(galley_root_node)
SESS_NODE_U64(galley_node_first_child)
SESS_NODE_U64(galley_node_last_child)
SESS_NODE_U64(galley_node_next_sibling)
SESS_NODE_U64(galley_node_prior_sibling)
SESS_NODE_U64(galley_node_parent)
SESS_NODE_INT(galley_node_is_valid)
SESS_NODE_INT(galley_symbol_is_terminal)
SESS_NODE_U32(galley_node_child_count)
SESS_NODE_I64(galley_node_variable_index)
SESS_I64(galley_diagnostic_kind)
SESS_I64(galley_diagnostic_expected_count)
SESS_I64(galley_diagnostic_context_count)
SESS_INT(galley_has_diagnostic)
SESS_I64(galley_syntax_error_count)
SESS_I64(galley_semantic_error_count)
SESS_I64(galley_diagnostic_recovery_kind)
SESS_I64(galley_recorded_diagnostic_count)
SESS_INDEX_I64(galley_recorded_diagnostic_kind)
SESS_INDEX_I64(galley_recorded_expected_count)
SESS_INDEX_I64(galley_recorded_context_count)
SESS_INDEX_I64(galley_recorded_diagnostic_recovery_kind)

ARGS_PTR(galley_procedure_session)
ARGS_U64(galley_procedure_current_node)
ARGS_I64(galley_procedure_drop_self)
ARGS_I64(galley_procedure_drop_children)
ARGS_I64(galley_procedure_drop_if_empty)
ARGS_I64(galley_procedure_replace_with_children)
ARGS_U32(galley_procedure_context_line)
ARGS_U32(galley_procedure_context_column)

/* ------------------------------------------------------------------ */
/* Custom methods: strings, buffers, tuples, options, parse, snapshot. */
/* ------------------------------------------------------------------ */

static napi_value method_galley_version(napi_env env, Lib *lib, size_t argc, napi_value *argv) {
  (void)lib;
  (void)argc;
  (void)argv;
  return make_string_or_null(env, galley_version());
}

static napi_value method_galley_status_string(napi_env env, Lib *lib, size_t argc, napi_value *argv) {
  (void)lib;
  if (argc < 1) {
    napi_throw_type_error(env, NULL, "expected status");
    return NULL;
  }
  int64_t status = 0;
  if (!get_i64(env, argv[0], &status)) return NULL;
  return make_string_or_null(env, galley_status_string(status));
}

static napi_value method_galley_symbol_name(napi_env env, Lib *lib, size_t argc, napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected index");
    return NULL;
  }
  uint64_t index = 0;
  if (!get_u64(env, argv[1], &index)) return NULL;
  const char *data = NULL;
  size_t len = 0;
  long long status = galley_symbol_name(session, index, &data, &len);
  return out_bytes(env, status, data, len);
}

static napi_value method_galley_variable_name(napi_env env, Lib *lib, size_t argc, napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected index");
    return NULL;
  }
  uint64_t index = 0;
  if (!get_u64(env, argv[1], &index)) return NULL;
  const char *data = NULL;
  size_t len = 0;
  long long status = galley_variable_name(session, index, &data, &len);
  return out_bytes(env, status, data, len);
}

static napi_value method_galley_session_create(napi_env env, Lib *lib, size_t argc, napi_value *argv) {
  (void)lib;
  (void)argc;
  (void)argv;
  return make_u64(env, (uint64_t)(uintptr_t)galley_session_create());
}

static bool options_arg(napi_env env, napi_value value, GalleyCOptions *out) {
  napi_value field;
  int32_t max_errors = 0;
  int32_t recovery_window = 0;
  int32_t stack_overflow_recovery = 0;
  uint32_t syntax_error_stack_depth = 0;
  int32_t verbosity = 0;
  double ast_preallocation_ratio = 0;
  uint64_t ast_preallocation_cap = 0;
  if (napi_get_named_property(env, value, "maxErrors", &field) != napi_ok ||
      napi_get_value_int32(env, field, &max_errors) != napi_ok ||
      napi_get_named_property(env, value, "recoveryWindow", &field) != napi_ok ||
      napi_get_value_int32(env, field, &recovery_window) != napi_ok ||
      napi_get_named_property(env, value, "stackOverflowRecovery", &field) != napi_ok ||
      napi_get_value_int32(env, field, &stack_overflow_recovery) != napi_ok ||
      napi_get_named_property(env, value, "syntaxErrorStackDepth", &field) != napi_ok ||
      napi_get_value_uint32(env, field, &syntax_error_stack_depth) != napi_ok ||
      napi_get_named_property(env, value, "verbosity", &field) != napi_ok ||
      napi_get_value_int32(env, field, &verbosity) != napi_ok ||
      napi_get_named_property(env, value, "astPreallocationRatio", &field) != napi_ok ||
      napi_get_value_double(env, field, &ast_preallocation_ratio) != napi_ok ||
      napi_get_named_property(env, value, "astPreallocationCap", &field) != napi_ok) {
    napi_throw_type_error(env, NULL, "expected session options");
    return false;
  }
  if (!get_u64(env, field, &ast_preallocation_cap)) return false;
  out->max_errors = max_errors;
  out->recovery_window = recovery_window;
  out->stack_overflow_recovery = stack_overflow_recovery;
  out->syntax_error_stack_depth = syntax_error_stack_depth;
  out->verbosity = verbosity;
  out->ast_preallocation_ratio = ast_preallocation_ratio;
  out->ast_preallocation_cap = (unsigned long long)ast_preallocation_cap;
  return true;
}

static napi_value method_galley_session_create_ex(napi_env env, Lib *lib, size_t argc,
                                                 napi_value *argv) {
  (void)lib;
  if (argc < 1) {
    napi_throw_type_error(env, NULL, "expected options");
    return NULL;
  }
  GalleyCOptions options;
  if (!options_arg(env, argv[0], &options)) return NULL;
  return make_u64(env, (uint64_t)(uintptr_t)galley_session_create_ex(&options));
}

static napi_value method_galley_session_destroy(napi_env env, Lib *lib, size_t argc,
                                               napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  galley_session_destroy(session);
  napi_value undefined_value;
  if (napi_get_undefined(env, &undefined_value) != napi_ok) return NULL;
  return undefined_value;
}

static napi_value method_galley_session_set_message_override(napi_env env, Lib *lib, size_t argc,
                                                            napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 3) {
    napi_throw_type_error(env, NULL, "expected name and message");
    return NULL;
  }
  char *name = NULL;
  size_t name_len = 0;
  char *message = NULL;
  size_t message_len = 0;
  if (!get_utf8(env, argv[1], &name, &name_len)) return NULL;
  if (!get_utf8(env, argv[2], &message, &message_len)) {
    free(name);
    return NULL;
  }
  long long status =
      galley_session_set_message_override(session, name, name_len, message, message_len);
  free(name);
  free(message);
  return make_i64(env, status);
}

typedef struct ParseState {
  GalleySession *session;
  const char *data;
  size_t len;
} ParseState;

static long long parse_body(void *state) {
  ParseState *parse = (ParseState *)state;
  return galley_parse(parse->session, parse->data, parse->len);
}

static napi_value method_galley_parse(napi_env env, Lib *lib, size_t argc, napi_value *argv) {
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected input");
    return NULL;
  }
  // Any Uint8Array view (Buffer included): the port contract is bytes,
  // not the Node subclass. The data pointer already accounts for the
  // view's byte offset; the parse copies what it retains.
  napi_typedarray_type view_type;
  size_t length = 0;
  void *data = NULL;
  napi_value buffer;
  size_t byte_offset = 0;
  if (napi_get_typedarray_info(env, argv[1], &view_type, &length, &data, &buffer,
                               &byte_offset) != napi_ok ||
      view_type != napi_uint8_array || (data == NULL && length != 0)) {
    napi_throw_type_error(env, NULL, "expected input bytes");
    return NULL;
  }
  ParseState state = {session, (const char *)data, length};
  return make_i64(env, with_parse_frame(env, lib, parse_body, &state));
}

static napi_value method_galley_parse_sentinel(napi_env env, Lib *lib, size_t argc,
                                              napi_value *argv) {
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected input");
    return NULL;
  }
  char *input = NULL;
  size_t input_len = 0;
  if (!get_utf8(env, argv[1], &input, &input_len)) return NULL;
  // NUL-terminate: get_utf8 already reserves the terminator slot.
  ParseState state = {session, input, input_len};
  long long status = with_parse_frame(env, lib, parse_body, &state);
  free(input);
  return make_i64(env, status);
}

typedef struct FileState {
  GalleySession *session;
  const char *path;
} FileState;

static long long parse_file_body(void *state) {
  FileState *file = (FileState *)state;
  return galley_parse_file(file->session, file->path);
}

static napi_value method_galley_parse_file(napi_env env, Lib *lib, size_t argc, napi_value *argv) {
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected path");
    return NULL;
  }
  char *path = NULL;
  size_t path_len = 0;
  if (!get_utf8(env, argv[1], &path, &path_len)) return NULL;
  FileState state = {session, path};
  long long status = with_parse_frame(env, lib, parse_file_body, &state);
  free(path);
  (void)path_len;
  return make_i64(env, status);
}

static napi_value method_galley_last_position(napi_env env, Lib *lib, size_t argc,
                                             napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  unsigned int line = 0;
  unsigned int column = 0;
  long long status = galley_last_position(session, &line, &column);
  return pair_u32_or_null(env, status, line, column);
}

static napi_value method_galley_node_span(napi_env env, Lib *lib, size_t argc, napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected node");
    return NULL;
  }
  uint64_t node = 0;
  if (!get_u64(env, argv[1], &node)) return NULL;
  unsigned long long start = 0;
  unsigned long long len = 0;
  long long status = galley_node_span(session, (GalleyNodeAddress)node, &start, &len);
  return pair_u64_or_null(env, status, (uint64_t)start, (uint64_t)len);
}

static napi_value method_galley_node_symbol_name(napi_env env, Lib *lib, size_t argc,
                                                napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected node");
    return NULL;
  }
  uint64_t node = 0;
  if (!get_u64(env, argv[1], &node)) return NULL;
  const char *data = NULL;
  size_t len = 0;
  long long status = galley_node_symbol_name(session, (GalleyNodeAddress)node, &data, &len);
  return out_bytes(env, status, data, len);
}

static napi_value method_galley_node_text(napi_env env, Lib *lib, size_t argc, napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected node");
    return NULL;
  }
  uint64_t node = 0;
  if (!get_u64(env, argv[1], &node)) return NULL;
  const char *data = NULL;
  size_t len = 0;
  long long status = galley_node_text(session, (GalleyNodeAddress)node, &data, &len);
  return out_bytes(env, status, data, len);
}

static napi_value method_galley_node_line_column(napi_env env, Lib *lib, size_t argc,
                                                napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected node");
    return NULL;
  }
  uint64_t node = 0;
  if (!get_u64(env, argv[1], &node)) return NULL;
  unsigned int line = 0;
  unsigned int column = 0;
  long long status = galley_node_line_column(session, (GalleyNodeAddress)node, &line, &column);
  return pair_u32_or_null(env, status, line, column);
}

static bool typed_column(napi_env env, napi_value array, napi_typedarray_type want, void **data) {
  napi_typedarray_type got;
  size_t length = 0;
  void *bytes = NULL;
  napi_value buffer;
  size_t byte_offset = 0;
  if (napi_get_typedarray_info(env, array, &got, &length, &bytes, &buffer, &byte_offset) !=
          napi_ok ||
      got != want) {
    napi_throw_type_error(env, NULL, "expected matching typed array");
    return false;
  }
  *data = bytes;
  return true;
}

static napi_value method_galley_tree_snapshot(napi_env env, Lib *lib, size_t argc,
                                             napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 9) {
    napi_throw_type_error(env, NULL, "expected snapshot columns and capacity");
    return NULL;
  }
  void *parent = NULL;
  void *first_child = NULL;
  void *next = NULL;
  void *child_count = NULL;
  void *variable = NULL;
  void *span_start = NULL;
  void *span_len = NULL;
  if (!typed_column(env, argv[1], napi_biguint64_array, &parent)) return NULL;
  if (!typed_column(env, argv[2], napi_biguint64_array, &first_child)) return NULL;
  if (!typed_column(env, argv[3], napi_biguint64_array, &next)) return NULL;
  if (!typed_column(env, argv[4], napi_uint32_array, &child_count)) return NULL;
  if (!typed_column(env, argv[5], napi_bigint64_array, &variable)) return NULL;
  if (!typed_column(env, argv[6], napi_biguint64_array, &span_start)) return NULL;
  if (!typed_column(env, argv[7], napi_biguint64_array, &span_len)) return NULL;
  uint64_t capacity = 0;
  if (!get_u64(env, argv[8], &capacity)) return NULL;
  long long status = galley_tree_snapshot(
      session, (GalleyNodeAddress *)parent, (GalleyNodeAddress *)first_child,
      (GalleyNodeAddress *)next, (unsigned int *)child_count, (long long *)variable,
      (unsigned long long *)span_start, (unsigned long long *)span_len,
      (unsigned long long)capacity);
  return make_i64(env, status);
}

static napi_value method_galley_walker_create(napi_env env, Lib *lib, size_t argc,
                                             napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 3) {
    napi_throw_type_error(env, NULL, "expected node and flags");
    return NULL;
  }
  uint64_t node = 0;
  int32_t skip = 0;
  if (!get_u64(env, argv[1], &node)) return NULL;
  if (!get_i32(env, argv[2], &skip)) return NULL;
  return make_u64(env, (uint64_t)(uintptr_t)galley_walker_create(session, (GalleyNodeAddress)node,
                                                                (int)skip));
}

static napi_value method_galley_walker_next(napi_env env, Lib *lib, size_t argc, napi_value *argv) {
  (void)lib;
  if (argc < 1) {
    napi_throw_type_error(env, NULL, "expected walker");
    return NULL;
  }
  uint64_t address = 0;
  if (!get_u64(env, argv[0], &address)) return NULL;
  GalleyWalker *walker = (GalleyWalker *)(uintptr_t)address;
  GalleyNodeAddress node = 0;
  unsigned int depth = 0;
  int is_semantic_error = 0;
  int yielded = galley_walker_next(walker, &node, &depth, &is_semantic_error);
  if (yielded == 0) return make_null(env);
  napi_value triple;
  napi_value node_value = make_u64(env, (uint64_t)node);
  napi_value depth_value = make_u32(env, depth);
  napi_value flag_value = make_i32(env, (int32_t)is_semantic_error);
  if (node_value == NULL || depth_value == NULL || flag_value == NULL) return NULL;
  if (napi_create_array_with_length(env, 3, &triple) != napi_ok) return NULL;
  if (napi_set_element(env, triple, 0, node_value) != napi_ok) return NULL;
  if (napi_set_element(env, triple, 1, depth_value) != napi_ok) return NULL;
  if (napi_set_element(env, triple, 2, flag_value) != napi_ok) return NULL;
  return triple;
}

static napi_value method_galley_walker_skip_children(napi_env env, Lib *lib, size_t argc,
                                                    napi_value *argv) {
  (void)lib;
  if (argc < 1) {
    napi_throw_type_error(env, NULL, "expected walker");
    return NULL;
  }
  uint64_t address = 0;
  if (!get_u64(env, argv[0], &address)) return NULL;
  galley_walker_skip_children((GalleyWalker *)(uintptr_t)address);
  napi_value undefined_value;
  if (napi_get_undefined(env, &undefined_value) != napi_ok) return NULL;
  return undefined_value;
}

static napi_value method_galley_walker_destroy(napi_env env, Lib *lib, size_t argc,
                                              napi_value *argv) {
  (void)lib;
  if (argc < 1) {
    napi_throw_type_error(env, NULL, "expected walker");
    return NULL;
  }
  uint64_t address = 0;
  if (!get_u64(env, argv[0], &address)) return NULL;
  galley_walker_destroy((GalleyWalker *)(uintptr_t)address);
  napi_value undefined_value;
  if (napi_get_undefined(env, &undefined_value) != napi_ok) return NULL;
  return undefined_value;
}

static napi_value method_galley_diagnostic_message(napi_env env, Lib *lib, size_t argc,
                                                  napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  const char *text = NULL;
  long long status = galley_diagnostic_message(session, &text);
  return message_or_null(env, status, text);
}

static napi_value method_galley_diagnostic_message_ansi(napi_env env, Lib *lib, size_t argc,
                                                       napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  const char *text = NULL;
  long long status = galley_diagnostic_message_ansi(session, &text);
  return message_or_null(env, status, text);
}

static napi_value method_galley_diagnostic_position(napi_env env, Lib *lib, size_t argc,
                                                   napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  unsigned int line = 0;
  unsigned int column = 0;
  long long status = galley_diagnostic_position(session, &line, &column);
  return pair_u32_or_null(env, status, line, column);
}

static napi_value method_galley_diagnostic_unexpected_token(napi_env env, Lib *lib, size_t argc,
                                                           napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  const char *data = NULL;
  size_t len = 0;
  long long status = galley_diagnostic_unexpected_token(session, &data, &len);
  return out_bytes(env, status, data, len);
}

static napi_value method_galley_diagnostic_expected_at(napi_env env, Lib *lib, size_t argc,
                                                      napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected index");
    return NULL;
  }
  uint64_t index = 0;
  if (!get_u64(env, argv[1], &index)) return NULL;
  const char *data = NULL;
  size_t len = 0;
  long long status = galley_diagnostic_expected_at(session, index, &data, &len);
  return out_bytes(env, status, data, len);
}

static napi_value method_galley_diagnostic_context_at(napi_env env, Lib *lib, size_t argc,
                                                     napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected index");
    return NULL;
  }
  uint64_t index = 0;
  if (!get_u64(env, argv[1], &index)) return NULL;
  const char *data = NULL;
  size_t len = 0;
  long long status = galley_diagnostic_context_at(session, index, &data, &len);
  return out_bytes(env, status, data, len);
}

static napi_value method_galley_diagnostic_semantic(napi_env env, Lib *lib, size_t argc,
                                                   napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  const char *variable = NULL;
  size_t variable_len = 0;
  const char *message = NULL;
  size_t message_len = 0;
  long long status = galley_diagnostic_semantic(session, &variable, &variable_len, &message,
                                                &message_len);
  return pair_string_or_null(env, status, variable, variable_len, message, message_len);
}

static napi_value method_galley_diagnostic_indentation(napi_env env, Lib *lib, size_t argc,
                                                      napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  unsigned int spaces = 0;
  unsigned int width = 0;
  long long status = galley_diagnostic_indentation(session, &spaces, &width);
  // Indentation reports nonzero status without an indentation diagnostic.
  if (status != 0) return make_null(env);
  return pair_u32_or_null(env, 0, spaces, width);
}

static napi_value method_galley_diagnostic_recovery_terminal(napi_env env, Lib *lib, size_t argc,
                                                            napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  const char *data = NULL;
  size_t len = 0;
  long long status = galley_diagnostic_recovery_terminal(session, &data, &len);
  return out_bytes(env, status, data, len);
}

static napi_value method_galley_diagnostic_recovery_resume(napi_env env, Lib *lib, size_t argc,
                                                          napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  long long value = 0;
  long long status = galley_diagnostic_recovery_resume(session, &value);
  if (status != 0) return make_null(env);
  napi_value out;
  // Resume targets are 0/1; the port contract is number.
  if (napi_create_double(env, (double)value, &out) != napi_ok) return NULL;
  return out;
}

static napi_value method_galley_diagnostic_recovery_lhs_variable(napi_env env, Lib *lib,
                                                                size_t argc, napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  const char *data = NULL;
  size_t len = 0;
  long long status = galley_diagnostic_recovery_lhs_variable(session, &data, &len);
  return out_string(env, status, data, len);
}

static napi_value method_galley_diagnostic_recovery_production(napi_env env, Lib *lib, size_t argc,
                                                              napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  const char *variable = NULL;
  size_t variable_len = 0;
  unsigned int rhs_index = 0;
  long long status =
      galley_diagnostic_recovery_production(session, &variable, &variable_len, &rhs_index);
  if (status != 0 || variable == NULL) return make_null(env);
  napi_value pair;
  napi_value variable_value;
  napi_value index_value = make_u32(env, rhs_index);
  if (napi_create_string_utf8(env, variable, variable_len, &variable_value) != napi_ok) return NULL;
  if (index_value == NULL) return NULL;
  if (napi_create_array_with_length(env, 2, &pair) != napi_ok) return NULL;
  if (napi_set_element(env, pair, 0, variable_value) != napi_ok) return NULL;
  if (napi_set_element(env, pair, 1, index_value) != napi_ok) return NULL;
  return pair;
}

static napi_value quad_or_null(napi_env env, long long status, const char *parent,
                               size_t parent_len, unsigned int rhs, unsigned int sym,
                               const char *variable, size_t variable_len) {
  if (status != 0) return make_null(env);
  if (parent == NULL || variable == NULL) return make_null(env);
  napi_value quad;
  napi_value parent_value;
  napi_value rhs_value = make_u32(env, rhs);
  napi_value sym_value = make_u32(env, sym);
  napi_value variable_value;
  if (napi_create_string_utf8(env, parent, parent_len, &parent_value) != napi_ok) return NULL;
  if (rhs_value == NULL || sym_value == NULL) return NULL;
  if (napi_create_string_utf8(env, variable, variable_len, &variable_value) != napi_ok) return NULL;
  if (napi_create_array_with_length(env, 4, &quad) != napi_ok) return NULL;
  if (napi_set_element(env, quad, 0, parent_value) != napi_ok) return NULL;
  if (napi_set_element(env, quad, 1, rhs_value) != napi_ok) return NULL;
  if (napi_set_element(env, quad, 2, sym_value) != napi_ok) return NULL;
  if (napi_set_element(env, quad, 3, variable_value) != napi_ok) return NULL;
  return quad;
}

static napi_value method_galley_diagnostic_recovery_occurrence(napi_env env, Lib *lib, size_t argc,
                                                              napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  const char *parent = NULL;
  size_t parent_len = 0;
  unsigned int rhs = 0;
  unsigned int sym = 0;
  const char *variable = NULL;
  size_t variable_len = 0;
  long long status = galley_diagnostic_recovery_occurrence(session, &parent, &parent_len, &rhs,
                                                           &sym, &variable, &variable_len);
  return quad_or_null(env, status, parent, parent_len, rhs, sym, variable, variable_len);
}

/* Recorded diagnostics: one more index argument than the singular forms. */

static bool recorded_arg(napi_env env, size_t argc, napi_value *argv, GalleySession **session,
                         uint64_t *index) {
  if (!session_arg(env, argc, argv, session)) return false;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected diagnostic index");
    return false;
  }
  return get_u64(env, argv[1], index);
}

static napi_value method_galley_recorded_diagnostic_position(napi_env env, Lib *lib, size_t argc,
                                                            napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  uint64_t index = 0;
  if (!recorded_arg(env, argc, argv, &session, &index)) return NULL;
  unsigned int line = 0;
  unsigned int column = 0;
  long long status = galley_recorded_diagnostic_position(session, index, &line, &column);
  return pair_u32_or_null(env, status, line, column);
}

static napi_value method_galley_recorded_unexpected_token(napi_env env, Lib *lib, size_t argc,
                                                         napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  uint64_t index = 0;
  if (!recorded_arg(env, argc, argv, &session, &index)) return NULL;
  const char *data = NULL;
  size_t len = 0;
  long long status = galley_recorded_unexpected_token(session, index, &data, &len);
  return out_bytes(env, status, data, len);
}

static napi_value method_galley_recorded_diagnostic_message(napi_env env, Lib *lib, size_t argc,
                                                           napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  uint64_t index = 0;
  if (!recorded_arg(env, argc, argv, &session, &index)) return NULL;
  const char *text = NULL;
  long long status = galley_recorded_diagnostic_message(session, index, &text);
  return message_or_null(env, status, text);
}

static napi_value method_galley_recorded_indentation(napi_env env, Lib *lib, size_t argc,
                                                    napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  uint64_t index = 0;
  if (!recorded_arg(env, argc, argv, &session, &index)) return NULL;
  unsigned int spaces = 0;
  unsigned int width = 0;
  long long status = galley_recorded_indentation(session, index, &spaces, &width);
  if (status != 0) return make_null(env);
  return pair_u32_or_null(env, 0, spaces, width);
}

static napi_value method_galley_recorded_semantic(napi_env env, Lib *lib, size_t argc,
                                                 napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  uint64_t index = 0;
  if (!recorded_arg(env, argc, argv, &session, &index)) return NULL;
  const char *variable = NULL;
  size_t variable_len = 0;
  const char *message = NULL;
  size_t message_len = 0;
  long long status =
      galley_recorded_semantic(session, index, &variable, &variable_len, &message, &message_len);
  return pair_string_or_null(env, status, variable, variable_len, message, message_len);
}

static napi_value method_galley_recorded_expected_token(napi_env env, Lib *lib, size_t argc,
                                                       napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  uint64_t index = 0;
  if (!recorded_arg(env, argc, argv, &session, &index)) return NULL;
  if (argc < 3) {
    napi_throw_type_error(env, NULL, "expected token index");
    return NULL;
  }
  uint64_t token = 0;
  if (!get_u64(env, argv[2], &token)) return NULL;
  const char *data = NULL;
  size_t len = 0;
  long long status = galley_recorded_expected_token(session, index, token, &data, &len);
  return out_bytes(env, status, data, len);
}

static napi_value method_galley_recorded_context_name(napi_env env, Lib *lib, size_t argc,
                                                     napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  uint64_t index = 0;
  if (!recorded_arg(env, argc, argv, &session, &index)) return NULL;
  if (argc < 3) {
    napi_throw_type_error(env, NULL, "expected context index");
    return NULL;
  }
  uint64_t context = 0;
  if (!get_u64(env, argv[2], &context)) return NULL;
  const char *data = NULL;
  size_t len = 0;
  long long status = galley_recorded_context_name(session, index, context, &data, &len);
  return out_bytes(env, status, data, len);
}

static napi_value method_galley_recorded_recovery_terminal(napi_env env, Lib *lib, size_t argc,
                                                          napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  uint64_t index = 0;
  if (!recorded_arg(env, argc, argv, &session, &index)) return NULL;
  const char *data = NULL;
  size_t len = 0;
  long long status = galley_recorded_recovery_terminal(session, index, &data, &len);
  return out_bytes(env, status, data, len);
}

static napi_value method_galley_recorded_recovery_resume(napi_env env, Lib *lib, size_t argc,
                                                        napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  uint64_t index = 0;
  if (!recorded_arg(env, argc, argv, &session, &index)) return NULL;
  long long value = 0;
  long long status = galley_recorded_recovery_resume(session, index, &value);
  if (status != 0) return make_null(env);
  napi_value out;
  if (napi_create_double(env, (double)value, &out) != napi_ok) return NULL;
  return out;
}

static napi_value method_galley_recorded_recovery_lhs_variable(napi_env env, Lib *lib, size_t argc,
                                                              napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  uint64_t index = 0;
  if (!recorded_arg(env, argc, argv, &session, &index)) return NULL;
  const char *data = NULL;
  size_t len = 0;
  long long status = galley_recorded_recovery_lhs_variable(session, index, &data, &len);
  return out_string(env, status, data, len);
}

static napi_value method_galley_recorded_recovery_production(napi_env env, Lib *lib, size_t argc,
                                                            napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  uint64_t index = 0;
  if (!recorded_arg(env, argc, argv, &session, &index)) return NULL;
  const char *variable = NULL;
  size_t variable_len = 0;
  unsigned int rhs_index = 0;
  long long status =
      galley_recorded_recovery_production(session, index, &variable, &variable_len, &rhs_index);
  if (status != 0 || variable == NULL) return make_null(env);
  napi_value pair;
  napi_value variable_value;
  napi_value index_value = make_u32(env, rhs_index);
  if (napi_create_string_utf8(env, variable, variable_len, &variable_value) != napi_ok) return NULL;
  if (index_value == NULL) return NULL;
  if (napi_create_array_with_length(env, 2, &pair) != napi_ok) return NULL;
  if (napi_set_element(env, pair, 0, variable_value) != napi_ok) return NULL;
  if (napi_set_element(env, pair, 1, index_value) != napi_ok) return NULL;
  return pair;
}

static napi_value method_galley_recorded_recovery_occurrence(napi_env env, Lib *lib, size_t argc,
                                                            napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  uint64_t index = 0;
  if (!recorded_arg(env, argc, argv, &session, &index)) return NULL;
  const char *parent = NULL;
  size_t parent_len = 0;
  unsigned int rhs = 0;
  unsigned int sym = 0;
  const char *variable = NULL;
  size_t variable_len = 0;
  long long status = galley_recorded_recovery_occurrence(session, index, &parent, &parent_len,
                                                         &rhs, &sym, &variable, &variable_len);
  return quad_or_null(env, status, parent, parent_len, rhs, sym, variable, variable_len);
}

/* Tree editing. */

static napi_value method_galley_tree_append_children(napi_env env, Lib *lib, size_t argc,
                                                    napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 3) {
    napi_throw_type_error(env, NULL, "expected parent and first");
    return NULL;
  }
  uint64_t parent = 0;
  uint64_t first = 0;
  if (!get_u64(env, argv[1], &parent)) return NULL;
  if (!get_u64(env, argv[2], &first)) return NULL;
  return make_i64(env, galley_tree_append_children(session, (GalleyNodeAddress)parent,
                                                   (GalleyNodeAddress)first));
}

static napi_value method_galley_tree_insert_before(napi_env env, Lib *lib, size_t argc,
                                                  napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 3) {
    napi_throw_type_error(env, NULL, "expected target and first");
    return NULL;
  }
  uint64_t target = 0;
  uint64_t first = 0;
  if (!get_u64(env, argv[1], &target)) return NULL;
  if (!get_u64(env, argv[2], &first)) return NULL;
  return make_i64(env, galley_tree_insert_before(session, (GalleyNodeAddress)target,
                                                 (GalleyNodeAddress)first));
}

static napi_value method_galley_tree_insert_after(napi_env env, Lib *lib, size_t argc,
                                                 napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 3) {
    napi_throw_type_error(env, NULL, "expected target and first");
    return NULL;
  }
  uint64_t target = 0;
  uint64_t first = 0;
  if (!get_u64(env, argv[1], &target)) return NULL;
  if (!get_u64(env, argv[2], &first)) return NULL;
  return make_i64(env, galley_tree_insert_after(session, (GalleyNodeAddress)target,
                                                (GalleyNodeAddress)first));
}

static napi_value head_pair(napi_env env, long long status, GalleyNodeAddress head) {
  napi_value pair;
  napi_value status_value = make_i64(env, status);
  napi_value head_value = make_u64(env, (uint64_t)head);
  if (status_value == NULL || head_value == NULL) return NULL;
  if (napi_create_array_with_length(env, 2, &pair) != napi_ok) return NULL;
  if (napi_set_element(env, pair, 0, status_value) != napi_ok) return NULL;
  if (napi_set_element(env, pair, 1, head_value) != napi_ok) return NULL;
  return pair;
}

static napi_value method_galley_tree_remove_siblings(napi_env env, Lib *lib, size_t argc,
                                                    napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 3) {
    napi_throw_type_error(env, NULL, "expected node and count");
    return NULL;
  }
  uint64_t node = 0;
  uint64_t count = 0;
  if (!get_u64(env, argv[1], &node)) return NULL;
  if (!get_u64(env, argv[2], &count)) return NULL;
  GalleyNodeAddress head = 0;
  long long status =
      galley_tree_remove_siblings(session, (GalleyNodeAddress)node, (size_t)count, &head);
  return head_pair(env, status, head);
}

static napi_value method_galley_tree_remove_self(napi_env env, Lib *lib, size_t argc,
                                                napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected node");
    return NULL;
  }
  uint64_t node = 0;
  if (!get_u64(env, argv[1], &node)) return NULL;
  GalleyNodeAddress head = 0;
  long long status = galley_tree_remove_self(session, (GalleyNodeAddress)node, &head);
  return head_pair(env, status, head);
}

static napi_value method_galley_tree_promote_children_over_wrapper(napi_env env, Lib *lib,
                                                                  size_t argc, napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected wrapper");
    return NULL;
  }
  uint64_t wrapper = 0;
  if (!get_u64(env, argv[1], &wrapper)) return NULL;
  GalleyNodeAddress head = 0;
  long long status =
      galley_tree_promote_children_over_wrapper(session, (GalleyNodeAddress)wrapper, &head);
  return head_pair(env, status, head);
}

static napi_value method_galley_tree_clean_children(napi_env env, Lib *lib, size_t argc,
                                                   napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected node");
    return NULL;
  }
  uint64_t node = 0;
  if (!get_u64(env, argv[1], &node)) return NULL;
  GalleyNodeAddress head = 0;
  long long status = galley_tree_clean_children(session, (GalleyNodeAddress)node, &head);
  return head_pair(env, status, head);
}

static napi_value method_galley_tree_unlink_wrapper(napi_env env, Lib *lib, size_t argc,
                                                   napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected wrapper");
    return NULL;
  }
  uint64_t wrapper = 0;
  if (!get_u64(env, argv[1], &wrapper)) return NULL;
  return make_i64(env, galley_tree_unlink_wrapper(session, (GalleyNodeAddress)wrapper));
}

static napi_value method_galley_tree_insert_children_at(napi_env env, Lib *lib, size_t argc,
                                                       napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 4) {
    napi_throw_type_error(env, NULL, "expected parent, index, and first");
    return NULL;
  }
  uint64_t parent = 0;
  uint64_t index = 0;
  uint64_t first = 0;
  if (!get_u64(env, argv[1], &parent)) return NULL;
  if (!get_u64(env, argv[2], &index)) return NULL;
  if (!get_u64(env, argv[3], &first)) return NULL;
  return make_i64(env, galley_tree_insert_children_at(session, (GalleyNodeAddress)parent,
                                                      (size_t)index, (GalleyNodeAddress)first));
}

static napi_value method_galley_tree_remove_children_at(napi_env env, Lib *lib, size_t argc,
                                                       napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 4) {
    napi_throw_type_error(env, NULL, "expected parent, index, and count");
    return NULL;
  }
  uint64_t parent = 0;
  uint64_t index = 0;
  uint64_t count = 0;
  if (!get_u64(env, argv[1], &parent)) return NULL;
  if (!get_u64(env, argv[2], &index)) return NULL;
  if (!get_u64(env, argv[3], &count)) return NULL;
  GalleyNodeAddress head = 0;
  long long status = galley_tree_remove_children_at(session, (GalleyNodeAddress)parent,
                                                    (size_t)index, (size_t)count, &head);
  return head_pair(env, status, head);
}

/* Parse-time procedure helpers. */

static napi_value method_galley_procedure_set_current_node(napi_env env, Lib *lib, size_t argc,
                                                          napi_value *argv) {
  (void)lib;
  void *args = NULL;
  if (!args_arg(env, argc, argv, &args)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected node");
    return NULL;
  }
  uint64_t node = 0;
  if (!get_u64(env, argv[1], &node)) return NULL;
  galley_procedure_set_current_node(args, (GalleyNodeAddress)node);
  napi_value undefined_value;
  if (napi_get_undefined(env, &undefined_value) != napi_ok) return NULL;
  return undefined_value;
}

static napi_value method_galley_procedure_report_semantic_error(napi_env env, Lib *lib, size_t argc,
                                                               napi_value *argv) {
  (void)lib;
  void *args = NULL;
  if (!args_arg(env, argc, argv, &args)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected message");
    return NULL;
  }
  char *message = NULL;
  size_t message_len = 0;
  if (!get_utf8(env, argv[1], &message, &message_len)) return NULL;
  long long status = galley_procedure_report_semantic_error(args, message, message_len);
  free(message);
  return make_i64(env, status);
}

/* Optional JS-shim surface: bound only when the probed symbols exist. */

static napi_value method_install_id_dispatch(napi_env env, Lib *lib, size_t argc,
                                            napi_value *argv) {
  if (argc < 1) {
    napi_throw_type_error(env, NULL, "expected callback");
    return NULL;
  }
  napi_valuetype type;
  if (napi_typeof(env, argv[0], &type) != napi_ok || type != napi_function) {
    napi_throw_type_error(env, NULL, "expected callback");
    return NULL;
  }
  if (lib->id_callback != NULL) napi_delete_reference(env, lib->id_callback);
  lib->id_callback = NULL;
  if (napi_create_reference(env, argv[0], 1, &lib->id_callback) != napi_ok) return NULL;
  lib->dispatch_ref = lib->id_callback;
  lib->install_id(id_trampoline);
  napi_value undefined_value;
  if (napi_get_undefined(env, &undefined_value) != napi_ok) return NULL;
  return undefined_value;
}

static napi_value method_install_name_dispatch(napi_env env, Lib *lib, size_t argc,
                                              napi_value *argv) {
  if (argc < 1) {
    napi_throw_type_error(env, NULL, "expected callback");
    return NULL;
  }
  napi_valuetype type;
  if (napi_typeof(env, argv[0], &type) != napi_ok || type != napi_function) {
    napi_throw_type_error(env, NULL, "expected callback");
    return NULL;
  }
  if (lib->name_callback != NULL) napi_delete_reference(env, lib->name_callback);
  lib->name_callback = NULL;
  if (napi_create_reference(env, argv[0], 1, &lib->name_callback) != napi_ok) return NULL;
  lib->dispatch_ref = lib->name_callback;
  lib->install_name(name_trampoline);
  napi_value undefined_value;
  if (napi_get_undefined(env, &undefined_value) != napi_ok) return NULL;
  return undefined_value;
}

static napi_value method_galley_js_procedure_count(napi_env env, Lib *lib, size_t argc,
                                                  napi_value *argv) {
  (void)argc;
  (void)argv;
  return make_u32(env, lib->procedure_count());
}

static napi_value method_galley_js_procedure_name(napi_env env, Lib *lib, size_t argc,
                                                 napi_value *argv) {
  if (argc < 1) {
    napi_throw_type_error(env, NULL, "expected index");
    return NULL;
  }
  uint64_t index = 0;
  if (!get_u64(env, argv[0], &index)) return NULL;
  void *ptr = lib->procedure_name_ptr((uint32_t)index);
  if (ptr == NULL) return make_null(env);
  size_t len = lib->procedure_name_len((uint32_t)index);
  napi_value out;
  if (napi_create_string_utf8(env, (const char *)ptr, len, &out) != napi_ok) return NULL;
  return out;
}

static napi_value method_galley_js_procedure_enable(napi_env env, Lib *lib, size_t argc,
                                                   napi_value *argv) {
  if (argc < 1) {
    napi_throw_type_error(env, NULL, "expected name");
    return NULL;
  }
  char *name = NULL;
  size_t name_len = 0;
  if (!get_utf8(env, argv[0], &name, &name_len)) return NULL;
  int result = lib->procedure_enable(name, name_len);
  free(name);
  return make_i32(env, (int32_t)result);
}

static napi_value method_galley_js_procedure_clear(napi_env env, Lib *lib, size_t argc,
                                                  napi_value *argv) {
  (void)argc;
  (void)argv;
  lib->procedure_clear();
  napi_value undefined_value;
  if (napi_get_undefined(env, &undefined_value) != napi_ok) return NULL;
  return undefined_value;
}

/* ------------------------------------------------------------------ */
/* load(parserPath): one bound object per library.                     */
/* ------------------------------------------------------------------ */

// galley_reserve_nodes(session, capacity): the one (session, uint64)
// function without an X-macro shape.
static napi_value method_galley_reserve_nodes(napi_env env, Lib *lib, size_t argc,
                                             napi_value *argv) {
  (void)lib;
  GalleySession *session = NULL;
  if (!session_arg(env, argc, argv, &session)) return NULL;
  if (argc < 2) {
    napi_throw_type_error(env, NULL, "expected capacity");
    return NULL;
  }
  uint64_t capacity = 0;
  if (!get_u64(env, argv[1], &capacity)) return NULL;
  return make_i64(env, galley_reserve_nodes(session, (unsigned long long)capacity));
}

static void *probe_symbol(void *probe, const char *name) {
  dlerror();
  void *symbol = dlsym(probe, name);
  const char *error = dlerror();
  if (error != NULL || symbol == NULL) return NULL;
  return symbol;
}

#define BIND_OR_THROW(api, lib, cfn)                                   \
  do {                                                                 \
    if (!bind(env, api, lib, #cfn, method_##cfn, NULL)) return NULL;   \
  } while (0)

#define BIND_SHIM_OR_THROW(api, lib, name, method, symbol)              \
  do {                                                                  \
    if (!bind(env, api, lib, name, method, symbol)) return NULL;       \
  } while (0)

static napi_value method_load(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1];
  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok) return NULL;
  if (argc < 1) {
    napi_throw_type_error(env, NULL, "expected parser path");
    return NULL;
  }
  char *parser_path = NULL;
  size_t parser_path_len = 0;
  if (!get_utf8(env, argv[0], &parser_path, &parser_path_len)) return NULL;
  (void)parser_path_len;
  void *probe = dlopen(parser_path, RTLD_NOW | RTLD_LOCAL);
  free(parser_path);
  if (probe == NULL) {
    napi_throw_error(env, NULL, dlerror());
    return NULL;
  }
  Lib *lib = (Lib *)calloc(1, sizeof(Lib));
  if (lib == NULL) {
    dlclose(probe);
    napi_throw_error(env, NULL, "out of memory");
    return NULL;
  }
  lib->probe = probe;
  // Optional JS-shim symbols stay NULL on libraries that predate them.
  lib->install_id = (dispatch_id_fn)probe_symbol(probe, "galley_install_js_dispatch_id");
  lib->install_name = (dispatch_name_fn)probe_symbol(probe, "galley_install_js_dispatch");
  lib->procedure_count =
      (uint32_t(*)(void))probe_symbol(probe, "galley_js_procedure_count");
  lib->procedure_name_ptr =
      (void *(*)(uint32_t))probe_symbol(probe, "galley_js_procedure_name_ptr");
  lib->procedure_name_len =
      (size_t(*)(uint32_t))probe_symbol(probe, "galley_js_procedure_name_len");
  lib->procedure_enable =
      (int (*)(const char *, size_t))probe_symbol(probe, "galley_js_procedure_enable");
  lib->procedure_clear = (void (*)(void))probe_symbol(probe, "galley_js_procedure_clear");

  napi_value api;
  if (napi_create_object(env, &api) != napi_ok) {
    free(lib);
    return NULL;
  }
  BIND_OR_THROW(api, lib, galley_version);
  BIND_OR_THROW(api, lib, galley_parser_type);
  BIND_OR_THROW(api, lib, galley_error_recovery_mode);
  BIND_OR_THROW(api, lib, galley_has_ast);
  BIND_OR_THROW(api, lib, galley_has_procedures);
  BIND_OR_THROW(api, lib, galley_allows_no_ast_tree_procedures);
  BIND_OR_THROW(api, lib, galley_source_retention_enabled);
  BIND_OR_THROW(api, lib, galley_has_position_tracking);
  BIND_OR_THROW(api, lib, galley_has_input_streaming);
  BIND_OR_THROW(api, lib, galley_uses_verbatim);
  BIND_OR_THROW(api, lib, galley_stack_overflow_recovery_available);
  BIND_OR_THROW(api, lib, galley_symbol_count);
  BIND_OR_THROW(api, lib, galley_variable_count);
  BIND_OR_THROW(api, lib, galley_status_string);
  BIND_OR_THROW(api, lib, galley_symbol_name);
  BIND_OR_THROW(api, lib, galley_symbol_is_terminal);
  BIND_OR_THROW(api, lib, galley_variable_name);
  BIND_OR_THROW(api, lib, galley_session_create);
  BIND_OR_THROW(api, lib, galley_session_create_ex);
  BIND_OR_THROW(api, lib, galley_session_destroy);
  BIND_OR_THROW(api, lib, galley_session_set_message_override);
  BIND_OR_THROW(api, lib, galley_parse_sentinel);
  BIND_OR_THROW(api, lib, galley_parse);
  BIND_OR_THROW(api, lib, galley_parse_file);
  BIND_OR_THROW(api, lib, galley_last_position);
  BIND_OR_THROW(api, lib, galley_node_count);
  BIND_OR_THROW(api, lib, galley_node_capacity);
  BIND_OR_THROW(api, lib, galley_root_node);
  BIND_OR_THROW(api, lib, galley_node_is_valid);
  BIND_OR_THROW(api, lib, galley_node_child_count);
  BIND_OR_THROW(api, lib, galley_node_first_child);
  BIND_OR_THROW(api, lib, galley_node_last_child);
  BIND_OR_THROW(api, lib, galley_node_next_sibling);
  BIND_OR_THROW(api, lib, galley_node_prior_sibling);
  BIND_OR_THROW(api, lib, galley_node_parent);
  BIND_OR_THROW(api, lib, galley_walker_create);
  BIND_OR_THROW(api, lib, galley_walker_next);
  BIND_OR_THROW(api, lib, galley_walker_skip_children);
  BIND_OR_THROW(api, lib, galley_walker_destroy);
  BIND_OR_THROW(api, lib, galley_node_symbol_name);
  BIND_OR_THROW(api, lib, galley_node_text);
  BIND_OR_THROW(api, lib, galley_node_span);
  BIND_OR_THROW(api, lib, galley_node_line_column);
  BIND_OR_THROW(api, lib, galley_node_variable_index);
  BIND_OR_THROW(api, lib, galley_tree_snapshot);
  BIND_OR_THROW(api, lib, galley_has_diagnostic);
  BIND_OR_THROW(api, lib, galley_diagnostic_kind);
  BIND_OR_THROW(api, lib, galley_diagnostic_message);
  BIND_OR_THROW(api, lib, galley_diagnostic_message_ansi);
  BIND_OR_THROW(api, lib, galley_diagnostic_position);
  BIND_OR_THROW(api, lib, galley_diagnostic_unexpected_token);
  BIND_OR_THROW(api, lib, galley_diagnostic_expected_count);
  BIND_OR_THROW(api, lib, galley_diagnostic_expected_at);
  BIND_OR_THROW(api, lib, galley_diagnostic_context_count);
  BIND_OR_THROW(api, lib, galley_diagnostic_context_at);
  BIND_OR_THROW(api, lib, galley_diagnostic_indentation);
  BIND_OR_THROW(api, lib, galley_syntax_error_count);
  BIND_OR_THROW(api, lib, galley_semantic_error_count);
  BIND_OR_THROW(api, lib, galley_diagnostic_semantic);
  BIND_OR_THROW(api, lib, galley_diagnostic_recovery_kind);
  BIND_OR_THROW(api, lib, galley_diagnostic_recovery_terminal);
  BIND_OR_THROW(api, lib, galley_diagnostic_recovery_resume);
  BIND_OR_THROW(api, lib, galley_diagnostic_recovery_lhs_variable);
  BIND_OR_THROW(api, lib, galley_diagnostic_recovery_production);
  BIND_OR_THROW(api, lib, galley_diagnostic_recovery_occurrence);
  BIND_OR_THROW(api, lib, galley_recorded_diagnostic_count);
  BIND_OR_THROW(api, lib, galley_recorded_diagnostic_kind);
  BIND_OR_THROW(api, lib, galley_recorded_diagnostic_position);
  BIND_OR_THROW(api, lib, galley_recorded_unexpected_token);
  BIND_OR_THROW(api, lib, galley_recorded_diagnostic_message);
  BIND_OR_THROW(api, lib, galley_recorded_indentation);
  BIND_OR_THROW(api, lib, galley_recorded_semantic);
  BIND_OR_THROW(api, lib, galley_recorded_expected_count);
  BIND_OR_THROW(api, lib, galley_recorded_expected_token);
  BIND_OR_THROW(api, lib, galley_recorded_context_count);
  BIND_OR_THROW(api, lib, galley_recorded_context_name);
  BIND_OR_THROW(api, lib, galley_recorded_diagnostic_recovery_kind);
  BIND_OR_THROW(api, lib, galley_recorded_recovery_terminal);
  BIND_OR_THROW(api, lib, galley_recorded_recovery_resume);
  BIND_OR_THROW(api, lib, galley_recorded_recovery_lhs_variable);
  BIND_OR_THROW(api, lib, galley_recorded_recovery_production);
  BIND_OR_THROW(api, lib, galley_recorded_recovery_occurrence);
  BIND_OR_THROW(api, lib, galley_tree_append_children);
  BIND_OR_THROW(api, lib, galley_tree_insert_before);
  BIND_OR_THROW(api, lib, galley_tree_insert_after);
  BIND_OR_THROW(api, lib, galley_tree_remove_siblings);
  BIND_OR_THROW(api, lib, galley_tree_remove_self);
  BIND_OR_THROW(api, lib, galley_tree_promote_children_over_wrapper);
  BIND_OR_THROW(api, lib, galley_tree_clean_children);
  BIND_OR_THROW(api, lib, galley_tree_unlink_wrapper);
  BIND_OR_THROW(api, lib, galley_tree_insert_children_at);
  BIND_OR_THROW(api, lib, galley_tree_remove_children_at);
  BIND_OR_THROW(api, lib, galley_procedure_session);
  BIND_OR_THROW(api, lib, galley_procedure_current_node);
  BIND_OR_THROW(api, lib, galley_procedure_set_current_node);
  BIND_OR_THROW(api, lib, galley_procedure_drop_self);
  BIND_OR_THROW(api, lib, galley_procedure_drop_children);
  BIND_OR_THROW(api, lib, galley_procedure_drop_if_empty);
  BIND_OR_THROW(api, lib, galley_procedure_replace_with_children);
  BIND_OR_THROW(api, lib, galley_procedure_context_line);
  BIND_OR_THROW(api, lib, galley_procedure_context_column);
  BIND_OR_THROW(api, lib, galley_procedure_report_semantic_error);
  // Reserve_nodes has no X-macro shape (session plus capacity).
  {
    if (!bind(env, api, lib, "galley_reserve_nodes", method_galley_reserve_nodes, NULL)) return NULL;
  }
  if (lib->install_id != NULL) {
    if (!bind(env, api, lib, "install_id_dispatch", method_install_id_dispatch, "galley_install_js_dispatch_id")) return NULL;
  } else if (!bind_null(env, api, "install_id_dispatch")) {
    return NULL;
  }
  if (lib->install_name != NULL) {
    if (!bind(env, api, lib, "install_name_dispatch", method_install_name_dispatch, "galley_install_js_dispatch")) return NULL;
  } else if (!bind_null(env, api, "install_name_dispatch")) {
    return NULL;
  }
  if (lib->procedure_count != NULL) {
    if (!bind(env, api, lib, "galley_js_procedure_count", method_galley_js_procedure_count, "galley_js_procedure_count"))
      return NULL;
  } else if (!bind_null(env, api, "galley_js_procedure_count")) {
    return NULL;
  }
  if (lib->procedure_name_ptr != NULL && lib->procedure_name_len != NULL) {
    if (!bind(env, api, lib, "galley_js_procedure_name", method_galley_js_procedure_name, "galley_js_procedure_name_ptr"))
      return NULL;
  } else if (!bind_null(env, api, "galley_js_procedure_name")) {
    return NULL;
  }
  if (lib->procedure_enable != NULL) {
    if (!bind(env, api, lib, "galley_js_procedure_enable", method_galley_js_procedure_enable, "galley_js_procedure_enable"))
      return NULL;
  } else if (!bind_null(env, api, "galley_js_procedure_enable")) {
    return NULL;
  }
  if (lib->procedure_clear != NULL) {
    if (!bind(env, api, lib, "galley_js_procedure_clear", method_galley_js_procedure_clear, "galley_js_procedure_clear"))
      return NULL;
  } else if (!bind_null(env, api, "galley_js_procedure_clear")) {
    return NULL;
  }
  for (int i = 0; i < lib->bound_count; i++) {
    if (probe_symbol(probe, lib->bound_names[i]) == NULL) {
      char message[256];
      snprintf(message, sizeof(message), "parser library is missing required symbol %s",
               lib->bound_names[i]);
      napi_throw_error(env, NULL, message);
      return NULL;
    }
  }
  return api;
}

static napi_value init(napi_env env, napi_value exports) {
  napi_value load_fn;
  if (napi_create_function(env, "load", NAPI_AUTO_LENGTH, method_load, NULL, &load_fn) != napi_ok)
    return NULL;
  if (napi_set_named_property(env, exports, "load", load_fn) != napi_ok) return NULL;
  return exports;
}

NAPI_MODULE(galley_addon, init)
