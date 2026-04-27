from functools import cached_property

from base import ParserGeneratorBaseMixin
from data_structures import GrammarSymbol, TerminalSymbol, VariableSymbol


class ParserGeneratorZigMixin(ParserGeneratorBaseMixin):
    @cached_property
    def zig_base(self):
        return f"""\
const std = @import("std");
const data_structures = @import("root").data_structures;
const parser = @import("parser");

pub const parse_table_type = "{self.parser_type}";

pub const symbols = &[_][]const u8{{
    {"\n    ".join([f'"{symbol.printable}",' for symbol in self.symbols])}
}};

pub const is_terminal = &[_]bool{{
    {
            "\n    ".join(
                [
                    f"{isinstance(symbol, TerminalSymbol) and 'true' or 'false'},"
                    for symbol in self.symbols
                ]
            )
        }
}};

pub const is_grammar = &[_]bool{{
    {
            "\n    ".join(
                [
                    f"{isinstance(symbol, GrammarSymbol) and 'true' or 'false'},"
                    for symbol in self.symbols
                ]
            )
        }
}};

pub const variables = &[_][]const u8{{
    {"\n    ".join([f'"{variable.printable}",' for variable in self.variables])}
}};

pub const rules = &[_]data_structures.Rule{{
{
            "\n".join(
                [
                    f'''\
    data_structures.Rule{{ .header = {
                        self.variables.index(VariableSymbol(id=header))
                    }, .right_hand_side = \
&[_]u16{{{
                        (" " if len(right_hand_side.symbols) > 1 else "")
                        + ", ".join(
                            [
                                f"{self.symbols.index(symbol)}"
                                for symbol in right_hand_side.symbols
                            ]
                        )
                        + (" " if len(right_hand_side.symbols) > 1 else "")
                    }}}, .right_hand_side_index = "{
                        self.rules[header].index(right_hand_side)
                    }" }}, // {VariableSymbol(id=header).printable}'''
                    for header, right_hand_side in self.rules_list
                ]
            )
        }
}};"""
