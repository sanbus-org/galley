from __future__ import annotations

import copy
import dataclasses
from collections import defaultdict
from functools import cached_property

from data_structures import (
    RightHandSide,
    Rule,
    Symbol,
    TerminalSymbol,
    VariableSymbol,
)

tuple_type = tuple


@dataclasses.dataclass
class Item:
    variable: VariableSymbol
    right_hand_side: RightHandSide
    head: int
    look_ahead: TerminalSymbol

    def __post_init__(self):
        self._hash = hash(
            (
                self.head,
                self.look_ahead.id,
                self.variable.id,
                *self.right_hand_side.symbols,
            )
        )

    def __hash__(self) -> int:
        return self._hash

    @cached_property
    def tuple(self) -> tuple_type[int, TerminalSymbol, VariableSymbol, RightHandSide]:
        return (self.head, self.look_ahead, self.variable, self.right_hand_side)

    @cached_property
    def head_symbol(self) -> Symbol | None:
        return (
            self.right_hand_side.symbols[self.head]
            if self.head < len(self.right_hand_side.symbols)
            else None
        )

    @cached_property
    def advanced(self) -> Item:
        return copy.replace(self, head=self.head + 1)

    @cached_property
    def remaining(self) -> list[Symbol]:
        return [*self.right_hand_side.symbols[self.head + 1 :]]

    def __repr__(self) -> str:
        return f"[{self.variable} -> {
            '|'.join(
                f'.{str(symbol)}' if i == self.head + 1 else str(symbol)
                for i, symbol in enumerate([''] + self.right_hand_side.symbols + [''])
            )
        },'{
            self.look_ahead.id.decode('utf-8').encode('unicode_escape').decode('utf-8')
        }']"

    def __lt__(self, other):
        # if not isinstance(other, type(self)):
        #     raise TypeError(
        #         f'Can\'t compare "{self}" with type "{type(self).__name__}" and "{other}" with type "{type(other).__name__}"'
        #     )
        return self.tuple < other.tuple


@dataclasses.dataclass
class State:
    items: set[Item]

    def __post_init__(self):
        self._hash = hash(tuple(sorted(hash(i) for i in self.items)))

    @cached_property
    def sorted_items(self) -> list[Item]:
        return sorted(self.items)

    @cached_property
    def items_by_symbol(self) -> dict[Symbol, State]:
        index: dict[Symbol, set[Item]] = defaultdict(set)
        for item in self.items:
            if item.head_symbol is None:
                continue
            index[item.head_symbol].add(item.advanced)

        return {symbol: State(items=items) for symbol, items in index.items()}

    def __repr__(self) -> str:
        return f"State {{{','.join(repr(item) for item in self.sorted_items)}}}"

    def __hash__(self) -> int:
        return self._hash

    def __eq__(self, other):
        # if not isinstance(other, type(self)):
        #     return False
        return self._hash == other._hash

    def __lt__(self, other):
        # if not isinstance(other, type(self)):
        #     raise TypeError(
        #         f'Can\'t compare "{self}" with type "{type(self).__name__}" and "{other}" with type "{type(other).__name__}"'
        #     )
        return self.items < other.items


empty_state = State(items=set())


@dataclasses.dataclass(frozen=True)
class Resolution:
    @cached_property
    def type_string(self) -> str:
        symbol_type = type(self).__name__
        assert symbol_type.endswith("Resolution")
        return symbol_type[: -len("Resolution")].lower()


@dataclasses.dataclass(frozen=True)
class ShiftResolution(Resolution):
    state: State

    def __repr__(self) -> str:
        return f"[Shift:{self.state}]"


@dataclasses.dataclass(frozen=True)
class ReduceResolution(Resolution):
    rule: Rule

    def __repr__(self) -> str:
        return f"[Reduce:{self.rule[0].decode('utf-8')} <~ {self.rule[1]}]"


@dataclasses.dataclass(frozen=True)
class GotoResolution(Resolution):
    state: State

    def __repr__(self) -> str:
        return f"[Goto:{self.state}]"


@dataclasses.dataclass(frozen=True)
class AcceptResolution(Resolution):
    def __repr__(self) -> str:
        return "[Accept]"
