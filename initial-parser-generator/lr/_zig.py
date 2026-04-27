from functools import cached_property

from base._zig import ParserGeneratorZigMixin
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
from lr._parse_table import LRParserGeneratorParseTableMixin


class LRParserGeneratorZigMixin(
    LRParserGeneratorParseTableMixin,
    ParserGeneratorZigMixin,
):
    @cached_property
    def zig_parse_table(self) -> str:
        return f"""\
{self.zig_base}

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
    break :blk &[_]data_structures.StaticStringMap(Resolution){{
{
            "\n".join(
                [
                    f'''        data_structures.StaticStringMap(Resolution).initComptime(\
&[_]data_structures.StaticStringMap(Resolution).Entry{{{
                        "\n            ".join(
                            [""]
                            + [
                                f'.{{ "{symbol.printable}", Resolution{{ .type = .{
                                    resolution.type_string
                                }, .data_index = {
                                    self.canonical_state_indices[resolution.state]
                                    if isinstance(resolution, ShiftResolution)
                                    else self.rules_list.index(resolution.rule)
                                    if isinstance(resolution, ReduceResolution)
                                    else 0
                                    if isinstance(resolution, AcceptResolution)
                                    else 1 / 0
                                } }} }},'
                                for symbol, resolution in sorted(
                                    self.lr_parse_table[state].items(),
                                    key=lambda x: x[0],
                                )
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
    break :blk &[_]data_structures.StaticIntMap(u16, u16){{
{
            "\n".join(
                [
                    f'''        data_structures.StaticIntMap(u16, u16).initComptime(\
&[_]data_structures.StaticIntMap(u16, u16).Entry{{{
                        "\n".join(
                            [""]
                            + [
                                f"            .{{ {self.variables.index(symbol)}, {
                                    self.canonical_state_indices[resolution.state]
                                    if isinstance(resolution, GotoResolution)
                                    else 1 / 0
                                } }},"
                                for symbol, resolution in self.lr_parse_table[
                                    state
                                ].items()
                                if isinstance(symbol, VariableSymbol)
                            ]
                            + (
                                ["        "]
                                if len(
                                    [
                                        symbol
                                        for symbol in self.lr_parse_table[state]
                                        if isinstance(symbol, VariableSymbol)
                                    ]
                                )
                                else []
                            )
                        )
                    }}}), // {repr("")} {self.canonical_state_indices[state]}'''
                    for state in self.canonical_states
                ]
            )
        }
    }};
}};

pub const rule_procedures = rule_procedures: {{
    var arr: [{
            len(self.rules_list)
        }]?*const data_structures.RuleProcedure = .{{null}} ** {len(self.rules_list)};

    for (rules, 0..) |rule, index| {{
        const procedure_name = "reduction_" ++ variables[rule.header] ++ "_" ++ rule.right_hand_side_index;
        if (@hasDecl(parser.procedures, procedure_name)) {{
            arr[index] = data_structures.wrap_procedure(data_structures.RuleProcedure, @field(parser.procedures, procedure_name), procedure_name);
        }}
    }}

    break :rule_procedures arr;
}};

pub const variable_procedures = variable_procedures: {{
    var arr: [{
            len(self.variables)
        }]?*const data_structures.VariableProcedure = .{{null}} ** {
            len(self.variables)
        };

    for (variables, 0..) |variable, index| {{
        const procedure_name = "reduction_" ++ variable;
        if (@hasDecl(parser.procedures, procedure_name)) {{
            arr[index] = data_structures.wrap_procedure(data_structures.VariableProcedure, @field(parser.procedures, procedure_name), variable);
        }}
    }}

    break :variable_procedures arr;
}};

pub const reduction_procedure: ?*const data_structures.ReductionProcedure = if (@hasDecl(parser.procedures, "reduction")) data_structures.wrap_procedure(data_structures.ReductionProcedure, @field(parser.procedures, "reduction"), "reduction") else null;
"""
