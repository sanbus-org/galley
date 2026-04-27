from functools import cached_property

from data_structures import (
    TerminalSymbol,
    VariableSymbol,
)
from glr._data_structures import (
    AcceptResolution,
    GotoResolution,
    ReduceResolution,
    ShiftResolution,
)
from glr._parse_table import GLRParserGeneratorParseTableMixin


class GLRParserGeneratorZigMixin(GLRParserGeneratorParseTableMixin):
    @cached_property
    def zig_parse_table(self) -> str:
        return f"""\
const std = @import("std");
const data_structures = @import("root").data_structures;

pub const parseTableType = "glr";

pub const Rule = struct {{
    header: u16,
    right_hand_side: []const u16,
}};

pub const symbols = &[_][]const u8{{
{"\n".join([f'    "{symbol.printable}",' for symbol in self.symbols])}
}};

pub const rules = &[_]Rule{{
{
            "\n".join(
                [
                    f'''\
    Rule{{ .header = {
                        self.symbols.index(VariableSymbol(id=header))
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
                    }}} }},'''
                    for header, right_hand_side in self.rules_list
                ]
            )
        }
}};

const ResolutionType = enum {{
    shift,
    reduce,
    accept,
}};

const Resolution = struct {{
    type: ResolutionType,
    data_index: u16,
}};

pub const action_table = blk: {{
    @setEvalBranchQuota(10_000_000);
    break :blk &[_]std.StaticStringMap([]const Resolution){{
{
            "\n".join(
                [
                    f'''        std.StaticStringMap([]const Resolution).initComptime(.{{{
                        "\n            ".join(
                            [""]
                            + [
                                f'.{{ "{symbol.printable}", &[_]Resolution{{ {
                                    ", ".join(
                                        f"Resolution{{.type = .{
                                            resolution.type_string
                                        }, .data_index = {
                                            self.canonical_state_indices[
                                                resolution.state
                                            ]
                                            if isinstance(resolution, ShiftResolution)
                                            else self.rules_list.index(resolution.rule)
                                            if isinstance(resolution, ReduceResolution)
                                            else 0
                                            if isinstance(resolution, AcceptResolution)
                                            else print(resolution) or 1 / 0
                                        }}}"
                                        for resolution in resolutions
                                    )
                                } }} }},'
                                for symbol, resolutions in self.parse_table[
                                    state
                                ].items()
                                if isinstance(symbol, TerminalSymbol)
                            ]
                        )
                    }
        }}), // {repr("")} {self.canonical_state_indices[state]}'''
                    for state in self.canonical_states
                ]
            )
        }
    }};
}};

pub const goto_table = blk: {{
    @setEvalBranchQuota(10_000_000);
    break :blk &[_]data_structures.StaticIntMap(u16, []const u16){{
{
            "\n".join(
                [
                    f'''        data_structures.StaticIntMap(u16, []const u16).initComptime(.{{{
                        "\n            ".join(
                            [""]
                            + [
                                f".{{ {self.symbols.index(symbol)}, &[_]u16{{ {
                                    ', '.join(
                                        str(
                                            self.canonical_state_indices[
                                                resolution.state
                                            ]
                                            if isinstance(resolution, GotoResolution)
                                            else 1 / 0
                                        )
                                        for resolution in resolutions
                                    )
                                } }} }},"
                                for symbol, resolutions in self.parse_table[
                                    state
                                ].items()
                                if isinstance(symbol, VariableSymbol)
                            ]
                        )
                    }
        }}), // {repr("")} {self.canonical_state_indices[state]}'''
                    for state in self.canonical_states
                ]
            )
        }
    }};
}};"""
