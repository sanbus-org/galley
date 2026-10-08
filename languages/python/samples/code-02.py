"""Exercise Python 3.10-3.14 constructs: match, type aliases, t-strings."""

type Point = tuple[float, float]
type Alias[T] = list[T]
type Mapping[K, V] = dict[K, V]
type Handler[*Ts] = tuple[*Ts]
type WithDefault[T = int] = list[T]
type Bounded[T: str] = list[T]

template = t"hello {name}"
other_template = t"count={count!r:>5}"
raw_template = rt"path\{name}\end"
upper_template = t"{name}"
combined = t"{x:{width}}"
debug = f"{total=}"
nested = f"outer {'inner'} end"
url = f"https://example.com/{name}?x={1 + 2}"
explicit = f"{'a'!s}"
triple_f = f"""line {1}
line {2}"""
triple_t = t"""t {x} end"""

value = {"kind": "circle", "radius": 3}

match value:
    case {"kind": "circle", "radius": radius}:
        area = radius
    case {"kind": "rect", "w": w, "h": h}:
        area = w
    case Point(x=px, y=py):
        area = px
    case [first, *rest]:
        area = first
    case (1 | 2) as number:
        area = number
    case str() | int() if flag:
        area = 0
    case _:
        area = -1

match command.split():
    case [action]:
        pass
    case [action, obj]:
        pass
    case {"key": key, **rest}:
        pass
    case _:
        pass

match status:
    case 200:
        ok = True
    case 404 | 500:
        ok = False
    case Point2D(x=0, y=0):
        ok = True
    case _:
        ok = False


def consumer(gen):
    result = yield 1
    received = yield from gen
    print((yield))
    return received


walrus = (share := 100)
if share := len(items):
    print(share)

while chunk := handle.read(3):
    print(chunk)

pairs = [(k, v) for k, v in mapping.items() if k]
total2 = sum(v for v in items if v > 1)
matrix = [[r * c for c in range(2)] for r in range(2)]
grouped = {}

try:
    pass
except* (ValueError, TypeError) as errors:
    print(errors)

a: int
b: str = "x"
c: list[int] = []
d = e = f = 1
target.attr = 2
target[key] = 3
x, (y, z) = pair
first, *middle, last = items


def outer():
    state = 0

    def inner():
        nonlocal state
        global global_name
        state = 1
        global_name = "g"

    inner()


global global_name

del items[0]
del mapping
del pair, unique
from os import path as ospath
from sys import argv, version as version_info
import json.decoder as json_decoder
from . import sibling
from ..pkg import thing
from ... import deep

print(f"{'nested "quotes" ok'}")
print("tab\there", end="\r\n")
print("backslash \\ done")
print("unicode \u0041\U00000042 end")
print(r"raw \n kept")
print(b"bytes")
print("text")
print(0xCAFE + 0b101 + 0o17)
print(1_2_3, 0xF_F, 3.50, 0.5, 5.0, 2e10, 1e-3)
print(True, False, None, ..., NotImplemented, Ellipsis)
print(a and b or c)
print(not flag)
print(a is b, a is not b, a in items, a not in items)
print(-a, +b, ~c)
print(a < b <= c > d >= e == f != g)
print(a | b, a & b, a ^ b, a << 1, a >> 2)
print(a if b else c)
print(*(1, 2), **{"a": 1})
print(x := 5)
print(lambda: 1)
print(
    [
        1,
        2,
        3,
    ]
)
print(
    {
        "a": 1,
    }
)
print(
    {
        1,
        2,
    }
)
print((1,))
print(())
print([])
print({})
print("adjacent strings")
