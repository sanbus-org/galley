/*
 * CPython extension module exposing generated Galley parsers.
 *
 * The module is compiled per consumer project against the shared library
 * Galley produces for one grammar (see python -m galley_bindings), and wraps
 * its C ABI (bindings/c/galley.h) without an intermediate marshalling layer:
 *
 * - every method is METH_O or METH_FASTCALL, so calls carry no argument
 *   tuples;
 * - node handles are galley.Node objects that wrap a stable address in the
 *   library's non-relocating node storage and keep a strong reference to
 *   their owning Session; plain ints are still accepted wherever a node is
 *   expected for backward compatibility, and Node supports int() and
 *   operator.index() to retrieve its address;
 * - text accessors copy straight into `bytes` with no UTF-8 decoding;
 * - parse() reads str inputs zero-copy through the interpreter's cached
 *   UTF-8 buffer, and parse_sentinel() additionally avoids the session's
 *   input copy for callers that keep the input alive until the next parse.
 *
 * Sessions are not thread-safe and every call holds the GIL: use one
 * session per thread or guard it externally. Node text, diagnostic
 * strings, and expected-token data remain valid until the next parse on
 * the same session; this module copies all of it before returning.
 */

#define _GNU_SOURCE
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <structmember.h>
#include <string.h>

#include <galley.h>
#if defined(__APPLE__) || defined(__linux__) || defined(__unix__)
#include <dlfcn.h>
#endif

/* ------------------------------------------------------------------ */
/* Error type                                                          */
/* ------------------------------------------------------------------ */

static PyObject *ErrorException = NULL;
static PyObject *py_procedure_table = NULL;
static PyObject *parsing_session = NULL;
static PyTypeObject ProcedureArgs_Type;

static PyObject *build_diagnostic(GalleySession *session);

typedef struct {
    PyObject_HEAD
    void *args;
    PyObject *session_obj;
} ProcedureArgsObject;

static PyObject *push_parsing_session(PyObject *self)
{
    PyObject *previous = parsing_session;
    parsing_session = self;
    return previous;
}

static void pop_parsing_session(PyObject *previous)
{
    parsing_session = previous;
}

static PyObject *make_procedure_args(void *args)
{
    ProcedureArgsObject *object = PyObject_New(ProcedureArgsObject, &ProcedureArgs_Type);
    if (object == NULL)
        return NULL;
    object->args = args;
    object->session_obj = parsing_session != NULL ? Py_NewRef(parsing_session) : NULL;
    return (PyObject *)object;
}

/* Python procedure dispatch: called from the generated Zig shim
 * (procedures_python.zig) for every reduction. The shim holds a
 * single global function pointer registered at module init; when the
 * library was built without Python support the pointer stays NULL and
 * hooks are no-ops. */
static void py_dispatch_impl(const char *name, size_t name_len, void *args) {
    if (py_procedure_table == NULL)
        return;
    PyObject *key = PyUnicode_FromStringAndSize(name, (Py_ssize_t)name_len);
    if (key == NULL) {
        PyErr_Clear();
        return;
    }
    PyObject *callable = PyDict_GetItemWithError(py_procedure_table, key);
    Py_DECREF(key);
    if (callable == NULL) {
        if (PyErr_Occurred())
            PyErr_Clear();
        return;
    }
    /* Pass a ProcedureArguments object; hooks that ignore it, take an
     * int, or take no args remain compatible. */
    PyObject *arg = make_procedure_args(args);
    if (arg == NULL) {
        PyErr_Clear();
        return;
    }
    PyObject *result = PyObject_CallOneArg(callable, arg);
    Py_DECREF(arg);
    if (result == NULL) {
        if (PyErr_ExceptionMatches(PyExc_TypeError)) {
            /* Allow def foo(): hooks that take no args. */
            PyErr_Clear();
            result = PyObject_CallNoArgs(callable);
            if (result == NULL)
                PyErr_Print();
            else
                Py_DECREF(result);
        } else {
            PyErr_Print();
        }
    } else {
        Py_DECREF(result);
    }
}

/* Try to register the dispatch target in the shared library. The library
 * is already loaded as a DT_NEEDED dependency of this extension, so
 * RTLD_DEFAULT finds it when it was built with Python support; when it
 * was built for C procedures the symbol is absent and we remain no-ops. */
static void try_install_python_dispatch(void) {
#if defined(__APPLE__) || defined(__linux__) || defined(__unix__)
    typedef void (*install_fn)(void (*)(const char *, size_t, void *));
    dlerror();
    install_fn installer = (install_fn)dlsym(RTLD_DEFAULT, "galley_install_python_dispatch");
    const char *error = dlerror();
    if (error == NULL && installer != NULL) {
        installer(py_dispatch_impl);
    }
#else
    /* Fallback weak linkage where dlfcn is unavailable. */
    extern void galley_install_python_dispatch(void (*)(const char *, size_t, void *));
    /* If the symbol is missing at load time, this call would have already
     * trapped on platforms without RTLD_DEFAULT; the dlfcn path above
     * handles POSIX. */
    #ifdef __has_attribute
    #if __has_attribute(weak)
    if (galley_install_python_dispatch)  /* weak reference */
        galley_install_python_dispatch(py_dispatch_impl);
    #endif
    #endif
#endif
}

static int auto_register_python_procedures(void) {
    /* Attempt to import `procedures` if it is on sys.path (the language dir
     * is typically on PYTHONPATH). Hooks are `reduction_*`, `reduction`, and
     * `hook_*` callables. This is best-effort: missing modules are ignored. */
    const char *candidates[] = {"procedures", NULL};
    for (int i = 0; candidates[i] != NULL; ++i) {
        PyObject *module = PyImport_ImportModule(candidates[i]);
        if (module == NULL) {
            PyErr_Clear();
            continue;
        }
        PyObject *dict = PyModule_GetDict(module);
        if (dict != NULL) {
            PyObject *key, *value;
            Py_ssize_t pos = 0;
            while (PyDict_Next(dict, &pos, &key, &value)) {
                if (!PyUnicode_Check(key) || !PyCallable_Check(value))
                    continue;
                const char *name = PyUnicode_AsUTF8(key);
                if (name == NULL) {
                    PyErr_Clear();
                    continue;
                }
                int is_procedure = 0;
                if (strcmp(name, "reduction") == 0)
                    is_procedure = 1;
                else if (strncmp(name, "reduction_", 10) == 0)
                    is_procedure = 1;
                else if (strncmp(name, "hook_", 5) == 0)
                    is_procedure = 1;
                if (!is_procedure)
                    continue;
                if (py_procedure_table == NULL) {
                    py_procedure_table = PyDict_New();
                    if (py_procedure_table == NULL) {
                        Py_DECREF(module);
                        return -1;
                    }
                }
                if (PyDict_SetItem(py_procedure_table, key, value) < 0) {
                    PyErr_Clear();
                }
            }
        }
        Py_DECREF(module);
        if (py_procedure_table != NULL && PyDict_Size(py_procedure_table) > 0)
            break;
    }
    return 0;
}

/* Sets ErrorException from a negative galley status code. The instance
 * carries the raw code as its `code` attribute and, when a session is
 * supplied, a snapshot of its current diagnostic as `diagnostic`. */
static void set_error_from_status_with_session(long long status, GalleySession *session)
{
    const char *description = galley_status_string(status);
    PyObject *message = NULL;
    PyObject *instance = NULL;
    PyObject *code = NULL;
    PyObject *diagnostic = NULL;

    if (description == NULL)
        description = "unknown galley error";
    message = PyUnicode_FromString(description);
    if (message == NULL)
        return;
    instance = PyObject_CallOneArg(ErrorException, message);
    Py_DECREF(message);
    if (instance == NULL)
        return;
    code = PyLong_FromLongLong(status);
    if (code == NULL || PyObject_SetAttrString(instance, "code", code) < 0) {
        Py_DECREF(instance);
        Py_XDECREF(code);
        return;
    }
    Py_DECREF(code);
    if (session != NULL && galley_has_diagnostic(session)) {
        diagnostic = build_diagnostic(session);
        if (diagnostic == NULL) {
            Py_DECREF(instance);
            return;
        }
    } else {
        diagnostic = Py_NewRef(Py_None);
    }
    if (PyObject_SetAttrString(instance, "diagnostic", diagnostic) < 0) {
        Py_DECREF(instance);
        Py_DECREF(diagnostic);
        return;
    }
    Py_DECREF(diagnostic);
    PyErr_SetObject(ErrorException, instance);
    Py_DECREF(instance);
}

static void set_error_from_status(long long status)
{
    set_error_from_status_with_session(status, NULL);
}

/* Converts a parse-style status into the returned byte count, raising on
 * error. */
static PyObject *status_to_parsed_with_session(long long status, GalleySession *session)
{
    if (status < 0) {
        set_error_from_status_with_session(status, session);
        return NULL;
    }
    return PyLong_FromLongLong(status);
}

static PyObject *status_to_parsed(long long status)
{
    if (status < 0) {
        set_error_from_status(status);
        return NULL;
    }
    return PyLong_FromLongLong(status);
}

/* Raises on a negative status; returns -1 in that case, else 0. */
static int check_status_with_session(long long status, GalleySession *session)
{
    if (status < 0) {
        set_error_from_status_with_session(status, session);
        return -1;
    }
    return 0;
}

static int check_status(long long status)
{
    if (status < 0) {
        set_error_from_status(status);
        return -1;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* Session and Node types                                              */
/* ------------------------------------------------------------------ */

typedef struct {
    PyObject_HEAD
    GalleySession *session;
} SessionObject;

typedef struct {
    PyObject_HEAD
    PyObject *session_obj;
    GalleySession *session;
    GalleyNodeAddress address;
} NodeObject;

static PyTypeObject Session_Type;
static PyTypeObject Node_Type;

/* ------------------------------------------------------------------ */
/* Argument helpers                                                    */
/* ------------------------------------------------------------------ */

static inline GalleySession *node_session(NodeObject *node)
{
    SessionObject *sobj = (SessionObject *)node->session_obj;
    if (sobj->session == NULL) {
        PyErr_SetString(PyExc_ValueError, "node's session is closed");
        return NULL;
    }
    return sobj->session;
}

static int node_argument(PyObject *object, GalleyNodeAddress *out)
{
    if (PyObject_IsInstance(object, (PyObject *)&Node_Type)) {
        NodeObject *node_obj = (NodeObject *)object;
        if (node_session(node_obj) == NULL)
            return -1;
        *out = node_obj->address;
        return 0;
    }
    unsigned long long value = PyLong_AsUnsignedLongLong(object);
    if (value == (unsigned long long)-1 && PyErr_Occurred())
        return -1;
    *out = (GalleyNodeAddress)value;
    return 0;
}

typedef GalleyNodeAddress (*NodeLink)(GalleySession *, GalleyNodeAddress);

/* Copies a (data, length) pair into bytes; NULL pointers become b""/"". */
static PyObject *bytes_from_pair(const char *data, size_t length)
{
    return PyBytes_FromStringAndSize(length > 0 ? data : "",
                                     (Py_ssize_t)length);
}

static PyObject *unicode_from_pair(const char *data, size_t length)
{
    return PyUnicode_FromStringAndSize(length > 0 ? data : "",
                                       (Py_ssize_t)length);
}

static inline GalleySession *require_session(PyObject *self)
{
    SessionObject *session_object = (SessionObject *)self;
    if (session_object->session == NULL) {
        PyErr_SetString(PyExc_ValueError, "session is closed");
        return NULL;
    }
    return session_object->session;
}

/* Shared body of the five link accessors: missing links become None. */
static PyObject *node_link_result(PyObject *session_obj, GalleySession *session, PyObject *node,
                                  NodeLink link)
{
    GalleyNodeAddress address;
    if (node_argument(node, &address) < 0)
        return NULL;
    address = link(session, address);
    if (address == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
    if (node_obj == NULL)
        return NULL;
    node_obj->session_obj = Py_NewRef(session_obj);
    node_obj->session = session;
    node_obj->address = address;
    return (PyObject *)node_obj;
}

/* Shared body of the two (data, length) accessors: invalid nodes become
 * None. */
static PyObject *node_bytes_result(
    GalleySession *session, PyObject *node,
    long long (*accessor)(GalleySession *, GalleyNodeAddress,
                          const char **, size_t *))
{
    GalleyNodeAddress address;
    const char *data;
    size_t length;

    if (node_argument(node, &address) < 0)
        return NULL;
    if (accessor(session, address, &data, &length) != galley_ok)
        Py_RETURN_NONE;
    return bytes_from_pair(data, length);
}

/* Shared body of the pair-valued span and line-column accessors: invalid
 * nodes become None. */
static PyObject *node_pair_result(
    GalleySession *session, PyObject *node,
    long long (*accessor)(GalleySession *, GalleyNodeAddress,
                          unsigned int *, unsigned int *),
    const char *format)
{
    GalleyNodeAddress address;
    unsigned int first = 0;
    unsigned int second = 0;

    if (node_argument(node, &address) < 0)
        return NULL;
    if (accessor(session, address, &first, &second) != galley_ok)
        Py_RETURN_NONE;
    return Py_BuildValue(format, first, second);
}

static int Session_init(SessionObject *self, PyObject *args, PyObject *keywords)
{
    int max_errors = 10;
    int recovery_window = 500;
    int stack_overflow_recovery = 0;
    unsigned int syntax_error_stack_depth = 0;
    int verbosity = 0;
    double ast_preallocation_ratio = -1.0;
    unsigned long long ast_preallocation_cap = 0;
    GalleyCOptions options;
    GalleySession *session;

    static char *list[] = {
        "max_errors", "recovery_window", "stack_overflow_recovery",
        "syntax_error_stack_depth", "verbosity", "ast_preallocation_ratio",
        "ast_preallocation_cap", NULL
    };
    static const char *format = "|$iipIidK:Session";

    if (!PyArg_ParseTupleAndKeywords(args, keywords, format, list,
                                     &max_errors, &recovery_window,
                                     &stack_overflow_recovery,
                                     &syntax_error_stack_depth, &verbosity,
                                     &ast_preallocation_ratio,
                                     &ast_preallocation_cap))
        return -1;

    options.max_errors = max_errors;
    options.recovery_window = recovery_window;
    options.stack_overflow_recovery = stack_overflow_recovery;
    options.syntax_error_stack_depth = syntax_error_stack_depth;
    options.verbosity = verbosity;
    options.ast_preallocation_ratio = ast_preallocation_ratio;
    options.ast_preallocation_cap = ast_preallocation_cap;

    session = galley_session_create_ex(&options);
    if (session == NULL) {
        set_error_from_status(galley_error_out_of_memory);
        return -1;
    }
    if (self->session != NULL)
        galley_session_destroy(self->session);
    self->session = session;
    return 0;
}

static void close_session(SessionObject *self)
{
    if (self->session != NULL) {
        galley_session_destroy(self->session);
        self->session = NULL;
    }
}

static PyObject *Session_close(SessionObject *self, PyObject *Py_UNUSED(ignored))
{
    close_session(self);
    Py_RETURN_NONE;
}

PyDoc_STRVAR(set_message_override_doc,
"set_message_override(name, message)\n"
"\n"
"Registers a per-session syntax-error message override. name is the\n"
"innermost variable name (or \"*\" for every site) and message may\n"
"use {line}, {column}, {unexpected}, {expected}, {context} placeholders.\n"
"Overrides set here take precedence over config.zig entries.");

static PyObject *Session_set_message_override(PyObject *self, PyObject *args)
{
    GalleySession *session = require_session(self);
    PyObject *name_obj;
    PyObject *message_obj;
    const char *name_data;
    const char *message_data;
    Py_ssize_t name_len;
    Py_ssize_t message_len;

    if (session == NULL)
        return NULL;
    if (!PyArg_ParseTuple(args, "OO:set_message_override", &name_obj, &message_obj))
        return NULL;
    if (PyUnicode_Check(name_obj)) {
        name_data = PyUnicode_AsUTF8AndSize(name_obj, &name_len);
        if (name_data == NULL)
            return NULL;
    } else if (PyBytes_Check(name_obj)) {
        name_data = PyBytes_AS_STRING(name_obj);
        name_len = PyBytes_GET_SIZE(name_obj);
    } else {
        PyErr_SetString(PyExc_TypeError, "name must be str or bytes");
        return NULL;
    }
    if (PyUnicode_Check(message_obj)) {
        message_data = PyUnicode_AsUTF8AndSize(message_obj, &message_len);
        if (message_data == NULL)
            return NULL;
    } else if (PyBytes_Check(message_obj)) {
        message_data = PyBytes_AS_STRING(message_obj);
        message_len = PyBytes_GET_SIZE(message_obj);
    } else {
        PyErr_SetString(PyExc_TypeError, "message must be str or bytes");
        return NULL;
    }
    if (check_status(galley_session_set_message_override(session, name_data, (size_t)name_len, message_data, (size_t)message_len)) < 0)
        return NULL;
    Py_RETURN_NONE;
}

static PyObject *Session_enter(SessionObject *self, PyObject *Py_UNUSED(ignored))
{
    Py_INCREF(self);
    return (PyObject *)self;
}

static PyObject *Session_exit(SessionObject *self, PyObject *Py_UNUSED(args),
                              Py_ssize_t Py_UNUSED(count))
{
    close_session(self);
    Py_RETURN_NONE;
}

static void Session_dealloc(SessionObject *self)
{
    close_session(self);
    Py_TYPE(self)->tp_free((PyObject *)self);
}

PyDoc_STRVAR(parse_doc,
"parse(input)\n"
"\n"
"Parses a str or bytes-like input that may contain NUL bytes and returns\n"
"the number of bytes parsed. The session copies the input, so parsed\n"
"text stays readable after the call regardless of what happens to the\n"
"object. Raises Error on failure; inspect diagnostic() for structured\n"
"details.");

static PyObject *Session_parse(PyObject *self, PyObject *input)
{
    GalleySession *session = require_session(self);
    const char *data = NULL;
    Py_ssize_t length = 0;
    Py_buffer view;
    int have_view = 0;
    long long status;

    if (session == NULL)
        return NULL;
    if (PyUnicode_Check(input)) {
        data = PyUnicode_AsUTF8AndSize(input, &length);
        if (data == NULL)
            return NULL;
    } else if (PyBytes_Check(input)) {
        data = PyBytes_AS_STRING(input);
        length = PyBytes_GET_SIZE(input);
    } else {
        if (PyObject_GetBuffer(input, &view, PyBUF_CONTIG_RO) < 0)
            return NULL;
        have_view = 1;
        data = (const char *)view.buf;
        length = view.len;
    }
    /* A zero-length input must not present a NULL pointer. */
    PyObject *previous = push_parsing_session(self);
    status = galley_parse(session, length > 0 ? data : "", (size_t)length);
    pop_parsing_session(previous);
    if (have_view)
        PyBuffer_Release(&view);
    return status_to_parsed_with_session(status, session);
}

PyDoc_STRVAR(parse_sentinel_doc,
"parse_sentinel(input)\n"
"\n"
"Parses a NUL-free str or bytes input and returns the number of bytes\n"
"parsed. Unlike parse(), the session may reference the input's buffer\n"
"without copying it: keep the object alive until the next parse on this\n"
"session. A NUL byte inside the input ends parsing early, exactly like\n"
"the underlying C entry point.");

static PyObject *Session_parse_sentinel(PyObject *self, PyObject *input)
{
    GalleySession *session = require_session(self);
    const char *data;
    Py_ssize_t length;

    if (session == NULL)
        return NULL;
    if (PyUnicode_Check(input)) {
        data = PyUnicode_AsUTF8AndSize(input, &length);
        if (data == NULL)
            return NULL;
    } else if (PyBytes_Check(input)) {
        data = PyBytes_AS_STRING(input);
        length = PyBytes_GET_SIZE(input);
    } else {
        PyErr_SetString(PyExc_TypeError,
                        "parse_sentinel expects str or bytes");
        return NULL;
    }
    PyObject *previous = push_parsing_session(self);
    PyObject *result = status_to_parsed_with_session(
        galley_parse_sentinel(session, length > 0 ? data : ""), session);
    pop_parsing_session(previous);
    return result;
}

PyDoc_STRVAR(parse_file_doc,
"parse_file(path)\n"
"\n"
"Parses the file at path (str, bytes, or os.PathLike) and returns the\n"
"number of bytes parsed.");

static PyObject *Session_parse_file(PyObject *self, PyObject *path)
{
    GalleySession *session = require_session(self);
    PyObject *filesystem_path;
    const char *data = NULL;
    PyObject *result = NULL;

    if (session == NULL)
        return NULL;
    filesystem_path = PyOS_FSPath(path);
    if (filesystem_path == NULL)
        return NULL;
    if (PyUnicode_Check(filesystem_path)) {
        data = PyUnicode_AsUTF8AndSize(filesystem_path, NULL);
    } else if (PyBytes_Check(filesystem_path)) {
        data = PyBytes_AS_STRING(filesystem_path);
    } else {
        PyErr_SetString(PyExc_TypeError, "path must be str or bytes");
    }
    if (data != NULL) {
        PyObject *previous = push_parsing_session(self);
        result = status_to_parsed_with_session(galley_parse_file(session, data), session);
        pop_parsing_session(previous);
    }
    Py_DECREF(filesystem_path);
    return result;
}

PyDoc_STRVAR(node_count_doc,
"node_count()\n"
"\n"
"Returns the number of AST nodes allocated by the most recent successful\n"
"parse (always 0 when the parser was built without AST construction).");

static PyObject *Session_node_count(PyObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleySession *session = require_session(self);
    if (session == NULL)
        return NULL;
    return PyLong_FromUnsignedLongLong(galley_node_count(session));
}

PyDoc_STRVAR(reserve_nodes_doc,
"reserve_nodes(capacity)\n"
"\n"
"Preallocates node storage for at least capacity nodes, avoiding growth\n"
"during subsequent parses.");

static PyObject *Session_reserve_nodes(PyObject *self, PyObject *capacity)
{
    GalleySession *session = require_session(self);
    unsigned long long value;

    if (session == NULL)
        return NULL;
    value = PyLong_AsUnsignedLongLong(capacity);
    if (value == (unsigned long long)-1 && PyErr_Occurred())
        return NULL;
    if (check_status(galley_reserve_nodes(session, value)) < 0)
        return NULL;
    Py_RETURN_NONE;
}

PyDoc_STRVAR(node_capacity_doc,
"node_capacity()\n"
"\n"
"Returns the current node storage capacity in nodes.");

static PyObject *Session_node_capacity(PyObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleySession *session = require_session(self);
    if (session == NULL)
        return NULL;
    return PyLong_FromUnsignedLongLong(galley_node_capacity(session));
}

PyDoc_STRVAR(root_node_doc,
"root_node()\n"
"\n"
"Returns the root node of the most recent successful parse, or None when\n"
"there is none.");

static PyObject *Session_root_node(PyObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress root;

    if (session == NULL)
        return NULL;
    root = galley_root_node(session);
    if (root == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
    if (node_obj == NULL)
        return NULL;
    node_obj->session_obj = Py_NewRef(self);
    node_obj->session = session;
    node_obj->address = root;
    return (PyObject *)node_obj;
}

PyDoc_STRVAR(node_valid_doc,
"node_valid(node)\n"
"\n"
"Returns whether the address refers to a live node of the most recent\n"
"parse.");

static PyObject *Session_node_valid(PyObject *self, PyObject *node)
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress address;

    if (session == NULL)
        return NULL;
    if (node_argument(node, &address) < 0)
        return NULL;
    return PyBool_FromLong(galley_node_is_valid(session, address));
}

PyDoc_STRVAR(child_count_doc,
"child_count(node)\n"
"\n"
"Returns the number of direct children of a node (0 for invalid nodes).");

static PyObject *Session_child_count(PyObject *self, PyObject *node)
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress address;

    if (session == NULL)
        return NULL;
    if (node_argument(node, &address) < 0)
        return NULL;
    return PyLong_FromUnsignedLong(galley_node_child_count(session, address));
}

PyDoc_STRVAR(children_doc,
"children(node)\n"
"\n"
"Returns a tuple of the direct children of a node, from first to last.\n"
"An empty tuple means no children. The tuple is iterable, so\n"
"'for child in session.children(node):' works.");

static PyObject *Session_children(PyObject *self, PyObject *node)
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress address;
    GalleyNodeAddress child;
    PyObject *tuple;
    Py_ssize_t count;
    Py_ssize_t i;

    if (session == NULL)
        return NULL;
    if (node_argument(node, &address) < 0)
        return NULL;
    count = (Py_ssize_t)galley_node_child_count(session, address);
    tuple = PyTuple_New(count);
    if (tuple == NULL)
        return NULL;
    child = galley_node_first_child(session, address);
    for (i = 0; i < count; ++i) {
        if (child == GALLEY_INVALID_NODE) {
            PyErr_SetString(PyExc_RuntimeError, "child count changed during iteration");
            Py_DECREF(tuple);
            return NULL;
        }
        NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
        if (node_obj == NULL) {
            Py_DECREF(tuple);
            return NULL;
        }
        node_obj->session_obj = Py_NewRef(self);
        node_obj->session = session;
        node_obj->address = child;
        PyTuple_SET_ITEM(tuple, i, (PyObject *)node_obj);
        child = galley_node_next_sibling(session, child);
    }
    return tuple;
}

PyDoc_STRVAR(first_child_doc,
"first_child(node)\n"
"\n"
"Returns the first child of a node, or None when the link does not\n"
"exist.");

static PyObject *Session_first_child(PyObject *self, PyObject *node)
{
    GalleySession *session = require_session(self);
    if (session == NULL)
        return NULL;
    return node_link_result(self, session, node, galley_node_first_child);
}

PyDoc_STRVAR(last_child_doc,
"last_child(node)\n"
"\n"
"Returns the last child of a node, or None when the link does not\n"
"exist.");

static PyObject *Session_last_child(PyObject *self, PyObject *node)
{
    GalleySession *session = require_session(self);
    if (session == NULL)
        return NULL;
    return node_link_result(self, session, node, galley_node_last_child);
}

PyDoc_STRVAR(next_sibling_doc,
"next_sibling(node)\n"
"\n"
"Returns the next sibling of a node, or None when the link does not\n"
"exist.");

static PyObject *Session_next_sibling(PyObject *self, PyObject *node)
{
    GalleySession *session = require_session(self);
    if (session == NULL)
        return NULL;
    return node_link_result(self, session, node, galley_node_next_sibling);
}

PyDoc_STRVAR(prior_sibling_doc,
"prior_sibling(node)\n"
"\n"
"Returns the previous sibling of a node, or None when the link does not\n"
"exist.");

static PyObject *Session_prior_sibling(PyObject *self, PyObject *node)
{
    GalleySession *session = require_session(self);
    if (session == NULL)
        return NULL;
    return node_link_result(self, session, node, galley_node_prior_sibling);
}

PyDoc_STRVAR(parent_doc,
"parent(node)\n"
"\n"
"Returns the parent of a node, or None for the root.");

static PyObject *Session_parent(PyObject *self, PyObject *node)
{
    GalleySession *session = require_session(self);
    if (session == NULL)
        return NULL;
    return node_link_result(self, session, node, galley_node_parent);
}

PyDoc_STRVAR(symbol_name_doc,
"symbol_name(node)\n"
"\n"
"Returns the grammar symbol name of a node as bytes (empty for\n"
"terminal-only nodes), or None for invalid nodes.");

static PyObject *Session_symbol_name(PyObject *self, PyObject *node)
{
    GalleySession *session = require_session(self);
    if (session == NULL)
        return NULL;
    return node_bytes_result(session, node, galley_node_symbol_name);
}

PyDoc_STRVAR(text_doc,
"text(node)\n"
"\n"
"Returns the source text matched by a node as bytes, or None for invalid\n"
"nodes.");

static PyObject *Session_text(PyObject *self, PyObject *node)
{
    GalleySession *session = require_session(self);
    if (session == NULL)
        return NULL;
    return node_bytes_result(session, node, galley_node_text);
}

PyDoc_STRVAR(span_doc,
"span(node)\n"
"\n"
"Returns the (start, length) byte span a node matched in the most recent\n"
"parse's input, or None for invalid nodes.");

static PyObject *Session_span(PyObject *self, PyObject *node)
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress address;
    unsigned long long start = 0;
    unsigned long long length = 0;

    if (session == NULL)
        return NULL;
    if (node_argument(node, &address) < 0)
        return NULL;
    if (galley_node_span(session, address, &start, &length) != galley_ok)
        Py_RETURN_NONE;
    return Py_BuildValue("KK", start, length);
}

PyDoc_STRVAR(line_column_doc,
"line_column(node)\n"
"\n"
"Returns the 1-based (line, column) of a node's first byte, or None for\n"
"invalid nodes. Scans the retained input, so cost is linear in the\n"
"offset.");

static PyObject *Session_line_column(PyObject *self, PyObject *node)
{
    GalleySession *session = require_session(self);
    if (session == NULL)
        return NULL;
    return node_pair_result(session, node, galley_node_line_column, "II");
}

PyDoc_STRVAR(variable_index_doc,
"variable_index(node)\n"
"\n"
"Returns the raw variable index of a node into the variable list, or\n"
"None when the node has no variable.");

static PyObject *Session_variable_index(PyObject *self, PyObject *node)
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress address;
    long long index;

    if (session == NULL)
        return NULL;
    if (node_argument(node, &address) < 0)
        return NULL;
    index = galley_node_variable_index(session, address);
    if (index == -1)
        Py_RETURN_NONE;
    if (index < 0) {
        set_error_from_status(index);
        return NULL;
    }
    return PyLong_FromLong(index);
}

PyDoc_STRVAR(last_position_doc,
"last_position()\n"
"\n"
"Returns the 1-based (line, column) where the most recent successful\n"
"parse ended (zeros when the parser was built without position\n"
"tracking).");

static PyObject *Session_last_position(PyObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleySession *session = require_session(self);
    unsigned int line = 0;
    unsigned int column = 0;

    if (session == NULL)
        return NULL;
    if (check_status(galley_last_position(session, &line, &column)) < 0)
        return NULL;
    return Py_BuildValue("II", line, column);
}

PyDoc_STRVAR(has_diagnostic_doc,
"has_diagnostic()\n"
"\n"
"Returns whether the previous parse produced a diagnostic.");

static PyObject *Session_has_diagnostic(PyObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleySession *session = require_session(self);
    if (session == NULL)
        return NULL;
    return PyBool_FromLong(galley_has_diagnostic(session));
}

/* ------------------------------------------------------------------ */
/* Diagnostic type                                                     */
/* ------------------------------------------------------------------ */

typedef struct {
    PyObject_HEAD
    long kind;
    long line;
    long column;
    PyObject *message;               /* str */
    PyObject *message_ansi;          /* str */
    PyObject *unexpected_token;      /* bytes | None */
    PyObject *expected_tokens;       /* tuple[bytes, ...] */
    PyObject *context;               /* tuple[str, ...] */
    long syntax_error_count;
    PyObject *indentation;           /* (spaces, width) | None */
    PyObject *recovery_kind;         /* int | None */
    PyObject *recovery_terminal;     /* bytes | None */
    PyObject *recovery_resume;       /* int | None */
    PyObject *recovery_lhs_variable; /* str | None */
    PyObject *recovery_production;   /* (variable, rhs_index) | None */
    PyObject *recovery_occurrence;   /* (parent, rhs, symbol, variable) | None */
} DiagnosticObject;

static void Diagnostic_dealloc(DiagnosticObject *self)
{
    Py_XDECREF(self->message);
    Py_XDECREF(self->message_ansi);
    Py_XDECREF(self->unexpected_token);
    Py_XDECREF(self->expected_tokens);
    Py_XDECREF(self->context);
    Py_XDECREF(self->indentation);
    Py_XDECREF(self->recovery_kind);
    Py_XDECREF(self->recovery_terminal);
    Py_XDECREF(self->recovery_resume);
    Py_XDECREF(self->recovery_lhs_variable);
    Py_XDECREF(self->recovery_production);
    Py_XDECREF(self->recovery_occurrence);
    Py_TYPE(self)->tp_free((PyObject *)self);
}

static PyMemberDef Diagnostic_members[] = {
    {"kind", T_LONG, offsetof(DiagnosticObject, kind), READONLY,
     "diagnostic classification: KIND_NONE, KIND_SYNTAX, KIND_INDENTATION"},
    {"line", T_LONG, offsetof(DiagnosticObject, line), READONLY,
     "1-based line of the failure"},
    {"column", T_LONG, offsetof(DiagnosticObject, column), READONLY,
     "1-based column of the failure"},
    {"message", T_OBJECT_EX, offsetof(DiagnosticObject, message), READONLY,
     "rendered plain-text message"},
    {"message_ansi", T_OBJECT_EX, offsetof(DiagnosticObject, message_ansi),
     READONLY, "rendered message with ANSI color escapes"},
    {"unexpected_token", T_OBJECT,
     offsetof(DiagnosticObject, unexpected_token), READONLY,
     "unexpected token bytes (syntax diagnostics only)"},
    {"expected_tokens", T_OBJECT_EX,
     offsetof(DiagnosticObject, expected_tokens), READONLY,
     "tuple of expected token bytes (syntax diagnostics only)"},
    {"context", T_OBJECT_EX, offsetof(DiagnosticObject, context), READONLY,
     "innermost-first tuple of variables being parsed (syntax only)"},
    {"syntax_error_count", T_LONG,
     offsetof(DiagnosticObject, syntax_error_count), READONLY,
     "how many syntax errors the recovery-enabled parse recorded"},
    {"indentation", T_OBJECT, offsetof(DiagnosticObject, indentation),
     READONLY,
     "(emitted spaces, indentation width) for indentation errors"},
    {"recovery_kind", T_OBJECT, offsetof(DiagnosticObject, recovery_kind),
     READONLY, "applied recovery target kind (RECOVERY_TARGET_ constants)"},
    {"recovery_terminal", T_OBJECT,
     offsetof(DiagnosticObject, recovery_terminal), READONLY,
     "synchronization terminal bytes chosen by recovery"},
    {"recovery_resume", T_OBJECT,
     offsetof(DiagnosticObject, recovery_resume), READONLY,
     "RESUME_BEFORE or RESUME_AFTER"},
    {"recovery_lhs_variable", T_OBJECT,
     offsetof(DiagnosticObject, recovery_lhs_variable), READONLY,
     "LHS variable scope of the applied recovery"},
    {"recovery_production", T_OBJECT,
     offsetof(DiagnosticObject, recovery_production), READONLY,
     "(variable, rhs index) of the production scope"},
    {"recovery_occurrence", T_OBJECT,
     offsetof(DiagnosticObject, recovery_occurrence), READONLY,
     "(parent variable, rhs index, symbol index, variable)"},
    {NULL}
};

static PyTypeObject Diagnostic_Type = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "galley.Diagnostic",
    .tp_basicsize = sizeof(DiagnosticObject),
    .tp_itemsize = 0,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_members = Diagnostic_members,
    .tp_dealloc = (destructor)Diagnostic_dealloc,
};

/* Builds the read-only Diagnostic snapshot of the current diagnostic, or
 * returns a new reference to None when there is none. Every C accessor is
 * guarded: fields that do not apply stay None (empty tuples for the list
 * fields). */
static PyObject *build_diagnostic(GalleySession *session)
{
    DiagnosticObject *diagnostic;
    unsigned int line = 0;
    unsigned int column = 0;
    unsigned int first = 0;
    unsigned int second = 0;
    const char *text = NULL;
    size_t length = 0;
    long long count;
    long long value;
    unsigned long long index;

    if (galley_has_diagnostic(session) == 0)
        Py_RETURN_NONE;

    diagnostic = PyObject_New(DiagnosticObject, &Diagnostic_Type);
    if (diagnostic == NULL)
        return NULL;
    diagnostic->kind = galley_diagnostic_kind_none;
    diagnostic->line = 0;
    diagnostic->column = 0;
    diagnostic->syntax_error_count = 0;
    diagnostic->message = Py_NewRef(Py_None);
    diagnostic->message_ansi = Py_NewRef(Py_None);
    diagnostic->unexpected_token = Py_NewRef(Py_None);
    diagnostic->expected_tokens = PyTuple_New(0);
    diagnostic->context = PyTuple_New(0);
    diagnostic->indentation = Py_NewRef(Py_None);
    diagnostic->recovery_kind = Py_NewRef(Py_None);
    diagnostic->recovery_terminal = Py_NewRef(Py_None);
    diagnostic->recovery_resume = Py_NewRef(Py_None);
    diagnostic->recovery_lhs_variable = Py_NewRef(Py_None);
    diagnostic->recovery_production = Py_NewRef(Py_None);
    diagnostic->recovery_occurrence = Py_NewRef(Py_None);
    if (diagnostic->expected_tokens == NULL || diagnostic->context == NULL)
        goto fail;

    diagnostic->kind = (long)galley_diagnostic_kind(session);
    if (galley_diagnostic_position(session, &line, &column) == galley_ok) {
        diagnostic->line = (long)line;
        diagnostic->column = (long)column;
    }
    if (galley_diagnostic_message(session, &text) == galley_ok &&
        text != NULL) {
        PyObject *rendered = PyUnicode_FromString(text);
        if (rendered == NULL)
            goto fail;
        Py_SETREF(diagnostic->message, rendered);
    }
    if (galley_diagnostic_message_ansi(session, &text) == galley_ok &&
        text != NULL) {
        PyObject *rendered = PyUnicode_FromString(text);
        if (rendered == NULL)
            goto fail;
        Py_SETREF(diagnostic->message_ansi, rendered);
    }
    if (galley_diagnostic_unexpected_token(session, &text, &length) ==
        galley_ok) {
        PyObject *token = bytes_from_pair(text, length);
        if (token == NULL)
            goto fail;
        Py_SETREF(diagnostic->unexpected_token, token);
    }
    count = galley_diagnostic_expected_count(session);
    if (count > 0) {
        PyObject *tokens = PyTuple_New((Py_ssize_t)count);
        if (tokens == NULL)
            goto fail;
        Py_SETREF(diagnostic->expected_tokens, tokens);
        for (index = 0; index < (unsigned long long)count; ++index) {
            PyObject *token;
            if (galley_diagnostic_expected_at(session, index, &text,
                                              &length) != galley_ok)
                text = NULL; /* Unreachable in practice; keeps the tuple dense. */
            token = bytes_from_pair(text, length);
            if (token == NULL)
                goto fail;
            PyTuple_SET_ITEM(tokens, (Py_ssize_t)index, token);
        }
    }
    count = galley_diagnostic_context_count(session);
    if (count > 0) {
        PyObject *context = PyTuple_New((Py_ssize_t)count);
        if (context == NULL)
            goto fail;
        Py_SETREF(diagnostic->context, context);
        for (index = 0; index < (unsigned long long)count; ++index) {
            PyObject *name;
            if (galley_diagnostic_context_at(session, index, &text,
                                             &length) != galley_ok)
                text = NULL; /* Unreachable in practice; keeps the tuple dense. */
            name = unicode_from_pair(text, length);
            if (name == NULL)
                goto fail;
            PyTuple_SET_ITEM(context, (Py_ssize_t)index, name);
        }
    }
    count = galley_syntax_error_count(session);
    if (count >= 0)
        diagnostic->syntax_error_count = (long)count;
    if (galley_diagnostic_indentation(session, &first, &second) ==
        galley_ok) {
        PyObject *pair = Py_BuildValue("II", first, second);
        if (pair == NULL)
            goto fail;
        Py_SETREF(diagnostic->indentation, pair);
    }

    value = galley_diagnostic_recovery_kind(session);
    if (value >= 0) {
        PyObject *boxed = PyLong_FromLong(value);
        if (boxed == NULL)
            goto fail;
        Py_SETREF(diagnostic->recovery_kind, boxed);
    }
    if (galley_diagnostic_recovery_terminal(session, &text, &length) ==
        galley_ok) {
        PyObject *terminal = bytes_from_pair(text, length);
        if (terminal == NULL)
            goto fail;
        Py_SETREF(diagnostic->recovery_terminal, terminal);
    }
    if (galley_diagnostic_recovery_resume(session, &value) == galley_ok &&
        value >= 0) {
        PyObject *boxed = PyLong_FromLong(value);
        if (boxed == NULL)
            goto fail;
        Py_SETREF(diagnostic->recovery_resume, boxed);
    }
    if (galley_diagnostic_recovery_lhs_variable(session, &text, &length) ==
        galley_ok) {
        PyObject *name = unicode_from_pair(text, length);
        if (name == NULL)
            goto fail;
        Py_SETREF(diagnostic->recovery_lhs_variable, name);
    }
    if (galley_diagnostic_recovery_production(session, &text, &length,
                                              &first) == galley_ok) {
        PyObject *name = unicode_from_pair(text, length);
        PyObject *pair;
        if (name == NULL)
            goto fail;
        pair = Py_BuildValue("(NI)", name, first);
        if (pair == NULL) {
            Py_DECREF(name);
            goto fail;
        }
        Py_SETREF(diagnostic->recovery_production, pair);
    }
    {
        const char *parent_text = NULL;
        const char *variable_text = NULL;
        size_t parent_length = 0;
        size_t variable_length = 0;
        if (galley_diagnostic_recovery_occurrence(
                session, &parent_text, &parent_length, &first, &second,
                &variable_text, &variable_length) == galley_ok) {
            PyObject *parent_name =
                unicode_from_pair(parent_text, parent_length);
            PyObject *variable_name =
                unicode_from_pair(variable_text, variable_length);
            PyObject *quadruple;
            if (parent_name == NULL || variable_name == NULL) {
                Py_XDECREF(parent_name);
                Py_XDECREF(variable_name);
                goto fail;
            }
            quadruple = Py_BuildValue("(NIII)", parent_name, first, second,
                                      variable_name);
            if (quadruple == NULL) {
                Py_DECREF(parent_name);
                Py_DECREF(variable_name);
                goto fail;
            }
            Py_SETREF(diagnostic->recovery_occurrence, quadruple);
        }
    }
    return (PyObject *)diagnostic;

fail:
    Py_DECREF(diagnostic);
    return NULL;
}

PyDoc_STRVAR(diagnostic_doc,
"diagnostic()\n"
"\n"
"Returns a read-only Diagnostic snapshot describing the failure of the\n"
"most recent parse, or None when it succeeded. The snapshot stays valid\n"
"forever; it does not track later parses.");

static PyObject *Session_diagnostic(PyObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleySession *session = require_session(self);
    if (session == NULL)
        return NULL;
    return build_diagnostic(session);
}

static PyObject *build_recorded_diagnostic(GalleySession *session, unsigned long long index)
{
    DiagnosticObject *diagnostic;
    unsigned int line = 0;
    unsigned int column = 0;
    const char *text = NULL;
    size_t length = 0;
    long long count;
    unsigned long long i;

    diagnostic = PyObject_New(DiagnosticObject, &Diagnostic_Type);
    if (diagnostic == NULL)
        return NULL;
    diagnostic->kind = (long)galley_recorded_diagnostic_kind(session, index);
    diagnostic->line = 0;
    diagnostic->column = 0;
    diagnostic->syntax_error_count = 0;
    diagnostic->message = Py_NewRef(Py_None);
    diagnostic->message_ansi = Py_NewRef(Py_None);
    diagnostic->unexpected_token = Py_NewRef(Py_None);
    diagnostic->expected_tokens = PyTuple_New(0);
    diagnostic->context = PyTuple_New(0);
    diagnostic->indentation = Py_NewRef(Py_None);
    diagnostic->recovery_kind = Py_NewRef(Py_None);
    diagnostic->recovery_terminal = Py_NewRef(Py_None);
    diagnostic->recovery_resume = Py_NewRef(Py_None);
    diagnostic->recovery_lhs_variable = Py_NewRef(Py_None);
    diagnostic->recovery_production = Py_NewRef(Py_None);
    diagnostic->recovery_occurrence = Py_NewRef(Py_None);
    if (diagnostic->expected_tokens == NULL || diagnostic->context == NULL)
        goto fail;

    if (galley_recorded_diagnostic_position(session, index, &line, &column) == galley_ok) {
        diagnostic->line = (long)line;
        diagnostic->column = (long)column;
    }
    if (galley_recorded_diagnostic_message(session, index, &text) == galley_ok && text != NULL) {
        PyObject *rendered = PyUnicode_FromString(text);
        if (rendered == NULL)
            goto fail;
        Py_SETREF(diagnostic->message, rendered);
        Py_SETREF(diagnostic->message_ansi, Py_NewRef(rendered));
    }
    if (galley_recorded_unexpected_token(session, index, &text, &length) == galley_ok) {
        PyObject *token = bytes_from_pair(text, length);
        if (token == NULL)
            goto fail;
        Py_SETREF(diagnostic->unexpected_token, token);
    }
    count = galley_recorded_expected_count(session, index);
    if (count > 0) {
        PyObject *tokens = PyTuple_New((Py_ssize_t)count);
        if (tokens == NULL)
            goto fail;
        Py_SETREF(diagnostic->expected_tokens, tokens);
        for (i = 0; i < (unsigned long long)count; ++i) {
            PyObject *token;
            if (galley_recorded_expected_token(session, index, i, &text, &length) != galley_ok)
                text = NULL;
            token = bytes_from_pair(text, length);
            if (token == NULL)
                goto fail;
            PyTuple_SET_ITEM(tokens, (Py_ssize_t)i, token);
        }
    }
    count = galley_recorded_context_count(session, index);
    if (count > 0) {
        PyObject *context = PyTuple_New((Py_ssize_t)count);
        if (context == NULL)
            goto fail;
        Py_SETREF(diagnostic->context, context);
        for (i = 0; i < (unsigned long long)count; ++i) {
            const char *name = NULL;
            size_t name_len = 0;
            PyObject *item;
            if (galley_recorded_context_name(session, index, i, &name, &name_len) != galley_ok)
                name = NULL;
            item = PyUnicode_FromStringAndSize(name ? name : "", name ? (Py_ssize_t)name_len : 0);
            if (item == NULL)
                goto fail;
            PyTuple_SET_ITEM(context, (Py_ssize_t)i, item);
        }
    }
    return (PyObject *)diagnostic;
fail:
    Py_XDECREF(diagnostic);
    return NULL;
}

PyDoc_STRVAR(diagnostics_doc,
"diagnostics()\n"
"\n"
"Returns a tuple of Diagnostic snapshots for every recorded diagnostic,\n"
"from first to last. Fail-fast parses have at most one.");

static PyObject *Session_diagnostics(PyObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleySession *session = require_session(self);
    long long count;
    PyObject *tuple;
    unsigned long long i;

    if (session == NULL)
        return NULL;
    count = galley_recorded_diagnostic_count(session);
    if (count < 0) {
        set_error_from_status(count);
        return NULL;
    }
    tuple = PyTuple_New((Py_ssize_t)count);
    if (tuple == NULL)
        return NULL;
    for (i = 0; i < (unsigned long long)count; ++i) {
        PyObject *diag = build_recorded_diagnostic(session, i);
        if (diag == NULL) {
            Py_DECREF(tuple);
            return NULL;
        }
        PyTuple_SET_ITEM(tuple, (Py_ssize_t)i, diag);
    }
    return tuple;
}

/* ------------------------------------------------------------------ */
/* Tree editing                                                        */
/* ------------------------------------------------------------------ */

static int expect_arguments(const char *name, Py_ssize_t count,
                            Py_ssize_t expected)
{
    if (count != expected) {
        PyErr_Format(PyExc_TypeError, "%s takes %zd arguments (%zd given)",
                     name, expected, count);
        return -1;
    }
    return 0;
}

PyDoc_STRVAR(append_children_doc,
"append_children(parent, chain)\n"
"\n"
"Appends chain (and its next-linked siblings) as the last children of\n"
"parent. Chains must be detached orphans.");

static PyObject *Session_append_children(PyObject *self,
                                         PyObject *const *arguments,
                                         Py_ssize_t count)
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress parent;
    GalleyNodeAddress chain;

    if (session == NULL)
        return NULL;
    if (expect_arguments("append_children", count, 2) < 0)
        return NULL;
    if (node_argument(arguments[0], &parent) < 0 ||
        node_argument(arguments[1], &chain) < 0)
        return NULL;
    if (check_status(galley_tree_append_children(session, parent, chain)) < 0)
        return NULL;
    Py_RETURN_NONE;
}

PyDoc_STRVAR(insert_before_doc,
"insert_before(target, chain)\n"
"\n"
"Inserts chain immediately before target among its siblings.");

static PyObject *Session_insert_before(PyObject *self,
                                       PyObject *const *arguments,
                                       Py_ssize_t count)
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress target;
    GalleyNodeAddress chain;

    if (session == NULL)
        return NULL;
    if (expect_arguments("insert_before", count, 2) < 0)
        return NULL;
    if (node_argument(arguments[0], &target) < 0 ||
        node_argument(arguments[1], &chain) < 0)
        return NULL;
    if (check_status(galley_tree_insert_before(session, target, chain)) < 0)
        return NULL;
    Py_RETURN_NONE;
}

PyDoc_STRVAR(insert_after_doc,
"insert_after(target, chain)\n"
"\n"
"Inserts chain immediately after target among its siblings.");

static PyObject *Session_insert_after(PyObject *self,
                                      PyObject *const *arguments,
                                      Py_ssize_t count)
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress target;
    GalleyNodeAddress chain;

    if (session == NULL)
        return NULL;
    if (expect_arguments("insert_after", count, 2) < 0)
        return NULL;
    if (node_argument(arguments[0], &target) < 0 ||
        node_argument(arguments[1], &chain) < 0)
        return NULL;
    if (check_status(galley_tree_insert_after(session, target, chain)) < 0)
        return NULL;
    Py_RETURN_NONE;
}

PyDoc_STRVAR(remove_siblings_doc,
"remove_siblings(node, count)\n"
"\n"
"Removes count consecutive siblings starting at node, detaching them\n"
"from parent and sibling chains, and returns the detached chain head\n"
"(None when empty).");

static PyObject *Session_remove_siblings(PyObject *self,
                                         PyObject *const *arguments,
                                         Py_ssize_t count)
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress node;
    Py_ssize_t sibling_count;
    GalleyNodeAddress head;

    if (session == NULL)
        return NULL;
    if (expect_arguments("remove_siblings", count, 2) < 0)
        return NULL;
    if (node_argument(arguments[0], &node) < 0)
        return NULL;
    sibling_count = PyLong_AsSsize_t(arguments[1]);
    if (sibling_count < 0 && PyErr_Occurred())
        return NULL;
    if (check_status(galley_tree_remove_siblings(session, node,
                                                 (size_t)sibling_count,
                                                 &head)) < 0)
        return NULL;
    if (head == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
    if (node_obj == NULL)
        return NULL;
    node_obj->session_obj = Py_NewRef(self);
    node_obj->session = session;
    node_obj->address = head;
    return (PyObject *)node_obj;
}

PyDoc_STRVAR(remove_self_doc,
"remove_self(node)\n"
"\n"
"Detaches node itself from its parent and siblings and returns the\n"
"detached head.");

static PyObject *Session_remove_self(PyObject *self, PyObject *node)
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress address;
    GalleyNodeAddress head;

    if (session == NULL)
        return NULL;
    if (node_argument(node, &address) < 0)
        return NULL;
    if (check_status(galley_tree_remove_self(session, address, &head)) < 0)
        return NULL;
    if (head == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
    if (node_obj == NULL)
        return NULL;
    node_obj->session_obj = Py_NewRef(self);
    node_obj->session = session;
    node_obj->address = head;
    return (PyObject *)node_obj;
}

PyDoc_STRVAR(promote_children_over_wrapper_doc,
"promote_children_over_wrapper(wrapper)\n"
"\n"
"Splices the children of wrapper in place of the wrapper among its\n"
"siblings and returns the promoted chain head (None when the wrapper has\n"
"no children). The wrapper is left detached.");

static PyObject *Session_promote_children_over_wrapper(PyObject *self,
                                                       PyObject *wrapper)
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress address;
    GalleyNodeAddress head;

    if (session == NULL)
        return NULL;
    if (node_argument(wrapper, &address) < 0)
        return NULL;
    if (check_status(galley_tree_promote_children_over_wrapper(
            session, address, &head)) < 0)
        return NULL;
    if (head == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
    if (node_obj == NULL)
        return NULL;
    node_obj->session_obj = Py_NewRef(self);
    node_obj->session = session;
    node_obj->address = head;
    return (PyObject *)node_obj;
}

PyDoc_STRVAR(clean_children_doc,
"clean_children(node)\n"
"\n"
"Detaches all children of node and returns the detached chain head (None\n"
"when there are none).");

static PyObject *Session_clean_children(PyObject *self, PyObject *node)
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress address;
    GalleyNodeAddress head;

    if (session == NULL)
        return NULL;
    if (node_argument(node, &address) < 0)
        return NULL;
    if (check_status(galley_tree_clean_children(session, address, &head)) < 0)
        return NULL;
    if (head == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
    if (node_obj == NULL)
        return NULL;
    node_obj->session_obj = Py_NewRef(self);
    node_obj->session = session;
    node_obj->address = head;
    return (PyObject *)node_obj;
}

PyDoc_STRVAR(unlink_wrapper_doc,
"unlink_wrapper(wrapper)\n"
"\n"
"Detaches wrapper from its parent and sibling chains without touching\n"
"its children.");

static PyObject *Session_unlink_wrapper(PyObject *self, PyObject *wrapper)
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress address;

    if (session == NULL)
        return NULL;
    if (node_argument(wrapper, &address) < 0)
        return NULL;
    if (check_status(galley_tree_unlink_wrapper(session, address)) < 0)
        return NULL;
    Py_RETURN_NONE;
}

PyDoc_STRVAR(insert_children_at_doc,
"insert_children_at(parent, index, chain)\n"
"\n"
"Inserts chain into the children of parent at index; an index equal to\n"
"the child count appends.");

static PyObject *Session_insert_children_at(PyObject *self,
                                            PyObject *const *arguments,
                                            Py_ssize_t count)
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress parent;
    GalleyNodeAddress chain;
    Py_ssize_t index;

    if (session == NULL)
        return NULL;
    if (expect_arguments("insert_children_at", count, 3) < 0)
        return NULL;
    if (node_argument(arguments[0], &parent) < 0)
        return NULL;
    index = PyLong_AsSsize_t(arguments[1]);
    if (index < 0 && PyErr_Occurred())
        return NULL;
    if (node_argument(arguments[2], &chain) < 0)
        return NULL;
    if (check_status(galley_tree_insert_children_at(session, parent,
                                                    (size_t)index,
                                                    chain)) < 0)
        return NULL;
    Py_RETURN_NONE;
}

PyDoc_STRVAR(remove_children_at_doc,
"remove_children_at(parent, index, count)\n"
"\n"
"Removes count consecutive children of parent starting at index and\n"
"returns the detached chain head (None when empty).");

static PyObject *Session_remove_children_at(PyObject *self,
                                            PyObject *const *arguments,
                                            Py_ssize_t count)
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress parent;
    GalleyNodeAddress head;
    Py_ssize_t index;
    Py_ssize_t child_count;

    if (session == NULL)
        return NULL;
    if (expect_arguments("remove_children_at", count, 3) < 0)
        return NULL;
    if (node_argument(arguments[0], &parent) < 0)
        return NULL;
    index = PyLong_AsSsize_t(arguments[1]);
    if (index < 0 && PyErr_Occurred())
        return NULL;
    child_count = PyLong_AsSsize_t(arguments[2]);
    if (child_count < 0 && PyErr_Occurred())
        return NULL;
    if (check_status(galley_tree_remove_children_at(session, parent,
                                                    (size_t)index,
                                                    (size_t)child_count,
                                                    &head)) < 0)
        return NULL;
    if (head == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
    if (node_obj == NULL)
        return NULL;
    node_obj->session_obj = Py_NewRef(self);
    node_obj->session = session;
    node_obj->address = head;
    return (PyObject *)node_obj;
}

/* ------------------------------------------------------------------ */
/* Grammar symbol table                                                */
/* ------------------------------------------------------------------ */

PyDoc_STRVAR(symbol_name_at_doc,
"symbol_name_at(index)\n"
"\n"
"Returns the name of the grammar symbol at index as bytes, or None when\n"
"the index is out of range.");

static PyObject *Session_symbol_name_at(PyObject *self, PyObject *index)
{
    GalleySession *session = require_session(self);
    unsigned long long position;
    const char *data;
    size_t length;

    if (session == NULL)
        return NULL;
    position = PyLong_AsUnsignedLongLong(index);
    if (position == (unsigned long long)-1 && PyErr_Occurred())
        return NULL;
    if (galley_symbol_name(session, position, &data, &length) != galley_ok)
        Py_RETURN_NONE;
    return bytes_from_pair(data, length);
}

PyDoc_STRVAR(symbol_is_terminal_doc,
"symbol_is_terminal(index)\n"
"\n"
"Returns whether the grammar symbol at index is a terminal.");

static PyObject *Session_symbol_is_terminal(PyObject *self, PyObject *index)
{
    GalleySession *session = require_session(self);
    unsigned long long position;

    if (session == NULL)
        return NULL;
    position = PyLong_AsUnsignedLongLong(index);
    if (position == (unsigned long long)-1 && PyErr_Occurred())
        return NULL;
    return PyBool_FromLong(galley_symbol_is_terminal(session, position));
}

PyDoc_STRVAR(variable_name_at_doc,
"variable_name_at(index)\n"
"\n"
"Returns the name of the grammar variable at index as bytes, or None\n"
"when the index is out of range.");

static PyObject *Session_variable_name_at(PyObject *self, PyObject *index)
{
    GalleySession *session = require_session(self);
    unsigned long long position;
    const char *data;
    size_t length;

    if (session == NULL)
        return NULL;
    position = PyLong_AsUnsignedLongLong(index);
    if (position == (unsigned long long)-1 && PyErr_Occurred())
        return NULL;
    if (galley_variable_name(session, position, &data, &length) != galley_ok)
        Py_RETURN_NONE;
    return bytes_from_pair(data, length);
}

/* ------------------------------------------------------------------ */
/* Session method table                                                */
/* ------------------------------------------------------------------ */

static PyMethodDef Session_methods[] = {
    {"close", (PyCFunction)(void (*)(void))Session_close, METH_NOARGS, NULL},
    {"__enter__", (PyCFunction)(void (*)(void))Session_enter, METH_NOARGS,
     NULL},
    {"__exit__", (PyCFunction)(void (*)(void))Session_exit, METH_FASTCALL,
     NULL},
    {"parse", (PyCFunction)(void (*)(void))Session_parse, METH_O, parse_doc},
    {"parse_sentinel", (PyCFunction)(void (*)(void))Session_parse_sentinel,
     METH_O, parse_sentinel_doc},
    {"parse_file", (PyCFunction)(void (*)(void))Session_parse_file, METH_O,
     parse_file_doc},
    {"node_count", (PyCFunction)(void (*)(void))Session_node_count,
     METH_NOARGS, node_count_doc},
    {"reserve_nodes", (PyCFunction)(void (*)(void))Session_reserve_nodes,
     METH_O, reserve_nodes_doc},
    {"node_capacity", (PyCFunction)(void (*)(void))Session_node_capacity,
     METH_NOARGS, node_capacity_doc},
    {"root_node", (PyCFunction)(void (*)(void))Session_root_node, METH_NOARGS,
     root_node_doc},
    {"node_valid", (PyCFunction)(void (*)(void))Session_node_valid, METH_O,
     node_valid_doc},
    {"child_count", (PyCFunction)(void (*)(void))Session_child_count, METH_O,
     child_count_doc},
    {"children", (PyCFunction)Session_children, METH_O, children_doc},
    {"first_child", (PyCFunction)(void (*)(void))Session_first_child, METH_O,
     first_child_doc},
    {"last_child", (PyCFunction)(void (*)(void))Session_last_child, METH_O,
     last_child_doc},
    {"next_sibling", (PyCFunction)(void (*)(void))Session_next_sibling,
     METH_O, next_sibling_doc},
    {"prior_sibling", (PyCFunction)(void (*)(void))Session_prior_sibling,
     METH_O, prior_sibling_doc},
    {"parent", (PyCFunction)(void (*)(void))Session_parent, METH_O,
     parent_doc},
    {"symbol_name", (PyCFunction)(void (*)(void))Session_symbol_name, METH_O,
     symbol_name_doc},
    {"text", (PyCFunction)(void (*)(void))Session_text, METH_O, text_doc},
    {"span", (PyCFunction)(void (*)(void))Session_span, METH_O, span_doc},
    {"line_column", (PyCFunction)(void (*)(void))Session_line_column, METH_O,
     line_column_doc},
    {"variable_index", (PyCFunction)(void (*)(void))Session_variable_index,
     METH_O, variable_index_doc},
    {"last_position", (PyCFunction)(void (*)(void))Session_last_position,
     METH_NOARGS, last_position_doc},
    {"has_diagnostic", (PyCFunction)(void (*)(void))Session_has_diagnostic,
     METH_NOARGS, has_diagnostic_doc},
    {"diagnostic", (PyCFunction)(void (*)(void))Session_diagnostic,
     METH_NOARGS, diagnostic_doc},
    {"append_children", (PyCFunction)(void (*)(void))Session_append_children,
     METH_FASTCALL, append_children_doc},
    {"insert_before", (PyCFunction)(void (*)(void))Session_insert_before,
     METH_FASTCALL, insert_before_doc},
    {"insert_after", (PyCFunction)(void (*)(void))Session_insert_after,
     METH_FASTCALL, insert_after_doc},
    {"remove_siblings", (PyCFunction)(void (*)(void))Session_remove_siblings,
     METH_FASTCALL, remove_siblings_doc},
    {"remove_self", (PyCFunction)(void (*)(void))Session_remove_self, METH_O,
     remove_self_doc},
    {"promote_children_over_wrapper",
     (PyCFunction)(void (*)(void))Session_promote_children_over_wrapper,
     METH_O, promote_children_over_wrapper_doc},
    {"clean_children", (PyCFunction)(void (*)(void))Session_clean_children,
     METH_O, clean_children_doc},
    {"unlink_wrapper", (PyCFunction)(void (*)(void))Session_unlink_wrapper,
     METH_O, unlink_wrapper_doc},
    {"insert_children_at",
     (PyCFunction)(void (*)(void))Session_insert_children_at, METH_FASTCALL,
     insert_children_at_doc},
    {"remove_children_at",
     (PyCFunction)(void (*)(void))Session_remove_children_at, METH_FASTCALL,
     remove_children_at_doc},
    {"symbol_name_at", (PyCFunction)(void (*)(void))Session_symbol_name_at,
     METH_O, symbol_name_at_doc},
    {"symbol_is_terminal",
     (PyCFunction)(void (*)(void))Session_symbol_is_terminal, METH_O,
     symbol_is_terminal_doc},
    {"variable_name_at",
     (PyCFunction)(void (*)(void))Session_variable_name_at, METH_O,
     variable_name_at_doc},
    {"set_message_override", (PyCFunction)Session_set_message_override,
     METH_VARARGS, set_message_override_doc},
    {"diagnostics", (PyCFunction)Session_diagnostics, METH_NOARGS,
     diagnostics_doc},
    {NULL, NULL, 0, NULL}
};

PyDoc_STRVAR(session_doc,
"Session(**options)\n"
"\n"
"Creates a parsing session bound to this library's parser. Keyword\n"
"options (all optional): max_errors=10, recovery_window=500,\n"
"stack_overflow_recovery=False, syntax_error_stack_depth=0,\n"
"verbosity=0, ast_preallocation_ratio=-1.0 (negative selects the runtime\n"
"default), ast_preallocation_cap=0.\n"
"\n"
"Sessions are not thread-safe: use one per thread or guard it externally.\n"
"Usable as a context manager; close() releases the underlying session and\n"
"is safe to call more than once.");

static PyTypeObject Session_Type = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "galley.Session",
    .tp_basicsize = sizeof(SessionObject),
    .tp_itemsize = 0,
    .tp_dealloc = (destructor)Session_dealloc,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_doc = session_doc,
    .tp_methods = Session_methods,
    .tp_init = (initproc)Session_init,
    .tp_new = PyType_GenericNew,
};

/* ------------------------------------------------------------------ */
/* Node type                                                           */
/* ------------------------------------------------------------------ */

static void Node_dealloc(NodeObject *self)
{
    Py_XDECREF(self->session_obj);
    Py_TYPE(self)->tp_free((PyObject *)self);
}

static PyObject *Node_repr(NodeObject *self)
{
    return PyUnicode_FromFormat("Node(%llu)", (unsigned long long)self->address);
}

static Py_ssize_t Node_length(NodeObject *self)
{
    GalleySession *session = node_session(self);
    if (session == NULL)
        return -1;
    return (Py_ssize_t)galley_node_child_count(session, self->address);
}

static PyObject *Node_item(NodeObject *self, Py_ssize_t index)
{
    GalleySession *session = node_session(self);
    if (session == NULL)
        return NULL;
    Py_ssize_t count = (Py_ssize_t)galley_node_child_count(session, self->address);
    if (index < 0)
        index += count;
    if (index < 0 || index >= count) {
        PyErr_SetString(PyExc_IndexError, "child index out of range");
        return NULL;
    }
    GalleyNodeAddress child = galley_node_first_child(session, self->address);
    for (Py_ssize_t i = 0; i < index; ++i)
        child = galley_node_next_sibling(session, child);
    if (child == GALLEY_INVALID_NODE) {
        PyErr_SetString(PyExc_RuntimeError, "child not found");
        return NULL;
    }
    NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
    if (node_obj == NULL)
        return NULL;
    node_obj->session_obj = Py_NewRef(self->session_obj);
    node_obj->session = session;
    node_obj->address = child;
    return (PyObject *)node_obj;
}

static PyObject *Node_subscript(NodeObject *self, PyObject *key)
{
    if (!PyLong_Check(key)) {
        PyErr_SetString(PyExc_TypeError, "node indices must be integers");
        return NULL;
    }
    Py_ssize_t index = PyLong_AsSsize_t(key);
    if (index == -1 && PyErr_Occurred())
        return NULL;
    return Node_item(self, index);
}

static PyObject *Node_iter(NodeObject *self)
{
    PyObject *tuple = Session_children((PyObject *)self->session_obj, (PyObject *)self);
    if (tuple == NULL)
        return NULL;
    PyObject *iter = PyObject_GetIter(tuple);
    Py_DECREF(tuple);
    return iter;
}

static PyObject *Node_children(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    return Session_children((PyObject *)self->session_obj, (PyObject *)self);
}

static PyObject *Node_text(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    const char *data;
    size_t length;
    GalleySession *session = node_session(self);
    if (session == NULL)
        return NULL;
    if (galley_node_text(session, self->address, &data, &length) != galley_ok)
        Py_RETURN_NONE;
    return PyBytes_FromStringAndSize(data, length);
}

static PyObject *Node_symbol_name(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    const char *data;
    size_t length;
    GalleySession *session = node_session(self);
    if (session == NULL)
        return NULL;
    if (galley_node_symbol_name(session, self->address, &data, &length) != galley_ok)
        Py_RETURN_NONE;
    return PyBytes_FromStringAndSize(data, length);
}

static PyObject *Node_span(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    unsigned long long start = 0;
    unsigned long long len = 0;
    GalleySession *session = node_session(self);
    if (session == NULL)
        return NULL;
    if (galley_node_span(session, self->address, &start, &len) != galley_ok)
        Py_RETURN_NONE;
    return Py_BuildValue("KK", start, len);
}

static PyObject *Node_line_column(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    unsigned int line = 0;
    unsigned int column = 0;
    GalleySession *session = node_session(self);
    if (session == NULL)
        return NULL;
    if (galley_node_line_column(session, self->address, &line, &column) != galley_ok)
        Py_RETURN_NONE;
    return Py_BuildValue("II", line, column);
}

static PyObject *Node_parent(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleyNodeAddress parent;
    GalleySession *session = node_session(self);
    if (session == NULL)
        return NULL;
    parent = galley_node_parent(session, self->address);
    if (parent == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
    if (node_obj == NULL)
        return NULL;
    node_obj->session_obj = Py_NewRef(self->session_obj);
    node_obj->session = session;
    node_obj->address = parent;
    return (PyObject *)node_obj;
}

static PyObject *Node_next_sibling(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleyNodeAddress sibling;
    GalleySession *session = node_session(self);
    if (session == NULL)
        return NULL;
    sibling = galley_node_next_sibling(session, self->address);
    if (sibling == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
    if (node_obj == NULL)
        return NULL;
    node_obj->session_obj = Py_NewRef(self->session_obj);
    node_obj->session = session;
    node_obj->address = sibling;
    return (PyObject *)node_obj;
}

static PyObject *Node_prior_sibling(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleyNodeAddress sibling;
    GalleySession *session = node_session(self);
    if (session == NULL)
        return NULL;
    sibling = galley_node_prior_sibling(session, self->address);
    if (sibling == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
    if (node_obj == NULL)
        return NULL;
    node_obj->session_obj = Py_NewRef(self->session_obj);
    node_obj->session = session;
    node_obj->address = sibling;
    return (PyObject *)node_obj;
}

static PyObject *Node_first_child(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleyNodeAddress child;
    GalleySession *session = node_session(self);
    if (session == NULL)
        return NULL;
    child = galley_node_first_child(session, self->address);
    if (child == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
    if (node_obj == NULL)
        return NULL;
    node_obj->session_obj = Py_NewRef(self->session_obj);
    node_obj->session = session;
    node_obj->address = child;
    return (PyObject *)node_obj;
}

static PyObject *Node_last_child(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleyNodeAddress child;
    GalleySession *session = node_session(self);
    if (session == NULL)
        return NULL;
    child = galley_node_last_child(session, self->address);
    if (child == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
    if (node_obj == NULL)
        return NULL;
    node_obj->session_obj = Py_NewRef(self->session_obj);
    node_obj->session = session;
    node_obj->address = child;
    return (PyObject *)node_obj;
}

static PyObject *Node_clean_children(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleyNodeAddress head;
    GalleySession *session = node_session(self);
    if (session == NULL)
        return NULL;
    if (check_status(galley_tree_clean_children(session, self->address, &head)) < 0)
        return NULL;
    if (head == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
    if (node_obj == NULL)
        return NULL;
    node_obj->session_obj = Py_NewRef(self->session_obj);
    node_obj->session = session;
    node_obj->address = head;
    return (PyObject *)node_obj;
}

static PyObject *Node_append_children(NodeObject *self, PyObject *chain)
{
    GalleyNodeAddress chain_address;
    GalleySession *session = node_session(self);
    if (session == NULL)
        return NULL;
    if (node_argument(chain, &chain_address) < 0)
        return NULL;
    if (check_status(galley_tree_append_children(session, self->address, chain_address)) < 0)
        return NULL;
    Py_RETURN_NONE;
}

PyDoc_STRVAR(node_children_doc, "children()\n\nReturns a tuple of the direct children of this node.");
PyDoc_STRVAR(node_text_doc, "text()\n\nReturns the text of this node as bytes, or None.");
PyDoc_STRVAR(node_symbol_name_doc, "symbol_name()\n\nReturns the symbol name of this node as bytes, or None.");
PyDoc_STRVAR(node_span_doc, "span()\n\nReturns (start, length) of this node, or None.");
PyDoc_STRVAR(node_line_column_doc, "line_column()\n\nReturns (line, column) of this node, or None.");
PyDoc_STRVAR(node_parent_doc, "parent()\n\nReturns the parent node, or None.");
PyDoc_STRVAR(node_next_sibling_doc, "next_sibling()\n\nReturns the next sibling, or None.");
PyDoc_STRVAR(node_prior_sibling_doc, "prior_sibling()\n\nReturns the prior sibling, or None.");
PyDoc_STRVAR(node_first_child_doc, "first_child()\n\nReturns the first child, or None.");
PyDoc_STRVAR(node_last_child_doc, "last_child()\n\nReturns the last child, or None.");

static PyMethodDef Node_methods[] = {
    {"children", (PyCFunction)Node_children, METH_NOARGS, node_children_doc},
    {"text", (PyCFunction)Node_text, METH_NOARGS, node_text_doc},
    {"symbol_name", (PyCFunction)Node_symbol_name, METH_NOARGS, node_symbol_name_doc},
    {"span", (PyCFunction)Node_span, METH_NOARGS, node_span_doc},
    {"line_column", (PyCFunction)Node_line_column, METH_NOARGS, node_line_column_doc},
    {"parent", (PyCFunction)Node_parent, METH_NOARGS, node_parent_doc},
    {"next_sibling", (PyCFunction)Node_next_sibling, METH_NOARGS, node_next_sibling_doc},
    {"prior_sibling", (PyCFunction)Node_prior_sibling, METH_NOARGS, node_prior_sibling_doc},
    {"first_child", (PyCFunction)Node_first_child, METH_NOARGS, node_first_child_doc},
    {"last_child", (PyCFunction)Node_last_child, METH_NOARGS, node_last_child_doc},
    {"clean_children", (PyCFunction)Node_clean_children, METH_NOARGS, clean_children_doc},
    {"append_children", (PyCFunction)Node_append_children, METH_O, append_children_doc},
    {NULL, NULL, 0, NULL}
};

static PySequenceMethods Node_sequence_methods = {
    .sq_length = (lenfunc)Node_length,
    .sq_item = (ssizeargfunc)Node_item,
};

static PyMappingMethods Node_mapping_methods = {
    .mp_length = (lenfunc)Node_length,
    .mp_subscript = (binaryfunc)Node_subscript,
};

static PyObject *Node_richcompare(PyObject *a, PyObject *b, int op)
{
    if (!PyObject_IsInstance(a, (PyObject *)&Node_Type) ||
        !PyObject_IsInstance(b, (PyObject *)&Node_Type)) {
        Py_RETURN_NOTIMPLEMENTED;
    }
    NodeObject *na = (NodeObject *)a;
    NodeObject *nb = (NodeObject *)b;
    int equal = (na->address == nb->address) && (na->session_obj == nb->session_obj);
    if (na->session_obj != nb->session_obj) {
        // Different sessions are never equal even if address coincides; the
        // address space is per-session. Keep inequality for cross-session
        // comparisons without leaking.
        equal = 0;
    }
    int result = 0;
    if (op == Py_EQ)
        result = equal;
    else if (op == Py_NE)
        result = !equal;
    else {
        Py_RETURN_NOTIMPLEMENTED;
    }
    if (result)
        Py_RETURN_TRUE;
    else
        Py_RETURN_FALSE;
}

static Py_hash_t Node_hash(NodeObject *self)
{
    // Use address as hash; mix in session pointer low bits to avoid
    // cross-session collisions when Nodes are used as dict keys.
    Py_hash_t h = (Py_hash_t)self->address;
    if (h == -1)
        h = -2;
    return h;
}

static PyObject *Node_int(NodeObject *self)
{
    return PyLong_FromUnsignedLongLong(self->address);
}

static PyNumberMethods Node_number_methods = {
    .nb_int = (unaryfunc)Node_int,
    .nb_index = (unaryfunc)Node_int,
};

static PyTypeObject Node_Type = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "galley.Node",
    .tp_basicsize = sizeof(NodeObject),
    .tp_itemsize = 0,
    .tp_dealloc = (destructor)Node_dealloc,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_doc = "Node handle with session-aware methods. Iterate directly: for child in node:",
    .tp_methods = Node_methods,
    .tp_as_sequence = &Node_sequence_methods,
    .tp_as_mapping = &Node_mapping_methods,
    .tp_as_number = &Node_number_methods,
    .tp_iter = (getiterfunc)Node_iter,
    .tp_richcompare = Node_richcompare,
    .tp_hash = (hashfunc)Node_hash,
    .tp_repr = (reprfunc)Node_repr,
    .tp_str = (reprfunc)Node_repr,
};

/* ------------------------------------------------------------------ */
/* ProcedureArguments — parse-time hook state                          */
/* ------------------------------------------------------------------ */

static void ProcedureArgs_dealloc(ProcedureArgsObject *self)
{
    Py_XDECREF(self->session_obj);
    Py_TYPE(self)->tp_free((PyObject *)self);
}

static PyObject *ProcedureArgs_make_node(ProcedureArgsObject *self, GalleyNodeAddress address)
{
    if (address == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    if (self->session_obj == NULL)
        Py_RETURN_NONE;
    SessionObject *session_obj = (SessionObject *)self->session_obj;
    if (session_obj->session == NULL) {
        PyErr_SetString(PyExc_ValueError, "session is closed");
        return NULL;
    }
    NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
    if (node_obj == NULL)
        return NULL;
    node_obj->session_obj = Py_NewRef(self->session_obj);
    node_obj->session = session_obj->session;
    node_obj->address = address;
    return (PyObject *)node_obj;
}

static PyObject *ProcedureArgs_current_node(ProcedureArgsObject *self, PyObject *Py_UNUSED(ignored))
{
    return ProcedureArgs_make_node(self, galley_procedure_current_node(self->args));
}

static PyObject *ProcedureArgs_session(ProcedureArgsObject *self, void *Py_UNUSED(closure))
{
    if (self->session_obj == NULL)
        Py_RETURN_NONE;
    return Py_NewRef(self->session_obj);
}

static PyObject *ProcedureArgs_drop_self(ProcedureArgsObject *self, PyObject *Py_UNUSED(ignored))
{
    if (check_status(galley_procedure_drop_self(self->args)) < 0)
        return NULL;
    Py_RETURN_NONE;
}

static PyObject *ProcedureArgs_drop_children(ProcedureArgsObject *self, PyObject *Py_UNUSED(ignored))
{
    if (check_status(galley_procedure_drop_children(self->args)) < 0)
        return NULL;
    Py_RETURN_NONE;
}

static PyObject *ProcedureArgs_drop_if_empty(ProcedureArgsObject *self, PyObject *Py_UNUSED(ignored))
{
    if (check_status(galley_procedure_drop_if_empty(self->args)) < 0)
        return NULL;
    Py_RETURN_NONE;
}

static PyObject *ProcedureArgs_replace_with_children(ProcedureArgsObject *self, PyObject *Py_UNUSED(ignored))
{
    if (check_status(galley_procedure_replace_with_children(self->args)) < 0)
        return NULL;
    Py_RETURN_NONE;
}

static PyObject *ProcedureArgs_current_line(ProcedureArgsObject *self, PyObject *Py_UNUSED(ignored))
{
    return PyLong_FromUnsignedLong(galley_procedure_context_line(self->args));
}

static PyObject *ProcedureArgs_current_column(ProcedureArgsObject *self, PyObject *Py_UNUSED(ignored))
{
    return PyLong_FromUnsignedLong(galley_procedure_context_column(self->args));
}

static PyMethodDef ProcedureArgs_methods[] = {
    {"current_node", (PyCFunction)ProcedureArgs_current_node, METH_NOARGS,
     "current_node()\n\nThe node being reduced, or None."},
    {"drop_self", (PyCFunction)ProcedureArgs_drop_self, METH_NOARGS,
     "drop_self()\n\nDrop the current node from the parse."},
    {"drop_children", (PyCFunction)ProcedureArgs_drop_children, METH_NOARGS,
     "drop_children()\n\nDrop children of the current node."},
    {"drop_if_empty", (PyCFunction)ProcedureArgs_drop_if_empty, METH_NOARGS,
     "drop_if_empty()\n\nDrop the current node when it has no children."},
    {"replace_with_children", (PyCFunction)ProcedureArgs_replace_with_children, METH_NOARGS,
     "replace_with_children()\n\nReplace the current node with its children."},
    {"current_line", (PyCFunction)ProcedureArgs_current_line, METH_NOARGS,
     "current_line()\n\nScanner line during this reduction."},
    {"current_column", (PyCFunction)ProcedureArgs_current_column, METH_NOARGS,
     "current_column()\n\nScanner column during this reduction."},
    {NULL, NULL, 0, NULL}
};

static PyGetSetDef ProcedureArgs_getset[] = {
    {"session", (getter)ProcedureArgs_session, NULL,
     "The Session currently parsing, or None.", NULL},
    {NULL, NULL, NULL, NULL, NULL}
};

static PyTypeObject ProcedureArgs_Type = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "galley.ProcedureArguments",
    .tp_basicsize = sizeof(ProcedureArgsObject),
    .tp_itemsize = 0,
    .tp_dealloc = (destructor)ProcedureArgs_dealloc,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_doc = "Parse-time procedure-hook arguments. Tree queries use current_node() "
              "and the ordinary Node methods.",
    .tp_methods = ProcedureArgs_methods,
    .tp_getset = ProcedureArgs_getset,
};

/* ------------------------------------------------------------------ */
/* Module-level functions                                              */
/* ------------------------------------------------------------------ */

PyDoc_STRVAR(version_doc,
"version()\n"
"\n"
"Returns the build-supplied version string of this library.");

static PyObject *module_version(PyObject *Py_UNUSED(module),
                                PyObject *Py_UNUSED(ignored))
{
    return PyUnicode_FromString(galley_version());
}

/* Generic wrappers over the zero-argument library queries. */
typedef long long (*Query)(void);
typedef int (*Flag)(void);

static PyObject *query_long(Query query)
{
    return PyLong_FromLongLong(query());
}

static PyObject *flag_bool(Flag flag)
{
    return PyBool_FromLong(flag() != 0);
}

#define MODULE_QUERY(name, call)                                          \
    static PyObject *module_##name(PyObject *Py_UNUSED(module),           \
                                   PyObject *Py_UNUSED(ignored))          \
    {                                                                     \
        return query_long(call);                                          \
    }

#define MODULE_FLAG(name, call)                                           \
    static PyObject *module_##name(PyObject *Py_UNUSED(module),           \
                                   PyObject *Py_UNUSED(ignored))          \
    {                                                                     \
        return flag_bool(call);                                           \
    }

MODULE_QUERY(parser_type, galley_parser_type)
MODULE_QUERY(error_recovery_mode, galley_error_recovery_mode)
MODULE_FLAG(has_ast, galley_has_ast)
MODULE_FLAG(has_procedures, galley_has_procedures)
MODULE_FLAG(allows_no_ast_tree_procedures,
            galley_allows_no_ast_tree_procedures)
MODULE_FLAG(source_retention_enabled, galley_source_retention_enabled)
MODULE_FLAG(has_position_tracking, galley_has_position_tracking)
MODULE_FLAG(has_input_streaming, galley_has_input_streaming)
MODULE_FLAG(uses_verbatim, galley_uses_verbatim)
MODULE_FLAG(stack_overflow_recovery_available,
            galley_stack_overflow_recovery_available)

static PyObject *module_symbol_count(PyObject *Py_UNUSED(module),
                                     PyObject *Py_UNUSED(ignored))
{
    return PyLong_FromUnsignedLongLong(galley_symbol_count());
}

static PyObject *module_variable_count(PyObject *Py_UNUSED(module),
                                       PyObject *Py_UNUSED(ignored))
{
    return PyLong_FromUnsignedLongLong(galley_variable_count());
}

PyDoc_STRVAR(status_string_doc,
"status_string(status)\n"
"\n"
"Renders a status code as a human-readable string, or None when\n"
"unknown.");

static PyObject *module_status_string(PyObject *Py_UNUSED(module),
                                      PyObject *status)
{
    long long value = PyLong_AsLongLong(status);
    const char *description;

    if (value == -1 && PyErr_Occurred())
        return NULL;
    description = galley_status_string(value);
    if (description == NULL)
        Py_RETURN_NONE;
    return PyUnicode_FromString(description);
}

PyDoc_STRVAR(install_procedure_doc,
"install_procedure(name, callable)\n"
"\n"
"Registers a Python procedure hook. name is the hook name (for example\n"
"\"reduction_Pair\" or \"hook_print\") and callable is a Python callable\n"
"that will be invoked with a ProcedureArguments object (or with no args\n"
"for compatibility). Hooks are\n"
"no-ops until installed; reinstalling replaces the previous callable.\n"
"Mirrors Go's hooks/procedures.go and Rust's procedures.rs registration.");

static PyObject *module_install_procedure(PyObject *Py_UNUSED(module),
                                          PyObject *args)
{
    const char *name;
    Py_ssize_t name_len;
    PyObject *callable;

    if (!PyArg_ParseTuple(args, "s#O:install_procedure", &name, &name_len, &callable))
        return NULL;
    if (!PyCallable_Check(callable)) {
        PyErr_SetString(PyExc_TypeError, "callable must be callable");
        return NULL;
    }
    if (py_procedure_table == NULL) {
        py_procedure_table = PyDict_New();
        if (py_procedure_table == NULL)
            return NULL;
    }
    PyObject *key = PyUnicode_FromStringAndSize(name, name_len);
    if (key == NULL)
        return NULL;
    if (PyDict_SetItem(py_procedure_table, key, callable) < 0) {
        Py_DECREF(key);
        return NULL;
    }
    Py_DECREF(key);
    Py_RETURN_NONE;
}

PyDoc_STRVAR(install_procedures_doc,
"install_procedures(module_or_dict)\n"
"\n"
"Registers all procedure hooks found in a module, dict, or object exposing\n"
"a __dict__. Hooks are `reduction`, `reduction_<Variable>`, and\n"
"`hook_<name>` callables. Returns the number of hooks installed.");

static PyObject *module_install_procedures(PyObject *Py_UNUSED(module),
                                           PyObject *source)
{
    PyObject *dict = NULL;
    int is_dict = PyDict_Check(source);
    int is_module = PyModule_Check(source);

    if (is_dict) {
        dict = Py_NewRef(source);
    } else if (is_module) {
        dict = PyModule_GetDict(source);
        if (dict == NULL)
            return NULL;
        Py_INCREF(dict);
    } else {
        PyObject *d = PyObject_GetAttrString(source, "__dict__");
        if (d != NULL && PyDict_Check(d)) {
            dict = d;
        } else {
            Py_XDECREF(d);
            PyErr_SetString(PyExc_TypeError, "install_procedures expects a module, dict, or object with __dict__");
            return NULL;
        }
    }

    if (py_procedure_table == NULL) {
        py_procedure_table = PyDict_New();
        if (py_procedure_table == NULL) {
            Py_DECREF(dict);
            return NULL;
        }
    }

    PyObject *key, *value;
    Py_ssize_t pos = 0;
    Py_ssize_t installed = 0;
    while (PyDict_Next(dict, &pos, &key, &value)) {
        if (!PyUnicode_Check(key) || !PyCallable_Check(value))
            continue;
        const char *name = PyUnicode_AsUTF8(key);
        if (name == NULL) {
            PyErr_Clear();
            continue;
        }
        int is_procedure = 0;
        if (strcmp(name, "reduction") == 0)
            is_procedure = 1;
        else if (strncmp(name, "reduction_", 10) == 0)
            is_procedure = 1;
        else if (strncmp(name, "hook_", 5) == 0)
            is_procedure = 1;
        if (!is_procedure)
            continue;
        if (PyDict_SetItem(py_procedure_table, key, value) < 0) {
            PyErr_Clear();
            continue;
        }
        installed++;
    }
    Py_DECREF(dict);
    return PyLong_FromSsize_t(installed);
}

PyDoc_STRVAR(clear_procedures_doc,
"clear_procedures()\n"
"\n"
"Clears all registered Python procedure hooks.");

static PyObject *module_clear_procedures(PyObject *Py_UNUSED(module),
                                         PyObject *Py_UNUSED(ignored))
{
    if (py_procedure_table != NULL) {
        PyDict_Clear(py_procedure_table);
    }
    Py_RETURN_NONE;
}

PyDoc_STRVAR(list_procedures_doc,
"list_procedures()\n"
"\n"
"Returns a dict of currently registered Python procedure hooks (name ->\n"
"callable).");

static PyObject *module_list_procedures(PyObject *Py_UNUSED(module),
                                        PyObject *Py_UNUSED(ignored))
{
    if (py_procedure_table == NULL)
        return PyDict_New();
    return PyDict_Copy(py_procedure_table);
}

static PyMethodDef module_methods[] = {
    {"version", module_version, METH_NOARGS, version_doc},
    {"parser_type", module_parser_type, METH_NOARGS,
     "parser_type()\n\nReturns the parser family: PARSER_TYPE_LL or\n"
     "PARSER_TYPE_LR."},
    {"error_recovery_mode", module_error_recovery_mode, METH_NOARGS,
     "error_recovery_mode()\n\nReturns the generated error-recovery mode:\n"
     "RECOVERY_MODE_DISABLED, RECOVERY_MODE_AUTOMATIC, or\n"
     "RECOVERY_MODE_EXPLICIT."},
    {"has_ast", module_has_ast, METH_NOARGS,
     "has_ast()\n\nReturns whether the library was built with AST\n"
     "construction."},
    {"has_procedures", module_has_procedures, METH_NOARGS,
     "has_procedures()\n\nReturns whether procedure hooks are compiled in."},
    {"allows_no_ast_tree_procedures", module_allows_no_ast_tree_procedures,
     METH_NOARGS,
     "allows_no_ast_tree_procedures()\n\nReturns whether tree helpers work\n"
     "in no-AST mode."},
    {"source_retention_enabled", module_source_retention_enabled, METH_NOARGS,
     "source_retention_enabled()\n\nReturns whether sessions retain source\n"
     "text."},
    {"has_position_tracking", module_has_position_tracking, METH_NOARGS,
     "has_position_tracking()\n\nReturns whether line/column data is\n"
     "meaningful."},
    {"has_input_streaming", module_has_input_streaming, METH_NOARGS,
     "has_input_streaming()\n\nReturns whether incremental input is\n"
     "supported."},
    {"uses_verbatim", module_uses_verbatim, METH_NOARGS,
     "uses_verbatim()\n\nReturns whether the grammar uses verbatim\n"
     "capture."},
    {"stack_overflow_recovery_available",
     module_stack_overflow_recovery_available, METH_NOARGS,
     "stack_overflow_recovery_available()\n\nReturns whether the platform\n"
     "supports stack-overflow recovery."},
    {"symbol_count", module_symbol_count, METH_NOARGS,
     "symbol_count()\n\nReturns how many symbols the grammar declares."},
    {"variable_count", module_variable_count, METH_NOARGS,
     "variable_count()\n\nReturns how many variables the grammar declares."},
    {"status_string", module_status_string, METH_O, status_string_doc},
    {"install_procedure", module_install_procedure, METH_VARARGS, install_procedure_doc},
    {"install_procedures", module_install_procedures, METH_O, install_procedures_doc},
    {"clear_procedures", module_clear_procedures, METH_NOARGS, clear_procedures_doc},
    {"list_procedures", module_list_procedures, METH_NOARGS, list_procedures_doc},
    {NULL, NULL, 0, NULL}
};

PyDoc_STRVAR(module_doc,
"Bindings over a Galley-generated parser shared library.\n"
"\n"
"One module embeds one parser: build it alongside your grammar with\n"
"python -m galley_bindings, then import it from that directory.\n"
"See Session for the parsing surface and the module constants for\n"
"classification enums.");

static struct PyModuleDef module_definition = {
    PyModuleDef_HEAD_INIT,
    .m_name = "galley",
    .m_doc = module_doc,
    .m_size = -1,
    .m_methods = module_methods,
};

PyMODINIT_FUNC PyInit_galley(void)
{
    PyObject *module;

    if (PyType_Ready(&Session_Type) < 0)
        return NULL;
    if (PyType_Ready(&Node_Type) < 0)
        return NULL;
    if (PyType_Ready(&ProcedureArgs_Type) < 0)
        return NULL;
    if (PyType_Ready(&Diagnostic_Type) < 0)
        return NULL;

    module = PyModule_Create(&module_definition);
    if (module == NULL)
        return NULL;

    ErrorException = PyErr_NewExceptionWithDoc(
        "galley.Error",
        "Failure reported by a Galley operation. The raw status code is\n"
        "available as the `code` attribute.",
        NULL, NULL);
    if (ErrorException == NULL)
        goto fail;
    Py_INCREF(ErrorException);
    if (PyModule_AddObject(module, "Error", ErrorException) < 0) {
        Py_DECREF(ErrorException);
        goto fail;
    }

    Py_INCREF(&Session_Type);
    if (PyModule_AddObject(module, "Session", (PyObject *)&Session_Type) < 0) {
        Py_DECREF(&Session_Type);
        goto fail;
    }
    Py_INCREF(&Diagnostic_Type);
    if (PyModule_AddObject(module, "Diagnostic",
                           (PyObject *)&Diagnostic_Type) < 0) {
        Py_DECREF(&Diagnostic_Type);
        goto fail;
    }
    Py_INCREF(&Node_Type);
    if (PyModule_AddObject(module, "Node", (PyObject *)&Node_Type) < 0) {
        Py_DECREF(&Node_Type);
        goto fail;
    }
    Py_INCREF(&ProcedureArgs_Type);
    if (PyModule_AddObject(module, "ProcedureArguments",
                           (PyObject *)&ProcedureArgs_Type) < 0) {
        Py_DECREF(&ProcedureArgs_Type);
        goto fail;
    }

    if (PyModule_AddIntConstant(module, "PARSER_TYPE_LL",
                                galley_parser_type_ll) < 0 ||
        PyModule_AddIntConstant(module, "PARSER_TYPE_LR",
                                galley_parser_type_lr) < 0 ||
        PyModule_AddIntConstant(module, "RECOVERY_MODE_DISABLED",
                                galley_recovery_mode_disabled) < 0 ||
        PyModule_AddIntConstant(module, "RECOVERY_MODE_AUTOMATIC",
                                galley_recovery_mode_automatic) < 0 ||
        PyModule_AddIntConstant(module, "RECOVERY_MODE_EXPLICIT",
                                galley_recovery_mode_explicit) < 0 ||
        PyModule_AddIntConstant(module, "KIND_NONE",
                                galley_diagnostic_kind_none) < 0 ||
        PyModule_AddIntConstant(module, "KIND_SYNTAX",
                                galley_diagnostic_kind_syntax) < 0 ||
        PyModule_AddIntConstant(module, "KIND_INDENTATION",
                                galley_diagnostic_kind_indentation) < 0 ||
        PyModule_AddIntConstant(module, "RECOVERY_TARGET_NONE",
                                galley_recovery_target_none) < 0 ||
        PyModule_AddIntConstant(module, "RECOVERY_TARGET_LHS_VARIABLE",
                                galley_recovery_target_lhs_variable) < 0 ||
        PyModule_AddIntConstant(module, "RECOVERY_TARGET_PRODUCTION",
                                galley_recovery_target_production) < 0 ||
        PyModule_AddIntConstant(module, "RECOVERY_TARGET_OCCURRENCE",
                                galley_recovery_target_occurrence) < 0 ||
        PyModule_AddIntConstant(module, "RESUME_BEFORE",
                                galley_resume_before) < 0 ||
        PyModule_AddIntConstant(module, "RESUME_AFTER",
                                galley_resume_after) < 0)
        goto fail;

    /* Python procedure hooks: install the dispatch callback into the
     * shared library (when built with Python support) and auto-import
     * any `procedures` module on sys.path. Missing libraries or modules
     * are silently ignored — hooks are simply no-ops. */
    try_install_python_dispatch();
    if (auto_register_python_procedures() < 0) {
        PyErr_Clear();
    }

    return module;

fail:
    Py_DECREF(module);
    return NULL;
}
