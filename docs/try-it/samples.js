// Default editor inputs for the try-it page: one ~1 KB sample per
// language, each verified to parse under its try-it grammar.

export const lispSample = `; A tiny interpreter: environments, arithmetic, and closures.
(define (lookup name env)
  (cond
    ((null? env) #f)
    ((eq? name (caar env)) (cdar env))
    (else (lookup name (cdr env)))))

(define (extend names values env)
  (if (null? names)
      env
      (extend (cdr names)
              (cdr values)
              (cons (cons (car names) (car values)) env))))

(define (eval-expr expr env)
  (cond
    ((number? expr) expr)
    ((symbol? expr) (lookup expr env))
    ((eq? (car expr) 'quote) (cadr expr))
    ((eq? (car expr) 'if)
     (eval-expr (if (eval-expr (cadr expr) env)
                    (caddr expr)
                    (cadddr expr))
                env))
    ((eq? (car expr) 'lambda)
     (cons 'closure (cons (cadr expr) (cons (caddr expr) env))))
    (else
     (apply-proc (eval-expr (car expr) env)
                 (map (lambda (a) (eval-expr a env))
                      (cdr expr))))))

(define (apply-proc proc args)
  (cond
    ((eq? (car proc) 'closure)
     (eval-expr (caddr proc)
                (extend (cadr proc) args (cdddr proc))))
    ((eq? (car proc) 'builtin)
     ((cadr proc) args))
    (else (error "not a procedure: " proc))))

(define (map f xs)
  (if (null? xs)
      '()
      (cons (f (car xs)) (map f (cdr xs)))))

(define (square x) (* x x))
(define (sum-of-squares a b)
  (+ (square a) (square b)))
(display (sum-of-squares 3 4))
`;

export const jsonSample = `{
  "name": "galley-try-it",
  "version": "0.3.1",
  "private": true,
  "description": "Interactive examples for every language binding Galley ships.",
  "keywords": ["parser", "generator", "grammar", "wasm", "incremental"],
  "engines": { "node": ">=20.0.0", "deno": ">=1.40.0", "bun": ">=1.0.0" },
  "scripts": {
    "build": "zig build -Doptimize=ReleaseFast",
    "test": "zig build test -Dtest-filter=case:ll-json",
    "bench": "zig build bench --summary all"
  },
  "bindings": {
    "c": { "header": "galley.h", "abi": "stable" },
    "python": { "module": "_galley", "wheel": true },
    "rust": { "crate": "galley", "edition": "2021" },
    "go": { "module": "example.com/galley", "package": "galley" }
  },
  "authors": [
    { "name": "Ada", "role": "maintainer", "email": "ada@example.com" },
    { "name": "Grace", "role": "reviewer", "email": "grace@example.com" }
  ],
  "limits": { "maxDepth": 64, "maxNodes": 1000000, "timeoutMs": 5000 },
  "features": [true, false, true, true, false],
  "retries": null,
  "i18n": {
    "zh": "你好，世界",
    "ar": "مرحبا بالعالم",
    "he": "שלום עולם",
    "ja": "こんにちは世界",
    "ko": "안녕하세요 세계",
    "th": "สวัสดีชาวโลก",
    "hi": "नमस्ते दुनिया"
  },
  "greeting": "café ✓ → مرحبا 世界 😀",
  "nul": "\\u0000"
}
`;

export const luaSample = `-- A tiny event bus: handlers, a frame loop, and message dispatch.
local EventBus = {}
EventBus.__index = EventBus

function EventBus.new()
    return setmetatable({ handlers = {}, queue = {} }, EventBus)
end

function EventBus:on(name, callback)
    if not self.handlers[name] then
        self.handlers[name] = {}
    end
    table.insert(self.handlers[name], callback)
    return self
end

function EventBus:emit(name, ...)
    local handlers = self.handlers[name] or {}
    for i = 1, #handlers do
        handlers[i](...)
    end
end

function EventBus:clear(name)
    self.handlers[name] = nil
    return self
end

local bus = EventBus.new()
local ticks = 0

bus:on("tick", function(dt)
    ticks = ticks + 1
    print("tick " .. ticks .. " dt=" .. tostring(dt))
end)

bus:on("stop", function()
    print("stopped after " .. ticks .. " ticks")
end)

while ticks < 3 do
    bus:emit("tick", 1 / 60)
end

bus:emit("stop")
`;

export const galleySample = `# A tiny CSV-flavoured table: a header row, then rows of cells.
# Cells are bare words, quoted strings, or numbers.

Document
| Header Rows

Header
| Cell HeaderCellTail new_line

HeaderCellTail
| "," Cell HeaderCellTail
|

Rows
| Row Rows
|

Row
| Cell RowCellTail new_line

RowCellTail
| "," Cell RowCellTail
|

Cell
| QuotedCell
| SignedNumber
| Number
| Word
| Boolean

# Cell types beyond bare words: signed counts (-3) and flags (true).

SignedNumber
| "-" Number

Boolean
| "true"
| "false"

QuotedCell
| "\\u{22}" QuotedCellTail

QuotedCellTail
| "\\u{22}"
| Escaped QuotedCellTail
| CellChar QuotedCellTail

Escaped
| "\\u{5c}" "\\u{22}"
| "\\u{5c}" "\\u{5c}"

Number
| digit NumberTail

NumberTail
| digit NumberTail
|

Word
| letter WordTail

WordTail
| letter WordTail
| digit WordTail
|

CellChar
| character^"\\u{22}"^"\\u{5c}"^"\\n"
`;
