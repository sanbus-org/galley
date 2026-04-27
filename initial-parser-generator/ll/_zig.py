from functools import cached_property

from base._zig import ParserGeneratorZigMixin
from ll._parse_table import LLParserGeneratorParseTableMixin


class LLParserGeneratorZigMixin(
    LLParserGeneratorParseTableMixin,
    ParserGeneratorZigMixin,
):
    @cached_property
    def zig_parse_table(self) -> str:
        def token_repr(token: bytes) -> str:
            return (
                token.decode("raw-unicode-escape")
                .encode("unicode-escape")
                .decode("utf-8")
                .replace('"', '\\"')
            )

        return f"""\
{self.zig_base}

pub const parse_table = blk: {{
    @setEvalBranchQuota(20_000);
    break :blk [_]std.StaticStringMap(usize){{
{
            "\n".join(
                [
                    f'''        std.StaticStringMap(usize).initComptime(.{{{
                        "\n            ".join(
                            [""]
                            + [
                                f'.{{ "{token_repr(token)}", {
                                    self.rules_list.index(rule)
                                }}},'
                                for token, rule in self.parse_table[symbol].items()
                            ]
                        )
                    }
        }}), // {repr(symbol)} {self.symbols.index(symbol)}'''
                    for symbol in self.symbols
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
