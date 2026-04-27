from __future__ import annotations

import dataclasses
from functools import cached_property


@dataclasses.dataclass(frozen=True, kw_only=True)
class Symbol:
    id: bytes

    def __post_init__(self):
        if self.id == b"":
            raise ValueError("Id of a symbol cannot be empty!")

    @staticmethod
    def from_str(string: bytes) -> Symbol:
        if string.startswith(b"@"):
            return ProcedureSymbol(id=string[1:])
        if string.startswith(b'"') and string.endswith(b'"'):
            return TerminalSymbol(id=string[1:-1])
        return VariableSymbol(id=string)

    def __repr__(self) -> str:
        return self.id.decode("utf-8").encode("unicode_escape").decode("utf-8")

    def __lt__(self, other) -> bool:
        # if not isinstance(other, Symbol):
        #     raise TypeError(
        #         f'Can\'t compare "{self}" with type "{type(self).__name__}" and "{other}" with type "{type(other).__name__}"'
        #     )
        return (self.type_string, self.id) < (other.type_string, other.id)

    @cached_property
    def type_string(self) -> str:
        symbol_type = type(self).__name__
        assert symbol_type.endswith("Symbol")
        return symbol_type[: -len("Symbol")].lower()

    @cached_property
    def printable(self) -> str:
        return (
            self.id.decode("raw-unicode-escape")
            .encode("unicode-escape")
            .decode("utf-8")
            .replace('"', '\\"')
        )


@dataclasses.dataclass(frozen=True, repr=False)
class GrammarSymbol(Symbol):
    pass


@dataclasses.dataclass(frozen=True)
class VariableSymbol(GrammarSymbol):
    def __repr__(self) -> str:
        return super().__repr__()


@dataclasses.dataclass(frozen=True)
class TerminalSymbol(GrammarSymbol):
    def __repr__(self) -> str:
        return f"'{super().__repr__()}'"


@dataclasses.dataclass(frozen=True)
class SpecialSymbol(Symbol):
    def __repr__(self) -> str:
        return "*"


class EndSymbol(SpecialSymbol, TerminalSymbol):
    def __init__(self) -> None:
        super().__init__(id=b"\x00")

    def __repr__(self) -> str:
        return f"{super().__repr__()}EOF"


@dataclasses.dataclass(frozen=True, repr=False)
class LogicalSymbol(Symbol):
    pass


@dataclasses.dataclass(frozen=True)
class ProcedureSymbol(LogicalSymbol):
    def __repr__(self) -> str:
        return f"@{super().__repr__()}"


@dataclasses.dataclass
class RightHandSide:
    symbols: list[Symbol]

    def __post_init__(self):
        self._hash = hash(tuple(self.symbols))

    def __repr__(self) -> str:
        return "|".join(str(symbol) for symbol in [""] + self.symbols + [""])

    def __hash__(self) -> int:
        return self._hash

    def __lt__(self, other) -> bool:
        # if not isinstance(other, type(self)):
        #     raise TypeError(
        #         f'Can\'t compare "{self}" with type "{type(self).__name__}" and "{other}" with type "{type(other).__name__}"'
        #     )
        return self.symbols < other.symbols


type Rule = tuple[bytes, RightHandSide]
