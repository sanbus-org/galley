"""Exercise core Python statements and expressions."""

import os
import sys as system
from collections.abc import Callable

CONSTANT = 0x1F
raten = 3.14
name = "galley" + "py"
items = [1, 2, 3, 4]
mapping = {"a": 1, "b": 2}
unique = {1, 2, 3}
pair = (1, "two")
nothing = None
flag = True
other = False
dots = ...

x = 1 + 2 * 3 - 4 / 5 // 6 % 7 @ 8
y = x << 2 >> 1 & 255 | 16 ^ 3
z = -x + ~y
p = x**2
q = x if flag else -x
r = lambda a, b=2, *args, **kwargs: a + b
awaitable = None
total = sum(items)
count = len(items)

a, b = b, a
first, *rest = items
text: str = "hello"
number: int = 42
lazy: "Callable[[int], int]" = str

assert flag, "must hold"
assert flag
del mapping["a"]
raise ValueError("bad")
raise ValueError("bad") from RuntimeError("cause")
result = None
if flag:
    result = "yes"
elif other:
    result = "maybe"
else:
    result = "no"

while result:
    result = other
    if not other:
        break
    continue

for index, value in enumerate(items):
    print(index, value)
else:
    print("done")

for key in mapping:
    pass

with open("f.txt") as handle:
    data = handle.read()

with open("a") as first_handle, open("b") as second_handle:
    pass

try:
    risky = int(name)
except ValueError as exc:
    print(exc)
except (TypeError, KeyError):
    raise
else:
    print("ok")
finally:
    print("cleanup")

try:
    pass
except* ValueError as group:
    print(group)


def greet(who: str = "world", *args: int, option: bool = False, **kwargs: str) -> str:
    """Greet someone."""
    return f"hello {who}"


async def fetch(url: str) -> str:
    return url


@decorator
@other_decorator(argument=1)
def decorated() -> None:
    pass


@class_decorator
class Widget(Thing):
    """A widget."""

    def __init__(self, name: str) -> None:
        self.name = name

    @property
    def label(self) -> str:
        return self.name


class Plain:
    pass


squares = [v * v for v in items if v]
uniques = {v for v in items}
_lookup = {v: v * v for v in items}
gen = (v for v in items)

bit = 0b1010
octal = 0o17
big = 1_000_000
tiny = 1e-5
imag = 3j
combo = 0x1F + 0o17 + 0b1

chosen = mapping.get("b", 0)
sliced = items[1:3]
first_item = items[0]
last_item = items[-1]
stepped = items[::2]
element = mapping["b"]
attribute = system.argv
called = print("hi", end="\n")
starred = [*items, 4]


def generator():
    yield 1
    received = yield 2
    yield from gen
    return received


async def collect(agen):
    seen = [v async for v in agen]
    return seen


global_name = "g"
