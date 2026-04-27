from pathlib import Path
from typing import override

from base._nullables import ParserGeneratorNullablesMixin
from data_structures import (
    LogicalSymbol,
    Rule,
    TerminalSymbol,
    VariableSymbol,
)


class LLParserGeneratorFirstsMixin(ParserGeneratorNullablesMixin):
    _firsts_cache: dict[VariableSymbol, dict[bytes, Rule]]

    def __init__(self) -> None:
        self._firsts_cache = {}
        super().__init__()

    @override
    def log_to_file(self, directory: Path) -> None:
        super().log_to_file(directory)
        if directory:
            with (directory / "firsts.log").open("w") as output:
                for variable in self.rules:
                    print(variable.decode("utf-8"), file=output)
                    print(
                        "  "
                        + "\n  ".join(
                            [
                                f'"{i.decode("utf-8")}": {j}'
                                for i, j in sorted(
                                    self._firsts(VariableSymbol(id=variable)).items(),
                                    key=lambda i: i[0],
                                )
                            ]
                        ),
                        file=output,
                    )

    def _firsts(
        self,
        variable: VariableSymbol,
        *,
        _visited: set[VariableSymbol] | None = None,
    ) -> dict[bytes, Rule]:
        if variable not in self._firsts_cache:
            if _visited and variable in _visited:
                return {}
            new_visited = (_visited | {variable}) if _visited else set()
            symbol_firsts: dict[bytes, Rule] = {}
            for right_hand_side in self.rules[variable.id]:
                for rhs_symbol in right_hand_side.symbols:
                    if isinstance(rhs_symbol, LogicalSymbol):
                        continue

                    if isinstance(rhs_symbol, VariableSymbol):
                        new_firsts = self._firsts(
                            rhs_symbol,
                            _visited=new_visited,
                        )
                        ambiguity_set: set[bytes] = {
                            terminal
                            for terminal in symbol_firsts
                            if terminal in new_firsts
                            and right_hand_side != symbol_firsts[terminal]
                        }
                        if ambiguity_set:
                            ambiguity = ambiguity_set.pop()
                            raise SyntaxError(
                                f"""Ambiguity in firsts for variable "{variable}":
{variable},"{ambiguity.decode()}"->{symbol_firsts[ambiguity]}
{rhs_symbol},"{ambiguity.decode()}"->{new_firsts[ambiguity]}"""
                            )
                        symbol_firsts |= {
                            (i, (variable.id, right_hand_side)) for i in new_firsts
                        }

                    if isinstance(rhs_symbol, TerminalSymbol):
                        symbol_firsts[rhs_symbol.id] = (variable.id, right_hand_side)

                    if rhs_symbol not in self.nullables:
                        break
            if _visited is None:
                self._firsts_cache[variable] = symbol_firsts
            else:
                return symbol_firsts
        return self._firsts_cache[variable]
