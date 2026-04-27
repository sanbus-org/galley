from functools import cached_property
from pathlib import Path
from typing import override

from base import ParserGeneratorBaseMixin
from data_structures import (
    Rule,
    VariableSymbol,
)


class ParserGeneratorNullablesMixin(ParserGeneratorBaseMixin):
    @cached_property
    def nullables(self) -> dict[VariableSymbol, Rule]:
        nullables: dict[VariableSymbol, Rule] = {}
        needs_update = True
        while needs_update:
            needs_update = False
            for variable in self.variables:
                if variable not in nullables:
                    for right_hand_side in self.rules[variable.id]:
                        for rhs_symbol in right_hand_side.symbols:
                            if (
                                not isinstance(rhs_symbol, VariableSymbol)
                                or rhs_symbol not in nullables
                            ):
                                break
                        else:
                            if variable in nullables:
                                raise SyntaxError(
                                    f'More than one null transition for variable "{variable}".',
                                )
                            nullables[variable] = (variable.id, right_hand_side)
                            needs_update = True

        return nullables

    @override
    def log_to_file(self, directory: Path) -> None:
        super().log_to_file(directory)
        with (directory / "nullables.log").open("w") as output:
            print(
                "\n".join(
                    [f"{header}-{rhs}" for header, rhs in self.nullables.items()]
                ),
                file=output,
            )
