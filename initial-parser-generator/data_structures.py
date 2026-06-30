from __future__ import annotations

import dataclasses
import re
import string
from typing import ClassVar

is_pascal_pattern = rb"^[A-Z][a-z0-9]*([A-Z][a-z0-9]*)*$"
is_pascal_re = re.compile(is_pascal_pattern)

procedures_pattern = rb"^(.*?)(@[^\"]+)"
procedures_re = re.compile(procedures_pattern)


BASE_GENERATIVE_TERMINALS = {
    b"digit",
    b"letter",
    b"lowercase_letter",
    b"uppercase_letter",
    b"whitespace",
    b"punctuation",
    b"character",
    b"operator",
    b"new_line",
    b"space",
    b"block_start",
    b"block_end",
}


def parse_generative_terminal(id: bytes) -> tuple[bytes, list[bytes]] | None:
    for base in BASE_GENERATIVE_TERMINALS:
        if id == base:
            return base, []
        if id.startswith(base + b"^"):
            suffix = id[len(base) :]
            exceptions = []
            i = 0
            while i < len(suffix):
                if suffix[i : i + 1] != b"^":
                    return None
                i += 1
                if i >= len(suffix):
                    return None
                quote = suffix[i : i + 1]
                if quote == b'"':
                    closing_char = b'"'
                elif quote == b"'":
                    closing_char = b"\x03"
                else:
                    return None

                i += 1
                closing_idx = -1
                for j in range(i, len(suffix)):
                    if suffix[j : j + 1] == closing_char:
                        if j + 1 == len(suffix) or suffix[j + 1 : j + 2] == b"^":
                            closing_idx = j
                            break
                if closing_idx != -1:
                    exceptions.append(suffix[i:closing_idx])
                    i = closing_idx + 1
                else:
                    exceptions.append(suffix[i:])
                    break
            return base, exceptions
    return None


def is_pascal_case(s):
    return is_pascal_re.match(s) is not None


@dataclasses.dataclass(slots=True, kw_only=True)
class Symbol:
    id: bytes
    index: int = dataclasses.field(init=False)
    procedures: list[bytes] = dataclasses.field(init=False)
    printable: str = dataclasses.field(init=False)
    is_ast_enabled: bool = dataclasses.field(init=False, default=True)

    string_to_symbol: ClassVar[dict[bytes, Symbol]] = {}

    def __post_init__(self):
        if procedures_match := procedures_re.match(self.id):
            self.id, remaining = procedures_match.groups()
            self.procedures = list(remaining[1:].split(b"@"))
        else:
            self.procedures = []
        for procedure in self.procedures:
            if not procedure.islower():
                raise ValueError(
                    f'Procedure name "{procedure.decode("utf-8")}" must be lowercase.'
                )

        if self.id in Symbol.string_to_symbol:
            self.index = Symbol.string_to_symbol[self.id].index
        else:
            self.index = len(Symbol.string_to_symbol)
            Symbol.string_to_symbol[self.id] = self

        self.fix_id()

        if self.id == b"":
            raise ValueError("Id of a symbol cannot be empty!")

        self.printable = (
            self.id.decode("raw-unicode-escape")
            .encode("unicode-escape")
            .decode("utf-8")
            .replace('"', '\\"')
        )

    def fix_id(self) -> None:
        pass

    @staticmethod
    def from_str(id: bytes) -> Symbol:
        if (found_symbol := Symbol.string_to_symbol.get(id, None)) is not None:
            return found_symbol

        if (id.startswith(b'"') and id.endswith(b'"')) or (
            id.startswith(b"'") and id.endswith(b"\x03")
        ):
            return TerminalSymbol(id=id)

        parsed_generative_terminal = parse_generative_terminal(id)
        if parsed_generative_terminal is not None:
            base_name, exceptions = parsed_generative_terminal
            match base_name:
                case b"digit":
                    terminals = string.digits
                case b"letter":
                    terminals = string.ascii_letters
                case b"lowercase_letter":
                    terminals = string.ascii_lowercase
                case b"uppercase_letter":
                    terminals = string.ascii_uppercase
                case b"whitespace":
                    terminals = string.whitespace
                case b"punctuation":
                    terminals = string.punctuation
                case b"character":
                    terminals = (
                        string.ascii_letters
                        + string.digits
                        + string.punctuation
                        + string.whitespace
                    )
                case b"operator":
                    terminals = [
                        "+",
                        "*",
                        "/",
                        "&",
                        "|",
                        ">",
                        ">=",
                        "<",
                        "<=",
                        "=",
                    ]
                case b"new_line":
                    terminals = "\n"
                case b"space":
                    terminals = " "
                case b"block_start":
                    terminals = "\x01"
                case b"block_end":
                    terminals = "\x02"
                case _:
                    raise ValueError(
                        f'Unknown generative terminal: "{id.decode("utf-8")}"'
                    )

            if exceptions:
                excluded = set()
                for exc in exceptions:
                    for b in exc:
                        excluded.add(chr(b))
                terminals = [t for t in terminals if t not in excluded]

            return GenerativeTerminalSymbol(
                id=id,
                terminals=[i.encode("raw-unicode-escape") for i in terminals],
            )

        return VariableSymbol(id=id)

    def __hash__(self) -> int:
        return self.index

    def __repr__(self) -> str:
        return self.id.decode("utf-8").encode("unicode_escape").decode("utf-8")

    def __eq__(self, other) -> bool:
        return self.index == other.index

    def __lt__(self, other) -> bool:
        # if not isinstance(other, Symbol):
        #     raise TypeError(
        #         f'Can\'t compare "{self}" with type "{type(self).__name__}" and "{other}" with type "{type(other).__name__}"'
        #     )
        return self.index < other.index


@dataclasses.dataclass(slots=True, repr=False, unsafe_hash=False, eq=False)
class VariableSymbol(Symbol):
    variable_index: int = dataclasses.field(init=False)

    string_to_variable: ClassVar[dict[bytes, VariableSymbol]] = {}

    def __post_init__(self):
        if self.id.startswith(b"_"):
            self.is_ast_enabled = False

        super().__post_init__()

        if self.id in VariableSymbol.string_to_variable:
            self.variable_index = VariableSymbol.string_to_variable[
                self.id
            ].variable_index
        else:
            self.variable_index = len(VariableSymbol.string_to_variable)
            VariableSymbol.string_to_variable[self.id] = self

        if not is_pascal_case(self.id) and (
            self.id[0:1] != b"_" or not is_pascal_case(self.id[1:])
        ):
            raise ValueError(
                f'Variable name "{self.id.decode("utf-8")}" must be PascalCase.'
            )


@dataclasses.dataclass(slots=True, unsafe_hash=False, eq=False)
class TerminalSymbol(Symbol):
    terminals: list[bytes] = dataclasses.field(default_factory=list)

    def __post_init__(self):
        super().__post_init__()
        self.terminals = self.terminals or [self.id]

    def __repr__(self) -> str:
        return f"terminal_{super().__repr__()}"

    def fix_id(self) -> None:
        self.id = self.id[1:-1]


@dataclasses.dataclass(slots=True, unsafe_hash=False, eq=False)
class GenerativeTerminalSymbol(TerminalSymbol):
    def __repr__(self) -> str:
        return f"generative_{super().__repr__()}"

    def __post_init__(self):
        super().__post_init__()
        parsed = parse_generative_terminal(self.id)
        if parsed is None:
            raise ValueError(
                f'Terminal ID "{self.id.decode("utf-8")}" is not a valid generative terminal.'
            )

    def fix_id(self) -> None:
        pass


@dataclasses.dataclass(slots=True, unsafe_hash=False, eq=False)
class SpecialSymbol(TerminalSymbol):
    def __repr__(self) -> str:
        return "special_"


@dataclasses.dataclass(slots=True, unsafe_hash=False, eq=False)
class EndSymbol(SpecialSymbol):
    def __init__(self) -> None:
        super().__init__(id=b"\x00")

    def __post_init__(self):
        super().__post_init__()
        self.terminals = self.terminals or [self.id]

    def __repr__(self) -> str:
        return f"{super().__repr__()}EOF"

    def fix_id(self) -> None:
        pass


@dataclasses.dataclass(slots=True)
class RightHandSide:
    symbols: tuple[Symbol, ...]
    procedures: list[bytes] = dataclasses.field(default_factory=list)
    _hash: int = dataclasses.field(init=False)

    def __post_init__(self):
        self._hash = hash(tuple(self.symbols))

    def __repr__(self) -> str:
        return "|".join(str(symbol) for symbol in ("",) + self.symbols + ("",))

    def __hash__(self) -> int:
        return self._hash

    def __lt__(self, other) -> bool:
        # if not isinstance(other, type(self)):
        #     raise TypeError(
        #         f'Can\'t compare "{self}" with type "{type(self).__name__}" and "{other}" with type "{type(other).__name__}"'
        #     )
        return self.symbols < other.symbols


type Rule = tuple[bytes, RightHandSide]
