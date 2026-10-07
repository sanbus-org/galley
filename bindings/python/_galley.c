/*
 * CPython extension module exposing generated Galley parsers.
 *
 * The module is compiled per consumer project against the shared library
 * Galley produces for one grammar (see python -m galley), and wraps
 * its C ABI (bindings/c/galley.h) without an intermediate marshalling layer:
 *
 * - every method is METH_O or METH_FASTCALL, so calls carry no argument
 *   tuples;
 * - node handles are galley.Node objects that wrap a stable address in the
 *   library's non-relocating node storage, keep a strong reference to
 *   their owning Session, and carry the core's parse generation they
 *   belong to. Which door a call crosses is chosen when the call is made:
 *   from inside a hook of the session's running parse, on the thread
 *   running that hook, a node reads through the parse's hook door;
 *   everywhere else it reads through the session door, and every such call
 *   hands the node's generation to the core, which refuses one that is not
 *   the published tree's. The host therefore keeps no cached copy of that
 *   generation and cannot disagree with the core about it. A node is the
 *   only thing accepted where a node is expected: raw addresses carry no
 *   generation, so they are refused, and snapshot().node(index) is the
 *   one sanctioned conversion from a stored address back to a node;
 * - every refusal raises, StaleTreeError for a tree that is gone; only
 *   Session.root_node() answers None for "nothing here";
 * - text accessors copy straight into `bytes` with no UTF-8 decoding;
 * - parse() passes pointer+length into galley_parse;
 *   str inputs use the interpreter's cached UTF-8 buffer.
 *
 * Sessions are not thread-safe: use one session per thread or guard it
 * externally. Parses release the GIL, so sessions on different threads
 * parse in parallel; a hook re-acquires it for the length of its call.
 * Each session owns its procedure hooks (a copy of the module's defaults
 * taken when it opens), so concurrent sessions share nothing. Node text,
 * diagnostic strings, and expected-token data remain valid until the next
 * parse on the same session; this module copies all of it before returning.
 */

#define _GNU_SOURCE
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <structmember.h>
#include <string.h>

#include <galley.h>

/* Baked module name: the inner extension is always built with
 * -DGALLEY_MODULE_NAME=galley_impl and imported relatively by the
 * generated package init, so the language directory keeps its own name.
 * The name sets the module object, GalleyError's qualified name, and the
 * PyInit entry importlib resolves. */
#ifndef GALLEY_MODULE_NAME
#define GALLEY_MODULE_NAME galley_impl
#endif
#define GALLEY_STRING_OF_IMPL(name) #name
#define GALLEY_STRING_OF(name) GALLEY_STRING_OF_IMPL(name)
#define GALLEY_MODULE_STRING GALLEY_STRING_OF(GALLEY_MODULE_NAME)
#define GALLEY_CONCAT_IMPL(left, right) left##right
#define GALLEY_CONCAT(left, right) GALLEY_CONCAT_IMPL(left, right)
#define GALLEY_INIT_FUNCTION GALLEY_CONCAT(PyInit_, GALLEY_MODULE_NAME)

/* ------------------------------------------------------------------ */
/* GalleyError type                                                    */
/* ------------------------------------------------------------------ */

static PyObject *ErrorException = NULL;
/* The one stale-tree error: raised wherever a node, walk, or tree read
 * addresses a generation the core does not hold live. A subclass of
 * GalleyError, so `except galley.GalleyError` still catches it. */
static PyObject *StaleTreeException = NULL;
/* The module's default hooks (name -> callable): each Session opened later
 * starts with a copy and owns it. */
static PyObject *py_procedure_table = NULL;
/* Hook name (str) -> hook index, from the library's own hook list, and the
 * number of hooks it forwards. Filled once at module init. */
static PyObject *hook_indexes = NULL;
static size_t hook_count = 0;
static PyTypeObject ProcedureArgs_Type;

static PyObject *build_diagnostic(GalleySession *session);

/* Defined after Diagnostic_Type; new reference to the snapshot's rendered
 * message, or NULL when it is not a unicode string. */
static PyObject *diagnostic_rendered_message(PyObject *diagnostic);

typedef struct {
    PyObject_HEAD
    /* The ticket the core issued for this hook call. It is all the object
     * knows about its hook: the core refuses every call made with the ticket
     * of a hook that has returned (galley_error_stale_hook), so the object
     * keeps no expiry flag of its own. Whatever must outlive the hook — the
     * tree — is addressed through the session. */
    unsigned long long hook;
    /* The session whose parse this hook belongs to. */
    PyObject *session_obj;
} ProcedureArgsObject;

typedef struct {
    PyObject_HEAD
    GalleySession *session;
    /* The running parse's hook door and generation, read from the core on
     * the parse's first dispatch (both are constant for the parse) and
     * dropped by the parse's finish gate; NULL between parses. */
    GalleyHookDoor *parse_door;
    unsigned long long parse_generation;
    /* Whether a hook is running now, and the thread running it: set per
     * dispatch. A call made on dispatch_thread while dispatching crosses
     * parse_door; a call from any other thread crosses the session door,
     * which the core refuses while the parse runs. */
    int dispatching;
    unsigned long dispatch_thread;
    /* This session's hooks by name (str -> callable): replaced whole by every
     * change, never mutated. NULL until Session.__init__ ran. */
    PyObject *hooks;
    /* The same callables by the library's hook index: a list with None for
     * every unhooked index. The dispatch lookup. */
    PyObject *hooks_by_index;
} SessionObject;

static PyObject *make_procedure_args(unsigned long long hook, PyObject *session_obj)
{
    ProcedureArgsObject *object = PyObject_New(ProcedureArgsObject, &ProcedureArgs_Type);
    if (object == NULL)
        return NULL;
    object->hook = hook;
    object->session_obj = Py_NewRef(session_obj);
    return (PyObject *)object;
}

/* Decides the hook call shape before invoking: a plain Python function
 * (or bound method) declaring no positional parameters gets no
 * arguments; anything else -- including variadic and defaulted
 * declarations -- gets the ProcedureArguments object. Deciding up front
 * means a TypeError raised inside a hook body is reported as-is instead
 * of being cleared and retried as a supposed arity mismatch (which also
 * ran the hook a second time). Non-function callables (builtins,
 * partials, callable objects) report -1 and keep the legacy probe
 * below. */
static int hook_takes_no_arguments(PyObject *callable)
{
    PyObject *func = callable;
    PyObject *code = NULL;
    PyObject *count_obj = NULL;
    PyObject *flags_obj = NULL;
    long positional;
    long flags;
    int bound_self = 0;

    if (PyMethod_Check(func)) {
        func = PyMethod_GET_FUNCTION(func);
        bound_self = 1;
    }
    if (!PyFunction_Check(func))
        return -1;
    code = PyObject_GetAttrString(func, "__code__");
    if (code == NULL) {
        PyErr_Clear();
        return -1;
    }
    count_obj = PyObject_GetAttrString(code, "co_argcount");
    flags_obj = PyObject_GetAttrString(code, "co_flags");
    Py_DECREF(code);
    if (count_obj == NULL || flags_obj == NULL) {
        Py_XDECREF(count_obj);
        Py_XDECREF(flags_obj);
        PyErr_Clear();
        return -1;
    }
    positional = PyLong_AsLong(count_obj);
    flags = PyLong_AsLong(flags_obj);
    Py_DECREF(count_obj);
    Py_DECREF(flags_obj);
    if ((positional == -1 || flags == -1) && PyErr_Occurred()) {
        PyErr_Clear();
        return -1;
    }
    if (positional - bound_self <= 0 && !(flags & CO_VARARGS))
        return 1;
    return 0;
}

/* Runs hook `index` of `session`'s running parse, with the GIL held. The
 * hook table is the session's own, fixed for the whole parse, so nothing
 * here depends on any other session. */
static void run_hook(SessionObject *session, unsigned int index, unsigned long long hook)
{
    if (session->hooks_by_index == NULL ||
        index >= (unsigned int)PyList_GET_SIZE(session->hooks_by_index))
        return;
    PyObject *callable = PyList_GET_ITEM(session->hooks_by_index, index);
    if (callable == Py_None)
        return;
    Py_INCREF(callable);
    /* The call shape is decided before invoking: no-arg hooks are
     * called empty, so a TypeError from a hook body is never mistaken
     * for an arity mismatch. Unknown shapes keep the legacy probe. */
    int no_arguments = hook_takes_no_arguments(callable);
    if (no_arguments > 0) {
        PyObject *result = PyObject_CallNoArgs(callable);
        if (result == NULL)
            PyErr_Print();
        else
            Py_DECREF(result);
        Py_DECREF(callable);
        return;
    }
    PyObject *arg = make_procedure_args(hook, (PyObject *)session);
    if (arg == NULL) {
        PyErr_Clear();
        Py_DECREF(callable);
        return;
    }
    PyObject *result = PyObject_CallOneArg(callable, arg);
    Py_DECREF(arg);
    if (result == NULL) {
        if (no_arguments == 0) {
            /* Arity was decided up front: a genuine hook-body failure. */
            PyErr_Print();
        } else if (PyErr_ExceptionMatches(PyExc_TypeError)) {
            /* Unknown shape (builtin, partial, callable object): allow
             * hooks that take no args. */
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
    Py_DECREF(callable);
}

/* The dispatch callback of every session (the handle is its SessionObject,
 * alive because the parse runs inside one of its own method calls). A parse
 * releases the GIL, so the hook takes it back for the length of its call.
 * The parse's hook door and generation are read on its first dispatch and
 * kept until the parse's finish gate; each dispatch only records that a
 * hook is running and on which thread, which is what lets a call choose its
 * door when it is made. */
static void py_dispatch_impl(void *handle, unsigned int index, unsigned long long hook)
{
    SessionObject *session = (SessionObject *)handle;
    PyGILState_STATE gil = PyGILState_Ensure();
    if (session->parse_door == NULL) {
        GalleyHookDoor *door = NULL;
        unsigned long long generation = 0;
        if (galley_procedure_door(session->session, hook, &door) == galley_ok &&
            galley_hook_generation(door, &generation) == galley_ok) {
            session->parse_generation = generation;
            session->parse_door = door;
        }
    }
    if (session->parse_door != NULL) {
        session->dispatch_thread = PyThread_get_thread_ident();
        session->dispatching = 1;
    }
    run_hook(session, index, hook);
    session->dispatching = 0;
    PyGILState_Release(gil);
}

/* Sets ErrorException from a negative galley status code. The instance
 * carries the raw code as its `code` attribute and, when a session is
 * supplied, a snapshot of its current diagnostic as `diagnostic`. The
 * exception text is the rendered diagnostic message when there is one,
 * falling back to the status string. */
static void set_error_from_status_with_session(long long status, GalleySession *session)
{
    const char *description = galley_status_string(status);
    PyObject *message = NULL;
    PyObject *instance = NULL;
    PyObject *code = NULL;
    PyObject *diagnostic = NULL;

    if (session != NULL && galley_has_diagnostic(session)) {
        diagnostic = build_diagnostic(session);
        if (diagnostic == NULL)
            return;
        message = diagnostic_rendered_message(diagnostic);
    }
    if (message == NULL) {
        if (description == NULL)
            description = "unknown galley error";
        message = PyUnicode_FromString(description);
        if (message == NULL) {
            Py_XDECREF(diagnostic);
            return;
        }
    }
    /* One stale-tree error for every source: a stale status from the core,
     * a stale walk step, and the host-side refusals below. The class is
     * StaleTreeError (a GalleyError subclass) exactly when the code says so. */
    PyObject *exception =
        (status == galley_error_stale_tree && StaleTreeException != NULL)
            ? StaleTreeException
            : ErrorException;
    instance = PyObject_CallOneArg(exception, message);
    Py_DECREF(message);
    if (instance == NULL) {
        Py_XDECREF(diagnostic);
        return;
    }
    code = PyLong_FromLongLong(status);
    if (code == NULL || PyObject_SetAttrString(instance, "code", code) < 0) {
        Py_DECREF(instance);
        Py_XDECREF(code);
        Py_XDECREF(diagnostic);
        return;
    }
    Py_DECREF(code);
    if (diagnostic == NULL)
        diagnostic = Py_NewRef(Py_None);
    if (PyObject_SetAttrString(instance, "diagnostic", diagnostic) < 0) {
        Py_DECREF(instance);
        Py_DECREF(diagnostic);
        return;
    }
    Py_DECREF(diagnostic);
    PyErr_SetObject(exception, instance);
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

/* Raises on a negative status; returns -1 in that case, else 0. */
static int check_status(long long status)
{
    if (status < 0) {
        set_error_from_status(status);
        return -1;
    }
    return 0;
}

/* A value-returning session-door call answers with its value, always
 * non-negative, or a negative status: raises on a status and returns -1,
 * else returns the value. */
static long long check_value(long long value)
{
    return check_status(value) < 0 ? -1 : value;
}

/* ------------------------------------------------------------------ */
/* Session and Node types                                              */
/* ------------------------------------------------------------------ */

typedef struct {
    PyObject_HEAD
    PyObject *session_obj;
    GalleyNodeAddress address;
    /* The core's parse generation this node belongs to, stamped from the
     * crossing that produced it. Identity is session, generation and
     * address; the door a node was reached through is not part of it. */
    unsigned long long generation;
} NodeObject;

typedef struct WalkerObject {
    PyObject_HEAD
    PyObject *session_obj;
    /* The whole walk: host-owned cursor, no native resource, one native
     * call per step (galley_walk_next or its hook twin). */
    GalleyWalkCursor cursor;
} WalkerObject;

/* One yielded walk position. Immutable, and made only by the walker: the
 * type has no constructor, like Node and Snapshot. */
typedef struct {
    PyObject_HEAD
    PyObject *node;
    unsigned long depth;
    int is_semantic_error;
    int is_recovered;
} WalkStepObject;

static PyTypeObject Session_Type;
static PyTypeObject Node_Type;
static PyTypeObject Walker_Type;
static PyTypeObject WalkStep_Type;

/* ------------------------------------------------------------------ */
/* Argument helpers                                                    */
/* ------------------------------------------------------------------ */

/* What one call crosses with, chosen when the call is made. */
typedef struct {
    GalleySession *session;
    /* The running parse's native hook door, or NULL for the session door. */
    GalleyHookDoor *hook;
    /* The generation the operation's node carries, passed to the core with
     * it on either door. The core refuses one that is not the live tree's;
     * an operation with a second node passes that node's own generation
     * beside it, and the core refuses a pair from two parses. */
    unsigned long long generation;
} NodeCrossing;

/* Chooses the door for a call on an open session: from inside a hook
 * dispatch of the session's running parse, on the thread running that
 * hook, the hook twins over that parse's door; otherwise the session door,
 * which the core refuses while a parse runs. The only place the choice is
 * made. The generation is not chosen here: the first node admitted fixes
 * it, and the core compares it against the door's tree. */
static void choose_door(SessionObject *session_object, NodeCrossing *cross)
{
    cross->session = session_object->session;
    cross->generation = 0;
    if (session_object->dispatching &&
        session_object->dispatch_thread == PyThread_get_thread_ident())
        cross->hook = session_object->parse_door;
    else
        cross->hook = NULL;
}

/* The gate for a call that takes no node: refuses a closed session and
 * chooses the door. */
static int session_crossing(PyObject *session_obj, NodeCrossing *cross)
{
    SessionObject *session_object = (SessionObject *)session_obj;
    if (session_object->session == NULL) {
        PyErr_SetString(PyExc_ValueError, "session is closed");
        return -1;
    }
    choose_door(session_object, cross);
    return 0;
}

/* The single gate for a node about to cross: a closed session raises
 * instead of reading destroyed storage, and the only way to obtain what a
 * crossing needs (the session handle, the native hook door) is through here. */
static int node_crossing(NodeObject *node, NodeCrossing *cross)
{
    SessionObject *session_object = (SessionObject *)node->session_obj;
    if (session_object->session == NULL) {
        PyErr_SetString(PyExc_ValueError, "node's session is closed");
        return -1;
    }
    choose_door(session_object, cross);
    cross->generation = node->generation;
    return 0;
}

/* The single gate for a node-typed argument: only a `Node` crosses, and it
 * must belong to `session_obj`, because the crossing sends a bare address
 * and native storage only bounds-checks it, so a node of another session
 * would silently alias whichever node holds that index here. A raw address
 * carries no generation, so anything that is not a `Node` is refused instead
 * of read through. Hands back the node's address and its own generation;
 * whether that generation is live is the core's to say. */
static int node_parts(PyObject *object, PyObject *session_obj,
                      GalleyNodeAddress *address, unsigned long long *generation)
{
    int is_node = PyObject_IsInstance(object, (PyObject *)&Node_Type);
    if (is_node < 0)
        return -1;
    if (!is_node) {
        PyErr_Format(PyExc_TypeError, "expected a Node, got %s",
                     Py_TYPE(object)->tp_name);
        return -1;
    }
    NodeObject *node_obj = (NodeObject *)object;
    if (node_obj->session_obj != session_obj) {
        PyErr_SetString(PyExc_ValueError,
                        "node belongs to a different session than this operation");
        return -1;
    }
    *address = node_obj->address;
    *generation = node_obj->generation;
    return 0;
}

/* The operation's node: its generation becomes the crossing's. */
static int node_argument(PyObject *object, PyObject *session_obj,
                         NodeCrossing *cross, GalleyNodeAddress *out)
{
    return node_parts(object, session_obj, out, &cross->generation);
}

/* Copies a (data, length) pair into bytes; NULL pointers become b""/"". */
static PyObject *bytes_from_pair(const char *data, size_t length)
{
    return PyBytes_FromStringAndSize(length > 0 ? data : "",
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

/* Ends a native parse leg: the parse's door dies with the parse, and nothing
 * else. The host keeps no generation cache, so there is nothing to refresh —
 * the nodes of this parse fail at their next use because the core refuses
 * their generation. A parse the core refused (`session in use`) started
 * nothing, so it leaves the running parse's door alone. Every native parse
 * leg calls this once, with the GIL held. */
static inline void finish_parse(PyObject *self, long long status)
{
    SessionObject *session_object = (SessionObject *)self;
    if (status == galley_error_session_in_use)
        return;
    session_object->parse_door = NULL;
}

/* Single gate for Node creation: stamps the generation of the crossing the
 * node was read through, so accessors refuse stale reads after a re-parse.
 * NULL with ValueError when the session is closed. */
static NodeObject *make_node(PyObject *session_obj, unsigned long long generation,
                             GalleyNodeAddress address)
{
    SessionObject *session_object = (SessionObject *)session_obj;
    if (session_object->session == NULL) {
        PyErr_SetString(PyExc_ValueError, "session is closed");
        return NULL;
    }
    NodeObject *node_obj = PyObject_New(NodeObject, &Node_Type);
    if (node_obj == NULL)
        return NULL;
    node_obj->session_obj = Py_NewRef(session_obj);
    node_obj->address = address;
    node_obj->generation = generation;
    return node_obj;
}

/* -- door crossing ----------------------------------------------------
 * One crossing per capability: the crossing decides the family, and the
 * NodeCrossing a caller crosses with only ever comes out of a gate
 * (session_crossing, node_crossing). The session family is galley_<name>,
 * its hook twin galley_hook_<name>; the two take the same arguments after
 * the handle, and both check the node's generation in the core, so a
 * refusal is a negative status on either. */

/* The one dispatch: every node, tree and walk call crosses through here,
 * and the caller only checks the status. GALLEY_CROSS_BARE passes the
 * arguments as they are (the walk step: its cursor carries the generation);
 * GALLEY_CROSS adds the crossing's generation after the handle. */
#define GALLEY_CROSS_BARE(cross, name, ...)                                         \
    ((cross).hook != NULL ? galley_hook_##name((cross).hook, __VA_ARGS__)           \
                          : galley_##name((cross).session, __VA_ARGS__))
#define GALLEY_CROSS(cross, name, ...) \
    GALLEY_CROSS_BARE(cross, name, (cross).generation, __VA_ARGS__)

/* A value-returning call (a link, the child count, the variable index)
 * through the chosen door: its value, or -1 with the error raised. */
#define CROSS_VALUE(cross, name, address) \
    check_value(GALLEY_CROSS(cross, name, address))

/* The node a checked link names: None for a missing link, the node
 * stamped with the crossing's generation otherwise, NULL when the link read
 * raised (`link` is -1). */
static PyObject *link_object(PyObject *session_obj, unsigned long long generation, long long link)
{
    if (link < 0)
        return NULL;
    if ((GalleyNodeAddress)link == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    return (PyObject *)make_node(session_obj, generation, (GalleyNodeAddress)link);
}

/* The one children loop: count-bounded, first to last, every step
 * crossing the same door and every result stamped with its generation. The
 * crossing comes out of a gate, so callers cannot skip it. */
static PyObject *children_via(PyObject *session_obj, NodeCrossing cross,
                              GalleyNodeAddress address)
{
    long long count = CROSS_VALUE(cross, node_child_count, address);
    long long link;
    PyObject *tuple;
    Py_ssize_t i;

    if (count < 0)
        return NULL;
    tuple = PyTuple_New((Py_ssize_t)count);
    if (tuple == NULL)
        return NULL;
    link = CROSS_VALUE(cross, node_first_child, address);
    for (i = 0; i < (Py_ssize_t)count; ++i) {
        NodeObject *node_obj;
        if (link < 0) {
            Py_DECREF(tuple);
            return NULL;
        }
        if ((GalleyNodeAddress)link == GALLEY_INVALID_NODE) {
            PyErr_SetString(PyExc_RuntimeError,
                            "child count changed during iteration");
            Py_DECREF(tuple);
            return NULL;
        }
        node_obj = make_node(session_obj, cross.generation, (GalleyNodeAddress)link);
        if (node_obj == NULL) {
            Py_DECREF(tuple);
            return NULL;
        }
        PyTuple_SET_ITEM(tuple, i, (PyObject *)node_obj);
        link = CROSS_VALUE(cross, node_next_sibling, (GalleyNodeAddress)link);
    }
    if (link < 0) {
        Py_DECREF(tuple);
        return NULL;
    }
    return tuple;
}

/* One value function per capability, shared by the session method (a node
 * argument) and the Node method (the node itself): each takes an admitted
 * crossing and names its capability once. Links answer None for a missing
 * link, and every refusal raises. */
#define DEFINE_LINK_VALUE(function, name)                                       \
    static PyObject *function(PyObject *session_obj, const NodeCrossing *crossing, \
                              GalleyNodeAddress address)                        \
    {                                                                           \
        NodeCrossing cross = *crossing;                                         \
        return link_object(session_obj, cross.generation, CROSS_VALUE(cross, name, address)); \
    }

#define DEFINE_BYTES_VALUE(function, name)                                      \
    static PyObject *function(PyObject *Py_UNUSED(session_obj),                 \
                              const NodeCrossing *crossing, GalleyNodeAddress address) \
    {                                                                           \
        NodeCrossing cross = *crossing;                                         \
        const char *data = NULL;                                                \
        size_t length = 0;                                                      \
        if (check_status(GALLEY_CROSS(cross, name, address, &data, &length)) < 0) \
            return NULL;                                                        \
        return bytes_from_pair(data, length);                                   \
    }

DEFINE_LINK_VALUE(first_child_value, node_first_child)
DEFINE_LINK_VALUE(last_child_value, node_last_child)
DEFINE_LINK_VALUE(next_sibling_value, node_next_sibling)
DEFINE_LINK_VALUE(prior_sibling_value, node_prior_sibling)
DEFINE_LINK_VALUE(parent_value, node_parent)
DEFINE_BYTES_VALUE(symbol_name_value, node_symbol_name)
DEFINE_BYTES_VALUE(text_value, node_text)

static PyObject *child_count_value(PyObject *Py_UNUSED(session_obj),
                                   const NodeCrossing *crossing, GalleyNodeAddress address)
{
    NodeCrossing cross = *crossing;
    long long count = CROSS_VALUE(cross, node_child_count, address);
    return count < 0 ? NULL : PyLong_FromLongLong(count);
}

static PyObject *span_value(PyObject *Py_UNUSED(session_obj),
                            const NodeCrossing *crossing, GalleyNodeAddress address)
{
    NodeCrossing cross = *crossing;
    unsigned long long start = 0;
    unsigned long long length = 0;
    if (check_status(GALLEY_CROSS(cross, node_span, address, &start, &length)) < 0)
        return NULL;
    return Py_BuildValue("KK", start, length);
}

static PyObject *line_column_value(PyObject *Py_UNUSED(session_obj),
                                   const NodeCrossing *crossing, GalleyNodeAddress address)
{
    NodeCrossing cross = *crossing;
    unsigned int line = 0;
    unsigned int column = 0;
    if (check_status(GALLEY_CROSS(cross, node_line_column, address, &line, &column)) < 0)
        return NULL;
    return Py_BuildValue("II", line, column);
}

static PyObject *variable_index_value(PyObject *Py_UNUSED(session_obj),
                                      const NodeCrossing *crossing, GalleyNodeAddress address)
{
    NodeCrossing cross = *crossing;
    long long index = CROSS_VALUE(cross, node_variable_index, address);
    if (index < 0)
        return NULL;
    if (index == GALLEY_NO_VARIABLE)
        Py_RETURN_NONE;
    return PyLong_FromLongLong(index);
}

/* The session method over a value function: the session crossing, one node
 * argument, then the value. */
static PyObject *session_value(PyObject *session_obj, PyObject *node,
                               PyObject *(*value)(PyObject *, const NodeCrossing *, GalleyNodeAddress))
{
    NodeCrossing cross;
    GalleyNodeAddress address;
    if (session_crossing(session_obj, &cross) < 0)
        return NULL;
    if (node_argument(node, session_obj, &cross, &address) < 0)
        return NULL;
    return value(session_obj, &cross, address);
}

/* The Node method over a value function. */
static PyObject *node_value(NodeObject *self,
                            PyObject *(*value)(PyObject *, const NodeCrossing *, GalleyNodeAddress))
{
    NodeCrossing cross;
    if (node_crossing(self, &cross) < 0)
        return NULL;
    return value(self->session_obj, &cross, self->address);
}

static int commit_hooks(SessionObject *self, GalleySession *session, PyObject *table);

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
    /* The session's own hooks start as a copy of the module's defaults. */
    PyObject *defaults = py_procedure_table != NULL ? PyDict_Copy(py_procedure_table)
                                                    : PyDict_New();
    if (defaults == NULL || commit_hooks(self, session, defaults) < 0) {
        Py_XDECREF(defaults);
        galley_session_destroy(session);
        return -1;
    }
    Py_DECREF(defaults);
    if (self->session != NULL)
        galley_session_destroy(self->session);
    self->session = session;
    /* A re-init orphans prior nodes and walkers: nothing is published on
     * the new session, so their next access raises instead of reading the
     * new storage. */
    self->parse_door = NULL;
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

static PyObject *Session_is_closed(SessionObject *self, PyObject *Py_UNUSED(ignored))
{
    if (self->session == NULL)
        Py_RETURN_TRUE;
    Py_RETURN_FALSE;
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

/* Hooks are callables a session holds and they may close over the session,
 * so the session takes part in cycle collection. */
static int Session_traverse(SessionObject *self, visitproc visit, void *arg)
{
    Py_VISIT(self->hooks);
    Py_VISIT(self->hooks_by_index);
    return 0;
}

static int Session_clear(SessionObject *self)
{
    Py_CLEAR(self->hooks);
    Py_CLEAR(self->hooks_by_index);
    return 0;
}

static void Session_dealloc(SessionObject *self)
{
    PyObject_GC_UnTrack(self);
    close_session(self);
    Session_clear(self);
    Py_TYPE(self)->tp_free((PyObject *)self);
}

PyDoc_STRVAR(parse_doc,
"parse(input)\n"
"\n"
"Parses a str or bytes-like input that may contain NUL bytes and returns\n"
"the number of bytes parsed. The session copies the input, so parsed\n"
"text stays readable after the call regardless of what happens to the\n"
"object. Raises GalleyError on failure; inspect diagnostic() for structured\n"
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
    /* A zero-length input must not present a NULL pointer. The GIL is
     * released for the parse itself: the input stays alive (an immutable
     * str or bytes, or a buffer export that blocks resizing), and a hook
     * takes the GIL back for the length of its call. */
    Py_BEGIN_ALLOW_THREADS
    status = galley_parse(session, length > 0 ? data : "", (size_t)length);
    Py_END_ALLOW_THREADS
    finish_parse(self, status);
    if (have_view)
        PyBuffer_Release(&view);
    return status_to_parsed_with_session(status, session);
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
    Py_ssize_t path_length = 0;
    if (PyUnicode_Check(filesystem_path)) {
        data = PyUnicode_AsUTF8AndSize(filesystem_path, &path_length);
    } else if (PyBytes_Check(filesystem_path)) {
        data = PyBytes_AS_STRING(filesystem_path);
        path_length = PyBytes_GET_SIZE(filesystem_path);
    } else {
        PyErr_SetString(PyExc_TypeError, "path must be str or bytes");
    }
    /* Paths cross into native code NUL-terminated: an interior NUL
     * would silently truncate, so reject loudly instead. */
    if (data != NULL && memchr(data, '\0', (size_t)path_length) != NULL) {
        PyErr_SetString(PyExc_ValueError, "path contains an interior NUL byte");
        data = NULL;
    }
    if (data != NULL) {
        long long status;
        Py_BEGIN_ALLOW_THREADS
        status = galley_parse_file(session, data);
        Py_END_ALLOW_THREADS
        finish_parse(self, status);
        result = status_to_parsed_with_session(status, session);
    }
    Py_DECREF(filesystem_path);
    return result;
}

PyDoc_STRVAR(node_count_doc,
"node_count()\n"
"\n"
"Returns the number of AST nodes of the published tree (always 0 when the\n"
"parser was built without AST construction). Raises StaleTreeError when no\n"
"tree is published: read root_node() and use its generation instead.");

static PyObject *Session_node_count(PyObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleySession *session = require_session(self);
    long long count = 0;
    unsigned long long generation = 0;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;

    if (session == NULL)
        return NULL;
    /* One read of the core answers both the root and the generation this
     * count belongs to; the core then refuses a count of a tree that is
     * gone, generation 0 (nothing published) included. */
    if (check_status(galley_root_node(session, &root, &generation)) < 0)
        return NULL;
    count = check_value(galley_node_count(session, generation));
    if (count < 0)
        return NULL;
    return PyLong_FromLongLong(count);
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
"Returns the current node storage capacity in nodes. Raises GalleyError\n"
"(session in use) while a parse runs.");

static PyObject *Session_node_capacity(PyObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleySession *session = require_session(self);
    if (session == NULL)
        return NULL;
    long long capacity = check_value(galley_node_capacity(session));
    return capacity < 0 ? NULL : PyLong_FromLongLong(capacity);
}

PyDoc_STRVAR(root_node_doc,
"root_node()\n"
"\n"
"Returns the root node of the most recent successful parse, or None when\n"
"there is none. Raises GalleyError (session in use) while a parse runs.\n"
"The node carries the core parse generation it belongs to, which every\n"
"later read of it passes back to the core.");

static PyObject *Session_root_node(PyObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleySession *session = require_session(self);
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    unsigned long long generation = 0;

    if (session == NULL)
        return NULL;
    /* One read of the core answers both: the root and the generation every
     * node of that tree carries. Nothing here is published, so nothing here.
     */
    if (check_status(galley_root_node(session, &root, &generation)) < 0)
        return NULL;
    if (root == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    return (PyObject *)make_node(self, generation, root);
}

PyDoc_STRVAR(child_count_doc,
"child_count(node)\n"
"\n"
"Returns the number of direct children of a node (0 for a leaf).");

static PyObject *Session_child_count(PyObject *self, PyObject *node)
{
    return session_value(self, node, child_count_value);
}

PyDoc_STRVAR(children_doc,
"children(node)\n"
"\n"
"Returns a tuple of the direct children of a node, from first to last.\n"
"An empty tuple means no children. The tuple is iterable, so\n"
"'for child in session.children(node):' works.");

static PyObject *Session_children(PyObject *self, PyObject *node)
{
    NodeCrossing cross;
    GalleyNodeAddress address;

    if (session_crossing(self, &cross) < 0)
        return NULL;
    if (node_argument(node, self, &cross, &address) < 0)
        return NULL;
    return children_via(self, cross, address);
}

PyDoc_STRVAR(first_child_doc,
"first_child(node)\n"
"\n"
"Returns the first child of a node, or None when the link does not\n"
"exist.");

static PyObject *Session_first_child(PyObject *self, PyObject *node)
{
    return session_value(self, node, first_child_value);
}

PyDoc_STRVAR(last_child_doc,
"last_child(node)\n"
"\n"
"Returns the last child of a node, or None when the link does not\n"
"exist.");

static PyObject *Session_last_child(PyObject *self, PyObject *node)
{
    return session_value(self, node, last_child_value);
}

PyDoc_STRVAR(next_sibling_doc,
"next_sibling(node)\n"
"\n"
"Returns the next sibling of a node, or None when the link does not\n"
"exist.");

static PyObject *Session_next_sibling(PyObject *self, PyObject *node)
{
    return session_value(self, node, next_sibling_value);
}

PyDoc_STRVAR(prior_sibling_doc,
"prior_sibling(node)\n"
"\n"
"Returns the previous sibling of a node, or None when the link does not\n"
"exist.");

static PyObject *Session_prior_sibling(PyObject *self, PyObject *node)
{
    return session_value(self, node, prior_sibling_value);
}

PyDoc_STRVAR(parent_doc,
"parent(node)\n"
"\n"
"Returns the parent of a node, or None for the root.");

static PyObject *Session_parent(PyObject *self, PyObject *node)
{
    return session_value(self, node, parent_value);
}

static PyObject *address_or_none(GalleyNodeAddress address)
{
    if (address == GALLEY_INVALID_NODE)
        return Py_NewRef(Py_None);
    return PyLong_FromUnsignedLongLong(address);
}

/* ------------------------------------------------------------------ */
/* Snapshot — one parse as flat columns, with the one sanctioned       */
/* address → node conversion                                           */
/* ------------------------------------------------------------------ */

typedef struct SnapshotObject {
    PyObject_HEAD
    /* The session the columns came from, and the published parse
     * generation they describe: node() stamps that generation, so its
     * nodes belong to this snapshot's parse and read as stale once the
     * session parses again. */
    PyObject *session_obj;
    unsigned long long generation;
    unsigned long long count;
    PyObject *parent;
    PyObject *first_child;
    PyObject *next;
    PyObject *child_count;
    PyObject *variable;
    PyObject *span_start;
    PyObject *span_len;
    PyObject *is_semantic_error;
    PyObject *is_recovered;
} SnapshotObject;

static void Snapshot_dealloc(SnapshotObject *self)
{
    Py_XDECREF(self->session_obj);
    Py_XDECREF(self->parent);
    Py_XDECREF(self->first_child);
    Py_XDECREF(self->next);
    Py_XDECREF(self->child_count);
    Py_XDECREF(self->variable);
    Py_XDECREF(self->span_start);
    Py_XDECREF(self->span_len);
    Py_XDECREF(self->is_semantic_error);
    Py_XDECREF(self->is_recovered);
    Py_TYPE(self)->tp_free((PyObject *)self);
}

PyDoc_STRVAR(Snapshot_node_doc,
"node(index)\n"
"\n"
"Returns the node at ``index`` for the parse these columns describe,\n"
"or None for ``INVALID_NODE``. Raises TypeError when ``index`` is not\n"
"an ``int`` (a ``bool`` included), IndexError when ``index`` is\n"
"outside ``0 .. count - 1``. The node carries this snapshot's parse\n"
"generation, so it raises StaleTreeError once the session parses again.");

static PyObject *Snapshot_node(SnapshotObject *self, PyObject *arg)
{
    unsigned long long index;

    /* bool subclasses int, but True/False are not node addresses. */
    if (PyBool_Check(arg)) {
        PyErr_SetString(PyExc_TypeError,
                        "node index must be an int, not a bool");
        return NULL;
    }
    index = PyLong_AsUnsignedLongLong(arg);
    if (index == (unsigned long long)-1 && PyErr_Occurred()) {
        /* A negative index is out of range; anything else is not an index. */
        if (PyErr_ExceptionMatches(PyExc_OverflowError)) {
            PyErr_Clear();
            PyErr_SetString(PyExc_IndexError, "node index out of range");
        }
        return NULL;
    }
    if (index == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    if (index >= self->count) {
        PyErr_Format(PyExc_IndexError,
                     "node index %llu out of range for a snapshot of %llu nodes",
                     index, self->count);
        return NULL;
    }
    return (PyObject *)make_node(self->session_obj, self->generation,
                                 (GalleyNodeAddress)index);
}

static PyMethodDef Snapshot_methods[] = {
    {"node", (PyCFunction)Snapshot_node, METH_O, Snapshot_node_doc},
    {NULL, NULL, 0, NULL}
};

/* One getter for every column: the closure is the field's offset, and
 * the columns are read-only tuples, so a caller cannot rewrite them. */
static PyObject *Snapshot_column(SnapshotObject *self, void *closure)
{
    PyObject **slot = (PyObject **)((char *)self + (size_t)closure);
    return Py_NewRef(*slot);
}

static PyObject *Snapshot_get_count(SnapshotObject *self,
                                    void *Py_UNUSED(closure))
{
    return PyLong_FromUnsignedLongLong(self->count);
}

#define SNAPSHOT_COLUMN(name, field, docstring)                              \
    {name, (getter)Snapshot_column, NULL, docstring, (void *)offsetof(SnapshotObject, field)}

static PyGetSetDef Snapshot_getset[] = {
    {"count", (getter)Snapshot_get_count, NULL,
     "Number of nodes in the parse these columns describe.", NULL},
    SNAPSHOT_COLUMN("parent", parent,
                    "Parent address per node; None where the link does not exist."),
    SNAPSHOT_COLUMN("first_child", first_child,
                    "First child address per node; None where the link does not exist."),
    SNAPSHOT_COLUMN("next", next,
                    "Next sibling address per node; None where the link does not exist."),
    SNAPSHOT_COLUMN("child_count", child_count,
                    "Direct child count per node."),
    SNAPSHOT_COLUMN("variable", variable,
                    "Variable index per node; None where there is none."),
    SNAPSHOT_COLUMN("span_start", span_start,
                    "Span start offset per node, into ``last_input()``."),
    SNAPSHOT_COLUMN("span_len", span_len,
                    "Span length per node."),
    SNAPSHOT_COLUMN("is_semantic_error", is_semantic_error,
                     "The semantic-error flag a walk step carries, per node."),
    SNAPSHOT_COLUMN("is_recovered", is_recovered,
                     "The recovered flag a walk step carries, per node: True "
                     "for a node syntax-error recovery kept in place of "
                     "damaged input."),
    {NULL, NULL, NULL, NULL, NULL}
};

static PyTypeObject Snapshot_Type = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = GALLEY_MODULE_STRING ".Snapshot",
    .tp_basicsize = sizeof(SnapshotObject),
    .tp_itemsize = 0,
    .tp_dealloc = (destructor)Snapshot_dealloc,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_doc = "One parse as flat columns: read-only attributes per node "
              "address, plus node(index) as the only address to node conversion.",
    .tp_methods = Snapshot_methods,
    .tp_getset = Snapshot_getset,
};

PyDoc_STRVAR(snapshot_doc,
"snapshot()\n"
"\n"
"Returns the published parse as flat tuples in a single call: a\n"
"Snapshot with ``count`` and one tuple per node address for\n"
"``parent``, ``first_child``, ``next``, ``child_count``, ``variable``,\n"
"``span_start``, ``span_len``, ``is_semantic_error`` and\n"
"``is_recovered`` (the flags a walk step carries). Missing links and\n"
"variables are None. Raises StaleTreeError when nothing is published. The columns\n"
"are read-only; ``snapshot.node(index)`` is the one conversion from a\n"
"column address back to a node, and only for the parse these columns\n"
"describe.\n"
"Walk ``parent``/``first_child``/``next`` directly instead of one call\n"
"per node; resolve spans against ``last_input()``.");

static PyObject *Session_snapshot(PyObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleySession *session = require_session(self);
    unsigned long long count;
    long long counted;
    GalleyNodeAddress *parent = NULL;
    GalleyNodeAddress *first_child = NULL;
    GalleyNodeAddress *next = NULL;
    unsigned int *child_count = NULL;
    long long *variable = NULL;
    unsigned long long *span_start = NULL;
    unsigned long long *span_len = NULL;
    int *is_semantic_error = NULL;
    int *is_recovered = NULL;
    long long total;
    SnapshotObject *snapshot = NULL;
    unsigned long long generation;
    GalleyNodeAddress root = GALLEY_INVALID_NODE;
    PyObject *t_parent = NULL;
    PyObject *t_first = NULL;
    PyObject *t_next = NULL;
    PyObject *t_child_count = NULL;
    PyObject *t_variable = NULL;
    PyObject *t_span_start = NULL;
    PyObject *t_span_len = NULL;
    PyObject *t_semantic = NULL;
    PyObject *t_recovered = NULL;
    unsigned long long i;

    if (session == NULL)
        return NULL;
    /* The columns describe one parse, so every leg carries that parse's
     * generation: root answers it, the count and the columns refuse it if a
     * parse ran in between, and node() stamps it on the nodes it hands back.
     * Nothing published (generation 0) is the core's stale-tree refusal, not an
     * empty snapshot. */
    if (check_status(galley_root_node(session, &root, &generation)) < 0)
        return NULL;
    counted = check_value(galley_node_count(session, generation));
    if (counted < 0)
        return NULL;
    count = (unsigned long long)counted;
    if (count > 0) {
        parent = PyMem_Malloc(count * sizeof(*parent));
        first_child = PyMem_Malloc(count * sizeof(*first_child));
        next = PyMem_Malloc(count * sizeof(*next));
        child_count = PyMem_Malloc(count * sizeof(*child_count));
        variable = PyMem_Malloc(count * sizeof(*variable));
        span_start = PyMem_Malloc(count * sizeof(*span_start));
        span_len = PyMem_Malloc(count * sizeof(*span_len));
        is_semantic_error = PyMem_Malloc(count * sizeof(*is_semantic_error));
        is_recovered = PyMem_Malloc(count * sizeof(*is_recovered));
        if (parent == NULL || first_child == NULL || next == NULL ||
            child_count == NULL || variable == NULL ||
            span_start == NULL || span_len == NULL ||
            is_semantic_error == NULL || is_recovered == NULL) {
            PyErr_NoMemory();
            goto done;
        }
    }
    total = galley_tree_snapshot(session, generation, parent, first_child, next,
                                 child_count, variable, span_start,
                                 span_len, is_semantic_error, is_recovered,
                                 count);
    if (total < 0) {
        set_error_from_status(total);
        goto done;
    }
    if ((unsigned long long)total != count) {
        PyErr_SetString(PyExc_RuntimeError,
                        "node count changed during snapshot");
        goto done;
    }
    t_parent = PyTuple_New((Py_ssize_t)count);
    t_first = PyTuple_New((Py_ssize_t)count);
    t_next = PyTuple_New((Py_ssize_t)count);
    t_child_count = PyTuple_New((Py_ssize_t)count);
    t_variable = PyTuple_New((Py_ssize_t)count);
    t_span_start = PyTuple_New((Py_ssize_t)count);
    t_span_len = PyTuple_New((Py_ssize_t)count);
    t_semantic = PyTuple_New((Py_ssize_t)count);
    t_recovered = PyTuple_New((Py_ssize_t)count);
    if (t_parent == NULL || t_first == NULL || t_next == NULL ||
        t_child_count == NULL || t_variable == NULL ||
        t_span_start == NULL || t_span_len == NULL || t_semantic == NULL ||
        t_recovered == NULL)
        goto done;
    for (i = 0; i < count; ++i) {
        PyObject *item;
        item = address_or_none(parent[i]);
        if (item == NULL) goto done;
        PyTuple_SET_ITEM(t_parent, (Py_ssize_t)i, item);
        item = address_or_none(first_child[i]);
        if (item == NULL) goto done;
        PyTuple_SET_ITEM(t_first, (Py_ssize_t)i, item);
        item = address_or_none(next[i]);
        if (item == NULL) goto done;
        PyTuple_SET_ITEM(t_next, (Py_ssize_t)i, item);
        item = PyLong_FromUnsignedLong(child_count[i]);
        if (item == NULL) goto done;
        PyTuple_SET_ITEM(t_child_count, (Py_ssize_t)i, item);
        if (variable[i] == GALLEY_NO_VARIABLE)
            item = Py_NewRef(Py_None);
        else
            item = PyLong_FromLongLong(variable[i]);
        if (item == NULL) goto done;
        PyTuple_SET_ITEM(t_variable, (Py_ssize_t)i, item);
        item = PyLong_FromUnsignedLongLong(span_start[i]);
        if (item == NULL) goto done;
        PyTuple_SET_ITEM(t_span_start, (Py_ssize_t)i, item);
        item = PyLong_FromUnsignedLongLong(span_len[i]);
        if (item == NULL) goto done;
        PyTuple_SET_ITEM(t_span_len, (Py_ssize_t)i, item);
        item = PyBool_FromLong(is_semantic_error[i]);
        if (item == NULL) goto done;
        PyTuple_SET_ITEM(t_semantic, (Py_ssize_t)i, item);
        item = PyBool_FromLong(is_recovered[i]);
        if (item == NULL) goto done;
        PyTuple_SET_ITEM(t_recovered, (Py_ssize_t)i, item);
    }
    snapshot = PyObject_New(SnapshotObject, &Snapshot_Type);
    if (snapshot == NULL)
        goto done;
    snapshot->session_obj = Py_NewRef(self);
    snapshot->generation = generation;
    snapshot->count = count;
    snapshot->parent = t_parent;
    snapshot->first_child = t_first;
    snapshot->next = t_next;
    snapshot->child_count = t_child_count;
    snapshot->variable = t_variable;
    snapshot->span_start = t_span_start;
    snapshot->span_len = t_span_len;
    snapshot->is_semantic_error = t_semantic;
    snapshot->is_recovered = t_recovered;
    t_parent = NULL;
    t_first = NULL;
    t_next = NULL;
    t_child_count = NULL;
    t_variable = NULL;
    t_span_start = NULL;
    t_span_len = NULL;
    t_semantic = NULL;
    t_recovered = NULL;
done:
    Py_XDECREF(t_parent);
    Py_XDECREF(t_first);
    Py_XDECREF(t_next);
    Py_XDECREF(t_child_count);
    Py_XDECREF(t_variable);
    Py_XDECREF(t_span_start);
    Py_XDECREF(t_span_len);
    Py_XDECREF(t_semantic);
    Py_XDECREF(t_recovered);
    PyMem_Free(parent);
    PyMem_Free(first_child);
    PyMem_Free(next);
    PyMem_Free(child_count);
    PyMem_Free(variable);
    PyMem_Free(span_start);
    PyMem_Free(span_len);
    PyMem_Free(is_semantic_error);
    PyMem_Free(is_recovered);
    return (PyObject *)snapshot;
}

PyDoc_STRVAR(symbol_name_doc,
"symbol_name(node)\n"
"\n"
"Returns the grammar symbol name of a node as bytes (empty for\n"
"terminal-only nodes). A refused node raises (StaleTreeError, or\n"
"GalleyError for an invalid node), on both doors.");

static PyObject *Session_symbol_name(PyObject *self, PyObject *node)
{
    return session_value(self, node, symbol_name_value);
}

PyDoc_STRVAR(text_doc,
"text(node)\n"
"\n"
"Returns the source text matched by a node as bytes. A refused node\n"
"raises (StaleTreeError, or GalleyError for an invalid node).");

static PyObject *Session_text(PyObject *self, PyObject *node)
{
    return session_value(self, node, text_value);
}

PyDoc_STRVAR(last_input_doc,
"last_input()\n"
"\n"
"Returns the retained input of the published parse as bytes: the\n"
"buffer that snapshot spans index. Follows the published tree like\n"
"every node read: raises StaleTreeError whenever nothing is published\n"
"(before the first parse included), and GalleyError with\n"
"ERROR_SESSION_IN_USE while a parse holds the session.");

static PyObject *Session_last_input(PyObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleySession *session = require_session(self);
    const char *data = NULL;
    size_t length = 0;

    if (session == NULL)
        return NULL;
    if (check_status(galley_last_input(session, &data, &length)) < 0)
        return NULL;
    return PyBytes_FromStringAndSize(data, (Py_ssize_t)length);
}

PyDoc_STRVAR(span_doc,
"span(node)\n"
"\n"
"Returns the (start, length) byte span a node matched in the published\n"
"parse's input. A refused node raises (StaleTreeError, or GalleyError\n"
"for an invalid node).");

static PyObject *Session_span(PyObject *self, PyObject *node)
{
    return session_value(self, node, span_value);
}

PyDoc_STRVAR(line_column_doc,
"line_column(node)\n"
"\n"
"Returns the 1-based (line, column) of a node's first byte. A refused\n"
"node raises (StaleTreeError, or GalleyError for an invalid node). Scans\n"
"the retained input, so cost is linear in the offset.");

static PyObject *Session_line_column(PyObject *self, PyObject *node)
{
    return session_value(self, node, line_column_value);
}

PyDoc_STRVAR(variable_index_doc,
"variable_index(node)\n"
"\n"
"Returns the raw variable index of a node into the variable list, or\n"
"None when the node has no variable.");

static PyObject *Session_variable_index(PyObject *self, PyObject *node)
{
    return session_value(self, node, variable_index_value);
}

PyDoc_STRVAR(last_position_doc,
"last_position()\n"
"\n"
"Returns the 1-based (line, column) where the published parse ended\n"
"(zeros when the parser was built without position tracking). Raises\n"
"like last_input() when nothing is published.");

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
    PyObject *context;               /* tuple[bytes, ...] */
    long syntax_error_count;
    long semantic_error_count;
    PyObject *semantic;              /* (variable bytes, message str) | None */
    PyObject *indentation;           /* (spaces, width) | None */
    PyObject *recovery_kind;         /* int | None */
    PyObject *recovery_terminal;     /* bytes | None */
    PyObject *recovery_resume;       /* int | None */
    PyObject *recovery_lhs_variable; /* bytes | None */
    PyObject *recovery_production;   /* (variable bytes, rhs_index) | None */
    PyObject *recovery_occurrence;   /* (parent bytes, rhs, symbol, variable bytes) | None */
} DiagnosticObject;

static void Diagnostic_dealloc(DiagnosticObject *self)
{
    Py_XDECREF(self->message);
    Py_XDECREF(self->message_ansi);
    Py_XDECREF(self->unexpected_token);
    Py_XDECREF(self->expected_tokens);
    Py_XDECREF(self->context);
    Py_XDECREF(self->indentation);
    Py_XDECREF(self->semantic);
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
     "diagnostic classification: Kind.NONE, Kind.SYNTAX, Kind.SEMANTIC, Kind.INDENTATION"},
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
    {"semantic_error_count", T_LONG,
     offsetof(DiagnosticObject, semantic_error_count), READONLY,
     "how many semantic errors the parse recorded"},
    {"semantic", T_OBJECT,
     offsetof(DiagnosticObject, semantic), READONLY,
     "(variable bytes, message str) for semantic errors, else None"},
    {"indentation", T_OBJECT, offsetof(DiagnosticObject, indentation),
     READONLY,
     "(emitted spaces, indentation width) for indentation errors"},
    {"recovery_kind", T_OBJECT, offsetof(DiagnosticObject, recovery_kind),
     READONLY, "applied recovery target (RecoveryTarget.NONE, RecoveryTarget.LHS_VARIABLE, RecoveryTarget.PRODUCTION, RecoveryTarget.OCCURRENCE)"},
    {"recovery_terminal", T_OBJECT,
     offsetof(DiagnosticObject, recovery_terminal), READONLY,
     "synchronization terminal bytes chosen by recovery"},
    {"recovery_resume", T_OBJECT,
     offsetof(DiagnosticObject, recovery_resume), READONLY,
     "Resume.BEFORE or Resume.AFTER"},
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
    .tp_name = GALLEY_MODULE_STRING ".Diagnostic",
    .tp_basicsize = sizeof(DiagnosticObject),
    .tp_itemsize = 0,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_members = Diagnostic_members,
    .tp_dealloc = (destructor)Diagnostic_dealloc,
};

static PyObject *diagnostic_rendered_message(PyObject *diagnostic)
{
    PyObject *rendered = ((DiagnosticObject *)diagnostic)->message;
    if (rendered != NULL && PyUnicode_Check(rendered))
        return Py_NewRef(rendered);
    return NULL;
}

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
    diagnostic->semantic_error_count = 0;
    diagnostic->semantic = Py_NewRef(Py_None);
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
            name = bytes_from_pair(text, length);
            if (name == NULL)
                goto fail;
            PyTuple_SET_ITEM(context, (Py_ssize_t)index, name);
        }
    }
    count = galley_syntax_error_count(session);
    if (count >= 0)
        diagnostic->syntax_error_count = (long)count;
    count = galley_semantic_error_count(session);
    if (count >= 0)
        diagnostic->semantic_error_count = (long)count;
    {
        const char *variable = NULL;
        size_t variable_len = 0;
        const char *message = NULL;
        size_t message_len = 0;
        if (galley_diagnostic_semantic(session, &variable, &variable_len, &message, &message_len) == galley_ok) {
            PyObject *pair = PyTuple_New(2);
            PyObject *variable_obj;
            PyObject *message_obj;
            if (pair == NULL)
                goto fail;
            variable_obj = PyBytes_FromStringAndSize(variable ? variable : "", variable ? (Py_ssize_t)variable_len : 0);
            message_obj = PyUnicode_FromStringAndSize(message ? message : "", message ? (Py_ssize_t)message_len : 0);
            if (variable_obj == NULL || message_obj == NULL) {
                Py_XDECREF(variable_obj);
                Py_XDECREF(message_obj);
                Py_DECREF(pair);
                goto fail;
            }
            PyTuple_SET_ITEM(pair, 0, variable_obj);
            PyTuple_SET_ITEM(pair, 1, message_obj);
            Py_SETREF(diagnostic->semantic, pair);
        }
    }
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
        PyObject *name = bytes_from_pair(text, length);
        if (name == NULL)
            goto fail;
        Py_SETREF(diagnostic->recovery_lhs_variable, name);
    }
    if (galley_diagnostic_recovery_production(session, &text, &length,
                                              &first) == galley_ok) {
        PyObject *name = bytes_from_pair(text, length);
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
                bytes_from_pair(parent_text, parent_length);
            PyObject *variable_name =
                bytes_from_pair(variable_text, variable_length);
            PyObject *quadruple;
            if (parent_name == NULL || variable_name == NULL) {
                Py_XDECREF(parent_name);
                Py_XDECREF(variable_name);
                goto fail;
            }
            quadruple = Py_BuildValue("(NIIN)", parent_name, first, second,
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
    diagnostic->semantic_error_count = 0;
    diagnostic->semantic = Py_NewRef(Py_None);
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
            item = PyBytes_FromStringAndSize(name ? name : "", name ? (Py_ssize_t)name_len : 0);
            if (item == NULL)
                goto fail;
            PyTuple_SET_ITEM(context, (Py_ssize_t)i, item);
        }
    }
    {
        const char *variable = NULL;
        size_t variable_len = 0;
        const char *message = NULL;
        size_t message_len = 0;
        if (galley_recorded_semantic(session, index, &variable, &variable_len, &message, &message_len) == galley_ok) {
            PyObject *pair = PyTuple_New(2);
            PyObject *variable_obj;
            PyObject *message_obj;
            if (pair == NULL)
                goto fail;
            variable_obj = PyBytes_FromStringAndSize(variable ? variable : "", variable ? (Py_ssize_t)variable_len : 0);
            message_obj = PyUnicode_FromStringAndSize(message ? message : "", message ? (Py_ssize_t)message_len : 0);
            if (variable_obj == NULL || message_obj == NULL) {
                Py_XDECREF(variable_obj);
                Py_XDECREF(message_obj);
                Py_DECREF(pair);
                goto fail;
            }
            PyTuple_SET_ITEM(pair, 0, variable_obj);
            PyTuple_SET_ITEM(pair, 1, message_obj);
            Py_SETREF(diagnostic->semantic, pair);
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
    NodeCrossing cross;
    GalleyNodeAddress parent;
    GalleyNodeAddress chain;
    unsigned long long chain_generation;

    if (session_crossing(self, &cross) < 0)
        return NULL;
    if (expect_arguments("append_children", count, 2) < 0)
        return NULL;
    if (node_argument(arguments[0], self, &cross, &parent) < 0 ||
        node_parts(arguments[1], self, &chain, &chain_generation) < 0)
        return NULL;
    if (check_status(GALLEY_CROSS(cross, tree_append_children, parent, chain_generation, chain)) < 0)
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
    NodeCrossing cross;
    GalleyNodeAddress target;
    GalleyNodeAddress chain;
    unsigned long long chain_generation;

    if (session_crossing(self, &cross) < 0)
        return NULL;
    if (expect_arguments("insert_before", count, 2) < 0)
        return NULL;
    if (node_argument(arguments[0], self, &cross, &target) < 0 ||
        node_parts(arguments[1], self, &chain, &chain_generation) < 0)
        return NULL;
    if (check_status(GALLEY_CROSS(cross, tree_insert_before, target, chain_generation, chain)) < 0)
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
    NodeCrossing cross;
    GalleyNodeAddress target;
    GalleyNodeAddress chain;
    unsigned long long chain_generation;

    if (session_crossing(self, &cross) < 0)
        return NULL;
    if (expect_arguments("insert_after", count, 2) < 0)
        return NULL;
    if (node_argument(arguments[0], self, &cross, &target) < 0 ||
        node_parts(arguments[1], self, &chain, &chain_generation) < 0)
        return NULL;
    if (check_status(GALLEY_CROSS(cross, tree_insert_after, target, chain_generation, chain)) < 0)
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
    NodeCrossing cross;
    GalleyNodeAddress node;
    Py_ssize_t sibling_count;
    GalleyNodeAddress head;

    if (session_crossing(self, &cross) < 0)
        return NULL;
    if (expect_arguments("remove_siblings", count, 2) < 0)
        return NULL;
    if (node_argument(arguments[0], self, &cross, &node) < 0)
        return NULL;
    sibling_count = PyLong_AsSsize_t(arguments[1]);
    if (sibling_count < 0 && PyErr_Occurred())
        return NULL;
    if (check_status(GALLEY_CROSS(cross, tree_remove_siblings, node,
                                  (size_t)sibling_count, &head)) < 0)
        return NULL;
    if (head == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    return (PyObject *)make_node(self, cross.generation, head);
}

PyDoc_STRVAR(remove_self_doc,
"remove_self(node)\n"
"\n"
"Detaches node itself from its parent and siblings and returns the\n"
"detached head.");

static PyObject *Session_remove_self(PyObject *self, PyObject *node)
{
    NodeCrossing cross;
    GalleyNodeAddress address;
    GalleyNodeAddress head;

    if (session_crossing(self, &cross) < 0)
        return NULL;
    if (node_argument(node, self, &cross, &address) < 0)
        return NULL;
    if (check_status(GALLEY_CROSS(cross, tree_remove_self, address, &head)) < 0)
        return NULL;
    if (head == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    return (PyObject *)make_node(self, cross.generation, head);
}

PyDoc_STRVAR(clean_children_doc,
"clean_children(node)\n"
"\n"
"Detaches all children of node and returns the detached chain head (None\n"
"when there are none).");

static PyObject *Session_clean_children(PyObject *self, PyObject *node)
{
    NodeCrossing cross;
    GalleyNodeAddress address;
    GalleyNodeAddress head;

    if (session_crossing(self, &cross) < 0)
        return NULL;
    if (node_argument(node, self, &cross, &address) < 0)
        return NULL;
    if (check_status(GALLEY_CROSS(cross, tree_clean_children, address, &head)) < 0)
        return NULL;
    if (head == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    return (PyObject *)make_node(self, cross.generation, head);
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
    NodeCrossing cross;
    GalleyNodeAddress parent;
    GalleyNodeAddress chain;
    unsigned long long chain_generation;
    Py_ssize_t index;

    if (session_crossing(self, &cross) < 0)
        return NULL;
    if (expect_arguments("insert_children_at", count, 3) < 0)
        return NULL;
    if (node_argument(arguments[0], self, &cross, &parent) < 0)
        return NULL;
    index = PyLong_AsSsize_t(arguments[1]);
    if (index < 0 && PyErr_Occurred())
        return NULL;
    if (node_parts(arguments[2], self, &chain, &chain_generation) < 0)
        return NULL;
    if (check_status(GALLEY_CROSS(cross, tree_insert_children_at, parent,
                                  (size_t)index, chain_generation, chain)) < 0)
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
    NodeCrossing cross;
    GalleyNodeAddress parent;
    GalleyNodeAddress head;
    Py_ssize_t index;
    Py_ssize_t child_count;

    if (session_crossing(self, &cross) < 0)
        return NULL;
    if (expect_arguments("remove_children_at", count, 3) < 0)
        return NULL;
    if (node_argument(arguments[0], self, &cross, &parent) < 0)
        return NULL;
    index = PyLong_AsSsize_t(arguments[1]);
    if (index < 0 && PyErr_Occurred())
        return NULL;
    child_count = PyLong_AsSsize_t(arguments[2]);
    if (child_count < 0 && PyErr_Occurred())
        return NULL;
    if (check_status(GALLEY_CROSS(cross, tree_remove_children_at, parent,
                                  (size_t)index, (size_t)child_count,
                                  &head)) < 0)
        return NULL;
    if (head == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    return (PyObject *)make_node(self, cross.generation, head);
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

/* ------------------------------------------------------------------ */
/* Procedure hooks: one table implementation, two owners               */
/* ------------------------------------------------------------------ */

/* The module owns the default table (`py_procedure_table`); every Session
 * owns its own copy. Both are plain name -> callable dicts and every
 * change to either goes through the three helpers below, so naming,
 * validation and warnings have one implementation. A session applies a
 * change to a copy and commits it, which tells the library first. */

/* Registers one callable under `name`. -1 with an exception set when the
 * callable is not callable. */
static int hooks_install_one(PyObject *table, const char *name,
                             Py_ssize_t name_len, PyObject *callable)
{
    if (!PyCallable_Check(callable)) {
        PyErr_SetString(PyExc_TypeError, "callable must be callable");
        return -1;
    }
    PyObject *key = PyUnicode_FromStringAndSize(name, name_len);
    if (key == NULL)
        return -1;
    int status = PyDict_SetItem(table, key, callable);
    Py_DECREF(key);
    return status;
}

/* True for export names that look like mistyped hooks
 * (`reductionPair`, `hookPrint`): warn, do not install. Anything else
 * (helpers, data) stays silent. */
static int is_near_miss_hook_name(const char *name)
{
    char lower[7];
    size_t i;
    for (i = 0; i < 6 && name[i] != '\0'; i++) {
        char c = name[i];
        lower[i] = (char)((c >= 'A' && c <= 'Z') ? (c + 32) : c);
    }
    lower[i] = '\0';
    return strncmp(lower, "reduct", 6) == 0 || strncmp(lower, "hook", 4) == 0;
}

/* Registers every hook-named callable of a module, dict, or object with a
 * __dict__ and counts them in `*installed`. -1 with an exception set. */
static int hooks_install_many(PyObject *table, PyObject *source,
                              Py_ssize_t *installed)
{
    PyObject *dict = NULL;

    *installed = 0;
    if (PyDict_Check(source)) {
        dict = Py_NewRef(source);
    } else if (PyModule_Check(source)) {
        dict = PyModule_GetDict(source);
        if (dict == NULL)
            return -1;
        Py_INCREF(dict);
    } else {
        PyObject *d = PyObject_GetAttrString(source, "__dict__");
        if (d != NULL && PyDict_Check(d)) {
            dict = d;
        } else {
            Py_XDECREF(d);
            PyErr_SetString(PyExc_TypeError, "install_procedures expects a module, dict, or object with __dict__");
            return -1;
        }
    }

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
        if (!is_procedure) {
            if (is_near_miss_hook_name(name)) {
                char message[256];
                snprintf(message, sizeof(message),
                         "galley: ignoring export \"%.200s\": procedure hooks must be named "
                         "reduction, reduction_*, or hook_*.",
                         name);
                if (PyErr_WarnEx(PyExc_RuntimeWarning, message, 1) < 0) {
                    Py_DECREF(dict);
                    return -1;
                }
            }
            continue;
        }
        if (PyDict_SetItem(table, key, value) < 0) {
            PyErr_Clear();
            continue;
        }
        (*installed)++;
    }
    Py_DECREF(dict);
    return 0;
}

/* The callable registered under a str or bytes name, as a new reference, or
 * None. NULL with an exception set for a bad name. `table` may be NULL. */
static PyObject *hooks_lookup(PyObject *table, PyObject *name_obj)
{
    const char *name_data;
    Py_ssize_t name_len;

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
    if (table == NULL)
        Py_RETURN_NONE;
    PyObject *key = PyUnicode_FromStringAndSize(name_data, name_len);
    if (key == NULL)
        return NULL;
    PyObject *callable = PyDict_GetItemWithError(table, key);
    Py_DECREF(key);
    if (callable == NULL) {
        if (PyErr_Occurred())
            return NULL;
        Py_RETURN_NONE;
    }
    return Py_NewRef(callable);
}

/* Fills hook_indexes and hook_count from the library's hook list. */
static int init_hook_indexes(void)
{
    hook_count = galley_hooks_count();
    hook_indexes = PyDict_New();
    if (hook_indexes == NULL)
        return -1;
    for (size_t index = 0; index < hook_count; index++) {
        PyObject *key = PyUnicode_FromStringAndSize(
            galley_hooks_name_data(index),
            (Py_ssize_t)galley_hooks_name_length(index));
        PyObject *value = PyLong_FromSize_t(index);
        int status = (key == NULL || value == NULL)
                         ? -1
                         : PyDict_SetItem(hook_indexes, key, value);
        Py_XDECREF(key);
        Py_XDECREF(value);
        if (status < 0)
            return -1;
    }
    return 0;
}

/* Single gate for every session hook change: hands the library the enabled
 * set first, so a refusal (a parse in flight raises ERROR_SESSION_IN_USE)
 * leaves the session's hooks and the library exactly as they were, then
 * publishes `table` (a new reference is taken) and its by-index view. -1
 * with an exception set. */
static int commit_hooks(SessionObject *self, GalleySession *session, PyObject *table)
{
    PyObject *by_index = PyList_New((Py_ssize_t)hook_count);
    unsigned char *enabled = PyMem_Calloc(hook_count > 0 ? hook_count : 1, 1);
    PyObject *key, *value;
    Py_ssize_t pos = 0;
    long long status;

    if (by_index == NULL || enabled == NULL) {
        Py_XDECREF(by_index);
        PyMem_Free(enabled);
        if (!PyErr_Occurred())
            PyErr_NoMemory();
        return -1;
    }
    for (size_t index = 0; index < hook_count; index++)
        PyList_SET_ITEM(by_index, (Py_ssize_t)index, Py_NewRef(Py_None));
    while (PyDict_Next(table, &pos, &key, &value)) {
        PyObject *index_obj = PyDict_GetItemWithError(hook_indexes, key);
        if (index_obj == NULL) {
            if (PyErr_Occurred())
                goto fail;
            continue; /* The grammar has no such hook: stays listed, never fires. */
        }
        Py_ssize_t index = PyLong_AsSsize_t(index_obj);
        if (PyList_SetItem(by_index, index, Py_NewRef(value)) < 0)
            goto fail;
        enabled[index] = 1;
    }
    status = galley_session_set_hooks(session, py_dispatch_impl, self, enabled, hook_count);
    if (status < 0) {
        set_error_from_status(status);
        goto fail;
    }
    PyMem_Free(enabled);
    Py_XSETREF(self->hooks_by_index, by_index);
    Py_XSETREF(self->hooks, Py_NewRef(table));
    return 0;

fail:
    Py_DECREF(by_index);
    PyMem_Free(enabled);
    return -1;
}

/* A session's hooks as a fresh dict to edit and commit. */
static PyObject *copy_session_hooks(SessionObject *self)
{
    return self->hooks != NULL ? PyDict_Copy(self->hooks) : PyDict_New();
}

PyDoc_STRVAR(install_procedure_doc,
"install_procedure(name, callable)\n"
"\n"
"Registers a default Python procedure hook. name is the hook name (for\n"
"example \"reduction_Pair\" or \"hook_print\") and callable is a Python\n"
"callable that will be invoked with a ProcedureArguments object (or with\n"
"no args for compatibility). Each Session starts with a copy of the\n"
"defaults, so an install here reaches sessions opened after it, never\n"
"sessions already open: use Session.install_procedure for those.\n"
"Reinstalling replaces the previous callable.");

static PyObject *module_install_procedure(PyObject *Py_UNUSED(module),
                                          PyObject *args)
{
    const char *name;
    Py_ssize_t name_len;
    PyObject *callable;

    if (!PyArg_ParseTuple(args, "s#O:install_procedure", &name, &name_len, &callable))
        return NULL;
    if (py_procedure_table == NULL) {
        py_procedure_table = PyDict_New();
        if (py_procedure_table == NULL)
            return NULL;
    }
    if (hooks_install_one(py_procedure_table, name, name_len, callable) < 0)
        return NULL;
    Py_RETURN_NONE;
}

PyDoc_STRVAR(install_procedures_doc,
"install_procedures(module_or_dict)\n"
"\n"
"Registers all default procedure hooks found in a module, dict, or object\n"
"exposing a __dict__. Hooks are `reduction`, `reduction_<Variable>`, and\n"
"`hook_<name>` callables. Returns the number of hooks installed. Reaches\n"
"sessions opened after the call, like install_procedure.");

static PyObject *module_install_procedures(PyObject *Py_UNUSED(module),
                                           PyObject *source)
{
    Py_ssize_t installed;

    if (py_procedure_table == NULL) {
        py_procedure_table = PyDict_New();
        if (py_procedure_table == NULL)
            return NULL;
    }
    if (hooks_install_many(py_procedure_table, source, &installed) < 0)
        return NULL;
    return PyLong_FromSsize_t(installed);
}

PyDoc_STRVAR(clear_procedures_doc,
"clear_procedures()\n"
"\n"
"Clears the default procedure hooks. Sessions already open keep theirs.");

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
"Returns a dict of the default procedure hooks (name -> callable).");

static PyObject *module_list_procedures(PyObject *Py_UNUSED(module),
                                        PyObject *Py_UNUSED(ignored))
{
    if (py_procedure_table == NULL)
        return PyDict_New();
    return PyDict_Copy(py_procedure_table);
}

PyDoc_STRVAR(procedure_hook_doc,
"procedure_hook(name)\n"
"\n"
"Returns the default callable registered for hook name, or None when no\n"
"hook is installed under that name.");

static PyObject *module_procedure_hook(PyObject *Py_UNUSED(module),
                                       PyObject *name_obj)
{
    return hooks_lookup(py_procedure_table, name_obj);
}

/* The same five operations on a session's own hooks. */

PyDoc_STRVAR(session_install_procedure_doc,
"install_procedure(name, callable)\n"
"\n"
"Registers a procedure hook on this session only. It takes effect from the\n"
"next parse. Raises GalleyError (ERROR_SESSION_IN_USE) when a parse is in\n"
"flight, from a hook or from another thread, and leaves the hooks as they\n"
"were.");

static PyObject *Session_install_procedure(PyObject *self, PyObject *args)
{
    GalleySession *session = require_session(self);
    const char *name;
    Py_ssize_t name_len;
    PyObject *callable;

    if (session == NULL)
        return NULL;
    if (!PyArg_ParseTuple(args, "s#O:install_procedure", &name, &name_len, &callable))
        return NULL;
    PyObject *next = copy_session_hooks((SessionObject *)self);
    if (next == NULL)
        return NULL;
    if (hooks_install_one(next, name, name_len, callable) < 0 ||
        commit_hooks((SessionObject *)self, session, next) < 0) {
        Py_DECREF(next);
        return NULL;
    }
    Py_DECREF(next);
    Py_RETURN_NONE;
}

PyDoc_STRVAR(session_install_procedures_doc,
"install_procedures(module_or_dict)\n"
"\n"
"Registers all procedure hooks found in a module, dict, or object exposing\n"
"a __dict__ on this session only, in one step. Returns the number of hooks\n"
"installed. Refused like install_procedure while a parse is in flight.");

static PyObject *Session_install_procedures(PyObject *self, PyObject *source)
{
    GalleySession *session = require_session(self);
    Py_ssize_t installed;

    if (session == NULL)
        return NULL;
    PyObject *next = copy_session_hooks((SessionObject *)self);
    if (next == NULL)
        return NULL;
    if (hooks_install_many(next, source, &installed) < 0 ||
        (installed > 0 && commit_hooks((SessionObject *)self, session, next) < 0)) {
        Py_DECREF(next);
        return NULL;
    }
    Py_DECREF(next);
    return PyLong_FromSsize_t(installed);
}

PyDoc_STRVAR(session_clear_procedures_doc,
"clear_procedures()\n"
"\n"
"Clears this session's procedure hooks. Refused like install_procedure\n"
"while a parse is in flight.");

static PyObject *Session_clear_procedures(PyObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleySession *session = require_session(self);

    if (session == NULL)
        return NULL;
    PyObject *next = PyDict_New();
    if (next == NULL)
        return NULL;
    if (commit_hooks((SessionObject *)self, session, next) < 0) {
        Py_DECREF(next);
        return NULL;
    }
    Py_DECREF(next);
    Py_RETURN_NONE;
}

PyDoc_STRVAR(session_list_procedures_doc,
"list_procedures()\n"
"\n"
"Returns a dict of this session's procedure hooks (name -> callable).");

static PyObject *Session_list_procedures(PyObject *self, PyObject *Py_UNUSED(ignored))
{
    if (require_session(self) == NULL)
        return NULL;
    return copy_session_hooks((SessionObject *)self);
}

PyDoc_STRVAR(session_procedure_hook_doc,
"procedure_hook(name)\n"
"\n"
"Returns the callable registered on this session for hook name, or None.");

static PyObject *Session_procedure_hook(PyObject *self, PyObject *name_obj)
{
    if (require_session(self) == NULL)
        return NULL;
    return hooks_lookup(((SessionObject *)self)->hooks, name_obj);
}

static PyMethodDef Session_methods[] = {
    {"close", (PyCFunction)(void (*)(void))Session_close, METH_NOARGS, NULL},
    {"is_closed", (PyCFunction)(void (*)(void))Session_is_closed, METH_NOARGS,
     "is_closed()\n\nReturns whether the session is closed."},
    {"__enter__", (PyCFunction)(void (*)(void))Session_enter, METH_NOARGS,
     NULL},
    {"__exit__", (PyCFunction)(void (*)(void))Session_exit, METH_FASTCALL,
     NULL},
    {"parse", (PyCFunction)(void (*)(void))Session_parse, METH_O, parse_doc},
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
    {"snapshot", (PyCFunction)(void (*)(void))Session_snapshot, METH_NOARGS,
     snapshot_doc},
    {"last_input", (PyCFunction)(void (*)(void))Session_last_input,
     METH_NOARGS, last_input_doc},
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
    {"clean_children", (PyCFunction)(void (*)(void))Session_clean_children,
     METH_O, clean_children_doc},
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
    {"install_procedure", (PyCFunction)Session_install_procedure,
     METH_VARARGS, session_install_procedure_doc},
    {"install_procedures", (PyCFunction)Session_install_procedures, METH_O,
     session_install_procedures_doc},
    {"clear_procedures", (PyCFunction)Session_clear_procedures, METH_NOARGS,
     session_clear_procedures_doc},
    {"list_procedures", (PyCFunction)Session_list_procedures, METH_NOARGS,
     session_list_procedures_doc},
    {"procedure_hook", (PyCFunction)Session_procedure_hook, METH_O,
     session_procedure_hook_doc},
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
"A session owns its procedure hooks, a copy of the module's defaults taken\n"
"when it opens (install_procedure and friends change only this session).\n"
"Usable as a context manager; close() releases the underlying session and\n"
"is safe to call more than once.");

static PyTypeObject Session_Type = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = GALLEY_MODULE_STRING ".Session",
    .tp_basicsize = sizeof(SessionObject),
    .tp_itemsize = 0,
    .tp_dealloc = (destructor)Session_dealloc,
    .tp_flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_HAVE_GC,
    .tp_traverse = (traverseproc)Session_traverse,
    .tp_clear = (inquiry)Session_clear,
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
    NodeCrossing cross;
    long long count;
    if (node_crossing(self, &cross) < 0)
        return -1;
    count = CROSS_VALUE(cross, node_child_count, self->address);
    return count < 0 ? -1 : (Py_ssize_t)count;
}

static PyObject *Node_item(NodeObject *self, Py_ssize_t index)
{
    NodeCrossing cross;
    long long count;
    long long link;
    if (node_crossing(self, &cross) < 0)
        return NULL;
    count = CROSS_VALUE(cross, node_child_count, self->address);
    if (count < 0)
        return NULL;
    if (index < 0)
        index += (Py_ssize_t)count;
    if (index < 0 || index >= (Py_ssize_t)count) {
        PyErr_SetString(PyExc_IndexError, "child index out of range");
        return NULL;
    }
    link = CROSS_VALUE(cross, node_first_child, self->address);
    for (Py_ssize_t i = 0; link >= 0 && i < index; ++i)
        link = CROSS_VALUE(cross, node_next_sibling, (GalleyNodeAddress)link);
    if (link >= 0 && (GalleyNodeAddress)link == GALLEY_INVALID_NODE) {
        PyErr_SetString(PyExc_RuntimeError, "child not found");
        return NULL;
    }
    return link_object(self->session_obj, cross.generation, link);
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

static PyObject *Node_children(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    NodeCrossing cross;
    if (node_crossing(self, &cross) < 0)
        return NULL;
    return children_via(self->session_obj, cross, self->address);
}

static PyObject *Node_iter(NodeObject *self)
{
    PyObject *tuple = Node_children(self, NULL);
    if (tuple == NULL)
        return NULL;
    PyObject *iter = PyObject_GetIter(tuple);
    Py_DECREF(tuple);
    return iter;
}

static PyObject *Node_text(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    return node_value(self, text_value);
}

static PyObject *Node_symbol_name(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    return node_value(self, symbol_name_value);
}

static PyObject *Node_span(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    return node_value(self, span_value);
}

static PyObject *Node_line_column(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    return node_value(self, line_column_value);
}

static PyObject *Node_parent(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    return node_value(self, parent_value);
}

static PyObject *Node_next_sibling(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    return node_value(self, next_sibling_value);
}

static PyObject *Node_prior_sibling(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    return node_value(self, prior_sibling_value);
}

static PyObject *Node_first_child(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    return node_value(self, first_child_value);
}

static PyObject *Node_last_child(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    return node_value(self, last_child_value);
}

static PyObject *Node_clean_children(NodeObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleyNodeAddress head;
    NodeCrossing cross;
    long long status;
    if (node_crossing(self, &cross) < 0)
        return NULL;
    status = GALLEY_CROSS(cross, tree_clean_children, self->address, &head);
    if (check_status(status) < 0)
        return NULL;
    if (head == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    return (PyObject *)make_node(self->session_obj, cross.generation, head);
}

static PyObject *Node_append_children(NodeObject *self, PyObject *chain)
{
    GalleyNodeAddress chain_address;
    unsigned long long chain_generation;
    NodeCrossing cross;
    long long status;
    if (node_crossing(self, &cross) < 0)
        return NULL;
    if (node_parts(chain, self->session_obj, &chain_address, &chain_generation) < 0)
        return NULL;
    status = GALLEY_CROSS(cross, tree_append_children, self->address, chain_generation, chain_address);
    if (check_status(status) < 0)
        return NULL;
    Py_RETURN_NONE;
}

PyDoc_STRVAR(node_walk_doc,
"walk(skip_semantic_errors=False, skip_recovered=False)\n"
"\n"
"Returns a pre-order Walker over the subtree rooted at this node, the\n"
"node itself at depth 0. Each iteration yields a WalkStep with ``node``,\n"
"``depth`` (relative to this node), ``is_semantic_error`` and\n"
"``is_recovered``. Pass a true ``skip_semantic_errors`` to prune subtrees\n"
"rooted at semantic-error nodes, and a true ``skip_recovered`` to prune\n"
"those rooted at nodes syntax-error recovery kept in place of damaged\n"
"input; with both the walk yields only undamaged, valid nodes.\n"
"\n"
"The walker owns no native resource: abandoning it is free, and parsing\n"
"again while one exists succeeds -- its next step raises StaleTreeError.\n"
"Each step picks its door like any node call: inside a hook of the\n"
"running parse it walks that parse's in-flight tree, otherwise the\n"
"published one. Steps follow the live links, so edits between steps are\n"
"visible; a step whose position is no longer inside the walk's root\n"
"(removed, or moved elsewhere) raises GalleyError (invalid node), and\n"
"stepping while a parse holds the session raises GalleyError with\n"
"ERROR_SESSION_IN_USE.");

static PyObject *Node_walk(NodeObject *self, PyObject *args, PyObject *keywords)
{
    int skip = 0;
    int skip_recovered = 0;
    WalkerObject *walker_obj;
    NodeCrossing cross;
    static char *names[] = {"skip_semantic_errors", "skip_recovered", NULL};

    if (!PyArg_ParseTupleAndKeywords(args, keywords, "|$pp:walk", names, &skip,
                                     &skip_recovered))
        return NULL;
    /* Door choice and generation check like every other node call, so a
     * walk created inside a hook belongs to that parse and steps through
     * its door. */
    if (node_crossing(self, &cross) < 0)
        return NULL;
    walker_obj = PyObject_New(WalkerObject, &Walker_Type);
    if (walker_obj == NULL)
        return NULL;
    walker_obj->session_obj = Py_NewRef(self->session_obj);
    /* The walk is bound to the tree this node came from: stamp the cursor
     * from the node's own generation. Nothing asks the core here; a stale
     * generation is refused at the first step. */
    walker_obj->cursor = (GalleyWalkCursor){
        .generation = self->generation,
        .root = self->address,
        .current = 0,
        .depth = 0,
        .state = GALLEY_WALK_STATE_NOT_STARTED,
        .options = (unsigned char)((skip ? GALLEY_WALK_SKIP_SEMANTIC_ERRORS : 0) |
                                   (skip_recovered ? GALLEY_WALK_SKIP_RECOVERED : 0)),
        .flags = 0,
    };
    return (PyObject *)walker_obj;
}

PyDoc_STRVAR(node_children_doc, "children()\n\nReturns a tuple of the direct children of this node.");
PyDoc_STRVAR(node_text_doc, "text()\n\nReturns the text of this node as bytes. A refused node raises.");
PyDoc_STRVAR(node_symbol_name_doc, "symbol_name()\n\nReturns the symbol name of this node as bytes. A refused node raises.");
PyDoc_STRVAR(node_span_doc, "span()\n\nReturns (start, length) of this node. A refused node raises.");
PyDoc_STRVAR(node_line_column_doc, "line_column()\n\nReturns (line, column) of this node. A refused node raises.");
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
    {"walk", (PyCFunction)(void (*)(void))Node_walk,
     METH_VARARGS | METH_KEYWORDS, node_walk_doc},
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
    // Identity is session, core parse generation and address. The door a
    // node was reached through is not part of it, so a hook node equals the
    // session's node for the same address once its parse published; and a
    // node of an earlier parse never equals the node of a later parse that
    // reuses its address.
    int equal = (na->address == nb->address) &&
                (na->generation == nb->generation) &&
                (na->session_obj == nb->session_obj);
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
    // Consistent with equality: the generation and address, mixed so the
    // nodes of one address across parses do not collide.
    Py_hash_t h = (Py_hash_t)(self->address ^ (self->generation * 0x9E3779B97F4A7C15ULL));
    if (h == -1)
        h = -2;
    return h;
}

static PyObject *Node_get_address(NodeObject *self, void *Py_UNUSED(closure))
{
    return PyLong_FromUnsignedLongLong(self->address);
}

static PyGetSetDef Node_getset[] = {
    {"address", (getter)Node_get_address, NULL,
     "Display-only raw address (stable index in the session's node "
     "storage); never an argument where a node is expected.", NULL},
    {NULL, NULL, NULL, NULL, NULL}
};

static PyTypeObject Node_Type = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = GALLEY_MODULE_STRING ".Node",
    .tp_basicsize = sizeof(NodeObject),
    .tp_itemsize = 0,
    .tp_dealloc = (destructor)Node_dealloc,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_doc = "Node handle with session-aware methods. Iterate directly: for child in node:",
    .tp_methods = Node_methods,
    .tp_getset = Node_getset,
    .tp_as_sequence = &Node_sequence_methods,
    .tp_as_mapping = &Node_mapping_methods,
    .tp_iter = (getiterfunc)Node_iter,
    .tp_richcompare = Node_richcompare,
    .tp_hash = (hashfunc)Node_hash,
    .tp_repr = (reprfunc)Node_repr,
    .tp_str = (reprfunc)Node_repr,
};

/* ------------------------------------------------------------------ */
/* WalkStep — one position of a walk                                    */
/* ------------------------------------------------------------------ */

static void WalkStep_dealloc(WalkStepObject *self)
{
    Py_XDECREF(self->node);
    Py_TYPE(self)->tp_free((PyObject *)self);
}

static PyObject *WalkStep_get_node(WalkStepObject *self, void *Py_UNUSED(closure))
{
    return Py_NewRef(self->node);
}

static PyObject *WalkStep_get_depth(WalkStepObject *self, void *Py_UNUSED(closure))
{
    return PyLong_FromUnsignedLong(self->depth);
}

static PyObject *WalkStep_get_is_semantic_error(WalkStepObject *self,
                                                void *Py_UNUSED(closure))
{
    return PyBool_FromLong(self->is_semantic_error);
}

static PyObject *WalkStep_get_is_recovered(WalkStepObject *self,
                                           void *Py_UNUSED(closure))
{
    return PyBool_FromLong(self->is_recovered);
}

static PyGetSetDef WalkStep_getset[] = {
    {"node", (getter)WalkStep_get_node, NULL,
     "The node this step visited.", NULL},
    {"depth", (getter)WalkStep_get_depth, NULL,
     "Depth below the walk's root node, which is at depth 0.", NULL},
    {"is_semantic_error", (getter)WalkStep_get_is_semantic_error, NULL,
     "True when the visited node is flagged as a semantic error.", NULL},
    {"is_recovered", (getter)WalkStep_get_is_recovered, NULL,
     "True when the visited node is one syntax-error recovery kept in place "
     "of damaged input; its span covers the input recovery skipped.", NULL},
    {NULL, NULL, NULL, NULL, NULL}
};

static PyTypeObject WalkStep_Type = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = GALLEY_MODULE_STRING ".WalkStep",
    .tp_basicsize = sizeof(WalkStepObject),
    .tp_itemsize = 0,
    .tp_dealloc = (destructor)WalkStep_dealloc,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_doc = "One position of a walk: read-only node, depth, "
              "is_semantic_error and is_recovered. Yielded by Walker, never "
              "constructed.",
    .tp_getset = WalkStep_getset,
};

/* ------------------------------------------------------------------ */
/* Walker — shared pre-order tree traversal                           */
/* ------------------------------------------------------------------ */

static void Walker_dealloc(WalkerObject *self)
{
    Py_XDECREF(self->session_obj);
    Py_TYPE(self)->tp_free((PyObject *)self);
}

static PyObject *Walker_iternext(WalkerObject *self)
{
    NodeCrossing cross;
    long long status;
    NodeObject *node_obj;
    WalkStepObject *step;

    /* Door per step, like every other node call: the hook door inside the
     * dispatching thread of the running parse, the session door otherwise.
     * The cursor already carries the walk's generation; the core compares it
     * against the tree the door serves. */
    if (session_crossing(self->session_obj, &cross) < 0)
        return NULL;
    status = GALLEY_CROSS_BARE(cross, walk_next, &self->cursor);
    if (status < 0) {
        set_error_from_status(status);
        return NULL;
    }
    if (status == 0)
        return NULL; /* walk done */
    node_obj = make_node(self->session_obj, self->cursor.generation,
                         self->cursor.current);
    if (node_obj == NULL)
        return NULL;
    step = PyObject_New(WalkStepObject, &WalkStep_Type);
    if (step == NULL) {
        Py_DECREF(node_obj);
        return NULL;
    }
    step->node = (PyObject *)node_obj;
    step->depth = self->cursor.depth;
    step->is_semantic_error =
        (self->cursor.flags & GALLEY_WALK_FLAG_SEMANTIC_ERROR) != 0;
    step->is_recovered = (self->cursor.flags & GALLEY_WALK_FLAG_RECOVERED) != 0;
    return (PyObject *)step;
}

PyDoc_STRVAR(walker_skip_children_doc,
"skip_children()\n"
"\n"
"Prunes the children of the last yielded node; the next iteration\n"
"continues with its next sibling. No effect without a last step.");

static PyObject *Walker_skip_children(WalkerObject *self, PyObject *Py_UNUSED(ignored))
{
    SessionObject *session_object = (SessionObject *)self->session_obj;
    if (session_object->session == NULL) {
        PyErr_SetString(PyExc_ValueError, "session is closed");
        return NULL;
    }
    /* A pure host-side state write: staleness is the next step's answer,
     * not this one's. */
    if (self->cursor.state == GALLEY_WALK_STATE_YIELDED)
        self->cursor.state = GALLEY_WALK_STATE_YIELDED_SKIP_CHILDREN;
    Py_RETURN_NONE;
}

static PyMethodDef Walker_methods[] = {
    {"skip_children", (PyCFunction)(void (*)(void))Walker_skip_children,
     METH_NOARGS, walker_skip_children_doc},
    {NULL, NULL, 0, NULL},
};

static PyTypeObject Walker_Type = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = GALLEY_MODULE_STRING ".Walker",
    .tp_basicsize = sizeof(WalkerObject),
    .tp_itemsize = 0,
    .tp_dealloc = (destructor)Walker_dealloc,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_doc = "Pre-order tree walker. Iterates WalkStep objects.",
    .tp_methods = Walker_methods,
    .tp_iter = PyObject_SelfIter,
    .tp_iternext = (iternextfunc)Walker_iternext,
};

/* ------------------------------------------------------------------ */
/* ProcedureArguments — per-hook state                                  */
/* ------------------------------------------------------------------ */

/* The single gate for per-hook state: the session handle every
 * galley_procedure_* call takes with this object's ticket. A closed session
 * raises instead of reading destroyed storage. Whether the hook is still
 * running is the core's to say: it refuses a ticket whose hook has returned
 * (galley_error_stale_hook), so this object keeps no expiry flag. */
static GalleySession *procedure_session(ProcedureArgsObject *self)
{
    return require_session(self->session_obj);
}

static void ProcedureArgs_dealloc(ProcedureArgsObject *self)
{
    Py_XDECREF(self->session_obj);
    Py_TYPE(self)->tp_free((PyObject *)self);
}

static PyObject *ProcedureArgs_current_node(ProcedureArgsObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleySession *session = procedure_session(self);
    if (session == NULL)
        return NULL;
    long long address = check_value(galley_procedure_current_node(session, self->hook));
    if (address < 0)
        return NULL;
    if ((GalleyNodeAddress)address == GALLEY_INVALID_NODE)
        Py_RETURN_NONE;
    /* The stamp of the nodes this parse hands out: read once from the core
     * on the parse's first dispatch, never compared against anything. */
    return (PyObject *)make_node(self->session_obj,
                                 ((SessionObject *)self->session_obj)->parse_generation,
                                 (GalleyNodeAddress)address);
}

/* The four tree helpers share one shape: the call through the core's gate,
 * then None. */
#define DEFINE_PROCEDURE_ACTION(function, name)                                  \
    static PyObject *function(ProcedureArgsObject *self, PyObject *Py_UNUSED(ignored)) \
    {                                                                            \
        GalleySession *session = procedure_session(self);                        \
        if (session == NULL)                                                     \
            return NULL;                                                         \
        if (check_status(galley_procedure_##name(session, self->hook)) < 0)      \
            return NULL;                                                         \
        Py_RETURN_NONE;                                                          \
    }

DEFINE_PROCEDURE_ACTION(ProcedureArgs_drop_self, drop_self)
DEFINE_PROCEDURE_ACTION(ProcedureArgs_drop_children, drop_children)
DEFINE_PROCEDURE_ACTION(ProcedureArgs_drop_if_empty, drop_if_empty)
DEFINE_PROCEDURE_ACTION(ProcedureArgs_replace_with_children, replace_with_children)

static PyObject *ProcedureArgs_current_line(ProcedureArgsObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleySession *session = procedure_session(self);
    if (session == NULL)
        return NULL;
    long long line = check_value(galley_procedure_context_line(session, self->hook));
    return line < 0 ? NULL : PyLong_FromLongLong(line);
}

static PyObject *ProcedureArgs_current_column(ProcedureArgsObject *self, PyObject *Py_UNUSED(ignored))
{
    GalleySession *session = procedure_session(self);
    if (session == NULL)
        return NULL;
    long long column = check_value(galley_procedure_context_column(session, self->hook));
    return column < 0 ? NULL : PyLong_FromLongLong(column);
}

static PyObject *ProcedureArgs_report_semantic_error(ProcedureArgsObject *self, PyObject *message_obj)
{
    const char *message_data;
    Py_ssize_t message_len;
    GalleySession *session = procedure_session(self);

    if (session == NULL)
        return NULL;
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
    long long count = galley_procedure_report_semantic_error(session, self->hook, message_data, (size_t)message_len);
    if (count < 0) {
        check_status(count);
        return NULL;
    }
    return PyLong_FromLongLong(count);
}

static PyObject *ProcedureArgs_set_current_node(ProcedureArgsObject *self, PyObject *node)
{
    GalleyNodeAddress address;
    unsigned long long generation;
    GalleySession *session = procedure_session(self);

    if (session == NULL)
        return NULL;
    if (node_parts(node, self->session_obj, &address, &generation) < 0)
        return NULL;
    if (check_status(galley_procedure_set_current_node(session, self->hook, generation, address)) < 0)
        return NULL;
    Py_RETURN_NONE;
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
    {"report_semantic_error", (PyCFunction)ProcedureArgs_report_semantic_error, METH_O,
     "report_semantic_error(message)\n\nRecord a semantic error on the current node and return the total count. Parsing continues."},
    {"set_current_node", (PyCFunction)ProcedureArgs_set_current_node, METH_O,
     "set_current_node(node)\n\nRedirect the current-node channel to node, a Node of this parse. Raises StaleTreeError for a node of another parse."},
    {NULL, NULL, 0, NULL}
};

static PyGetSetDef ProcedureArgs_getset[] = {
    {NULL, NULL, NULL, NULL, NULL}
};

static PyTypeObject ProcedureArgs_Type = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = GALLEY_MODULE_STRING ".ProcedureArguments",
    .tp_basicsize = sizeof(ProcedureArgsObject),
    .tp_itemsize = 0,
    .tp_dealloc = (destructor)ProcedureArgs_dealloc,
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_doc = "Per-hook procedure arguments, valid only while the hook runs. Tree "
              "queries use current_node() and the ordinary Node methods; those "
              "nodes stay usable for the rest of the parse and, when the parse "
              "succeeds, until the session parses again.",
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

static PyMethodDef module_methods[] = {
    {"version", module_version, METH_NOARGS, version_doc},
    {"parser_type", module_parser_type, METH_NOARGS,
     "parser_type()\n\nReturns the parser family: ParserType.LL or\n"
     "ParserType.LR."},
    {"error_recovery_mode", module_error_recovery_mode, METH_NOARGS,
     "error_recovery_mode()\n\nReturns the generated error-recovery mode:\n"
     "RecoveryMode.DISABLED, RecoveryMode.AUTOMATIC, or\n"
     "RecoveryMode.EXPLICIT."},
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
    {"procedure_hook", module_procedure_hook, METH_O, procedure_hook_doc},
    {NULL, NULL, 0, NULL}
};

PyDoc_STRVAR(module_doc,
"Bindings over a Galley-generated parser archive.\n"
"\n"
"One inner module embeds one parser: the generated package init imports\n"
"it relatively, so build the language directory with\n"
"python -m galley, then import the directory or bind it by path.\n"
"See Session for the parsing surface and the module constants for\n"
"classification enums.");

static struct PyModuleDef module_definition = {
    PyModuleDef_HEAD_INIT,
    .m_name = GALLEY_MODULE_STRING,
    .m_doc = module_doc,
    .m_size = -1,
    .m_methods = module_methods,
};

static int add_int_enum(PyObject *module, const char *class_name,
                        const char *const *members, const long long *values,
                        size_t count)
{
    PyObject *enum_module = PyImport_ImportModule("enum");
    PyObject *int_enum;
    PyObject *namespace;
    PyObject *cls;
    size_t i;

    if (enum_module == NULL)
        return -1;
    int_enum = PyObject_GetAttrString(enum_module, "IntEnum");
    Py_DECREF(enum_module);
    if (int_enum == NULL)
        return -1;
    namespace = PyDict_New();
    if (namespace == NULL) {
        Py_DECREF(int_enum);
        return -1;
    }
    for (i = 0; i < count; i++) {
        PyObject *value = PyLong_FromLongLong(values[i]);
        int stored = -1;
        if (value != NULL)
            stored = PyDict_SetItemString(namespace, members[i], value);
        Py_XDECREF(value);
        if (stored < 0) {
            Py_DECREF(namespace);
            Py_DECREF(int_enum);
            return -1;
        }
    }
    cls = PyObject_CallFunction(int_enum, "sO", class_name, namespace);
    Py_DECREF(namespace);
    Py_DECREF(int_enum);
    if (cls == NULL)
        return -1;
    if (PyModule_AddObject(module, class_name, cls) < 0) {
        Py_DECREF(cls);
        return -1;
    }
    return 0;
}

/* Registers one IntEnum from `<prefix>_members` and `<prefix>_values`. The
 * count is derived from the values array, so a member can no longer be left
 * out of the class by a stale hand-written count; ENUM_ARRAYS_MATCH refuses a
 * build where the two arrays differ in length. */
#define ARRAY_LENGTH(array) (sizeof(array) / sizeof((array)[0]))
#define ENUM_ARRAYS_MATCH(prefix)                                                  \
    _Static_assert(ARRAY_LENGTH(prefix##_members) == ARRAY_LENGTH(prefix##_values), \
                   #prefix " members and values differ in length")
#define ADD_INT_ENUM(module, class_name, prefix)                                   \
    add_int_enum(module, class_name, prefix##_members, prefix##_values,            \
                 ARRAY_LENGTH(prefix##_values))

static int add_binding_enums(PyObject *module)
{
    static const char *const parser_type_members[] = {"LL", "LR"};
    static const long long parser_type_values[] = {
        galley_parser_type_ll, galley_parser_type_lr};
    static const char *const recovery_mode_members[] = {
        "DISABLED", "AUTOMATIC", "EXPLICIT"};
    static const long long recovery_mode_values[] = {
        galley_recovery_mode_disabled, galley_recovery_mode_automatic,
        galley_recovery_mode_explicit};
    static const char *const kind_members[] = {
        "NONE", "SYNTAX", "INDENTATION", "SEMANTIC"};
    static const long long kind_values[] = {
        galley_diagnostic_kind_none, galley_diagnostic_kind_syntax,
        galley_diagnostic_kind_indentation, galley_diagnostic_kind_semantic};
    static const char *const recovery_target_members[] = {
        "NONE", "LHS_VARIABLE", "PRODUCTION", "OCCURRENCE"};
    static const long long recovery_target_values[] = {
        galley_recovery_target_none, galley_recovery_target_lhs_variable,
        galley_recovery_target_production, galley_recovery_target_occurrence};
    static const char *const resume_members[] = {"BEFORE", "AFTER"};
    static const long long resume_values[] = {
        galley_resume_before, galley_resume_after};
    static const char *const status_members[] = {
        "OK",
        "ERROR_NULL_ARGUMENT",
        "ERROR_SYNTAX",
        "ERROR_INDENTATION",
        "ERROR_STACK_OVERFLOW",
        "ERROR_AST_CAPACITY_EXCEEDED",
        "ERROR_UNTERMINATED_RAW_STRING",
        "ERROR_OUT_OF_MEMORY",
        "ERROR_INTERNAL",
        "ERROR_NO_DIAGNOSTIC",
        "ERROR_INVALID_NODE",
        "ERROR_IO",
        "ERROR_SEMANTIC",
        "ERROR_SESSION_IN_USE",
        "ERROR_STALE_TREE",
        "ERROR_STALE_HOOK"};
    static const long long status_values[] = {
        galley_ok,
        galley_error_null_argument,
        galley_error_syntax,
        galley_error_indentation,
        galley_error_stack_overflow,
        galley_error_ast_capacity_exceeded,
        galley_error_unterminated_raw_string,
        galley_error_out_of_memory,
        galley_error_internal,
        galley_error_no_diagnostic,
        galley_error_invalid_node,
        galley_error_io,
        galley_error_semantic,
        galley_error_session_in_use,
        galley_error_stale_tree,
        galley_error_stale_hook};

    ENUM_ARRAYS_MATCH(parser_type);
    ENUM_ARRAYS_MATCH(recovery_mode);
    ENUM_ARRAYS_MATCH(kind);
    ENUM_ARRAYS_MATCH(recovery_target);
    ENUM_ARRAYS_MATCH(resume);
    ENUM_ARRAYS_MATCH(status);

    if (ADD_INT_ENUM(module, "ParserType", parser_type) < 0 ||
        ADD_INT_ENUM(module, "RecoveryMode", recovery_mode) < 0 ||
        ADD_INT_ENUM(module, "Kind", kind) < 0 ||
        ADD_INT_ENUM(module, "RecoveryTarget", recovery_target) < 0 ||
        ADD_INT_ENUM(module, "Resume", resume) < 0 ||
        ADD_INT_ENUM(module, "Status", status) < 0)
        return -1;
    return 0;
}

PyMODINIT_FUNC GALLEY_INIT_FUNCTION(void)
{
    PyObject *module;

    if (PyType_Ready(&Session_Type) < 0)
        return NULL;
    if (PyType_Ready(&Node_Type) < 0)
        return NULL;
    if (PyType_Ready(&ProcedureArgs_Type) < 0)
        return NULL;
    if (PyType_Ready(&WalkStep_Type) < 0)
        return NULL;
    if (PyType_Ready(&Walker_Type) < 0)
        return NULL;
    if (PyType_Ready(&Snapshot_Type) < 0)
        return NULL;
    if (PyType_Ready(&Diagnostic_Type) < 0)
        return NULL;

    module = PyModule_Create(&module_definition);
    if (module == NULL)
        return NULL;

    ErrorException = PyErr_NewExceptionWithDoc(
        GALLEY_MODULE_STRING ".GalleyError",
        "Failure reported by a Galley operation. The raw status code is\n"
        "available as the `code` attribute.",
        NULL, NULL);
    if (ErrorException == NULL)
        goto fail;
    Py_INCREF(ErrorException);
    if (PyModule_AddObject(module, "GalleyError", ErrorException) < 0) {
        Py_DECREF(ErrorException);
        goto fail;
    }

    /* The one stale-tree error: a node, walk, or tree read addressed a
     * generation the core does not hold live. A subclass of GalleyError, so
     * existing `except GalleyError` sites keep working. */
    StaleTreeException = PyErr_NewExceptionWithDoc(
        GALLEY_MODULE_STRING ".StaleTreeError",
        "The tree this handle belongs to is gone: the session parsed\n"
        "again since, the last parse published nothing, or nothing was\n"
        "ever published. Read root_node() and use the nodes it returns.",
        ErrorException, NULL);
    if (StaleTreeException == NULL)
        goto fail;
    Py_INCREF(StaleTreeException);
    if (PyModule_AddObject(module, "StaleTreeError", StaleTreeException) < 0) {
        Py_DECREF(StaleTreeException);
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
    Py_INCREF(&WalkStep_Type);
    if (PyModule_AddObject(module, "WalkStep", (PyObject *)&WalkStep_Type) < 0) {
        Py_DECREF(&WalkStep_Type);
        goto fail;
    }
    Py_INCREF(&Walker_Type);
    if (PyModule_AddObject(module, "Walker", (PyObject *)&Walker_Type) < 0) {
        Py_DECREF(&Walker_Type);
        goto fail;
    }
    Py_INCREF(&Snapshot_Type);
    if (PyModule_AddObject(module, "Snapshot", (PyObject *)&Snapshot_Type) < 0) {
        Py_DECREF(&Snapshot_Type);
        goto fail;
    }

    if (add_binding_enums(module) < 0)
        goto fail;

    PyObject *invalid_node = PyLong_FromUnsignedLongLong(GALLEY_INVALID_NODE);
    if (invalid_node == NULL ||
        PyModule_AddObject(module, "INVALID_NODE", invalid_node) < 0) {
        Py_XDECREF(invalid_node);
        goto fail;
    }

    /* Python procedure hooks: learn the library's hook list. Hook
     * callables arrive through generated package init or explicit
     * registration, which own procedures.py scanning. */
    if (init_hook_indexes() < 0)
        goto fail;

    return module;

fail:
    Py_DECREF(module);
    return NULL;
}
