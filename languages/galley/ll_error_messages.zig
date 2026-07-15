const std = @import("std");
const root = @import("galley");

const Syntax = root.SyntaxDiagnostic;

fn syntax(args: root.SyntaxErrorMessageArgs) Syntax {
    return switch (args.diagnostic) {
        .syntax => |diagnostic| diagnostic,
    };
}

fn fmt(args: root.SyntaxErrorMessageArgs, comptime body: []const u8) ![]const u8 {
    const diagnostic = syntax(args);
    return switch (args.style) {
        .plain => try std.fmt.allocPrint(
            args.allocator,
            "SyntaxError at {d}:{d}:\n" ++ body ++ "\nUnexpected token: \"{f}\"\n",
            .{
                diagnostic.line,
                diagnostic.column,
                root.string_utilities.fmtString(diagnostic.unexpected_token),
            },
        ),
        .ansi => try std.fmt.allocPrint(
            args.allocator,
            "\x1b[35mSyntaxError at {d}:{d}:\x1b[0m\n" ++ body ++ "\n\x1b[37mUnexpected token: \x1b[31m\"{f}\"\x1b[0m\n",
            .{
                diagnostic.line,
                diagnostic.column,
                root.string_utilities.fmtString(diagnostic.unexpected_token),
            },
        ),
    };
}

fn expectedRule(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected a grammar rule header.\n" ++
            "A rule starts with an uppercase variable name, or an underscore-prefixed helper variable, for example:\n" ++
            "  Expr\n" ++
            "  _Whitespace",
    );
}

fn expectedRhsLine(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected a right-hand-side line for the current rule.\n" ++
            "Start each production with `|`, or use `#` for a comment, for example:\n" ++
            "  | Symbol OtherSymbol\n" ++
            "  |",
    );
}

fn expectedSymbol(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected a grammar symbol.\n" ++
            "Use an uppercase variable (`Expr`), a quoted terminal (`\"let\"`), or a lowercase generative terminal (`digit`).",
    );
}

fn expectedQuotedTerminal(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected a quoted terminal symbol.\n" ++
            "Use double quotes for literal text, for example `\"let\"`, or single quotes for escaped/control-style terminals.",
    );
}

fn expectedGenerativeTerminal(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected a lowercase generative terminal name.\n" ++
            "Common examples are `digit`, `letter`, `space`, `new_line`, and `character`.",
    );
}

fn expectedVariable(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected a variable symbol.\n" ++
            "Variables must start with an uppercase letter. Helper variables may start with `_`, for example `_OptionalBlank`.",
    );
}

fn expectedProcedureName(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected a procedure name after `@`.\n" ++
            "Procedure names use lower-camel style in grammar annotations, for example `@dropSelf` or `@replaceWithChildren`.",
    );
}

fn expectedProcedureTail(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected either another procedure annotation, whitespace, or the end of the line.\n" ++
            "Procedure annotations look like `@dropSelf` and are placed directly after a rule header, production marker, or symbol.",
    );
}

fn expectedSpaceSeparatedSymbol(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected a space before the next symbol, or a newline to end this production.\n" ++
            "Right-hand-side symbols are space-separated.",
    );
}

fn expectedGenerativeException(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected a generative-terminal exception, a procedure annotation, whitespace, or a newline.\n" ++
            "Exceptions use `^` followed by a terminal, for example `character^\"\\n\"`.",
    );
}

fn expectedNewline(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(args, "Expected a newline here.");
}

fn expectedNewlineOrComment(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected another newline, a comment line, or the next grammar item.\n" ++
            "Comment lines start with `#`. Blank lines separate grammar rules.",
    );
}

fn expectedCommentStart(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(args, "Expected `#` to start a grammar comment line.");
}

fn expectedCommentContent(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected comment text or the end of the comment line.\n" ++
            "A grammar comment starts with `#` and continues until the newline.",
    );
}

fn expectedNextRhsLineOrRuleSeparator(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected another production line, a comment line, or a blank line before the next rule.\n" ++
            "Production lines start with `|`; comment lines start with `#`.\n" ++
            "If this is a new rule header, insert a blank line before it.",
    );
}

fn expectedHelperVariableMarker(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected `_` to start a helper variable name.\n" ++
            "Helper variables look like `_Whitespace` and regular variables start with an uppercase letter.",
    );
}

fn expectedSingleQuotedTerminalBoundary(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected a single-quoted terminal boundary.\n" ++
            "Single-quoted terminals look like `'literal'`. Use double quotes for simpler literal text.",
    );
}

fn expectedDoubleQuotedTerminalBoundary(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(args, "Expected `\"` to open or close a double-quoted terminal.");
}

fn expectedSingleQuotedTerminalContent(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected more single-quoted terminal content or the closing quote.\n" ++
            "Example: `'literal'`.",
    );
}

fn expectedDoubleQuotedTerminalContent(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected more double-quoted terminal content or the closing quote.\n" ++
            "Example: `\"literal\"`.",
    );
}

fn expectedTerminalCharacter(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected a character inside the terminal literal.\n" ++
            "Close the terminal with the matching quote, or add literal text before it.",
    );
}

fn expectedControlCharacter(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected an escaped control character in the terminal literal.\n" ++
            "Supported control escapes here are `\\x01`, `\\x03`, and `\\x04`.",
    );
}

fn expectedControlCharacterEscape(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(args, "Expected this specific escaped control character in the terminal literal.");
}

fn expectedIdentifierTail(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected an identifier continuation or the end of the identifier.\n" ++
            "Identifiers may continue with letters, digits, or `_`.",
    );
}

fn expectedLetter(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(args, "Expected a letter here.");
}

fn expectedDigit(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(args, "Expected a digit here.");
}

fn expectedProcedureNameTail(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected a procedure-name continuation or the end of the procedure name.\n" ++
            "Procedure names may continue with letters or digits.",
    );
}

fn expectedEndOfGrammar(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return fmt(
        args,
        "Expected the end of the grammar file.\n" ++
            "Remove trailing text, or make sure the previous rule is complete.",
    );
}

pub fn syntax_error_ll_Start__expected_Rules(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedRule(args);
}

pub fn syntax_error_ll_Rules__expected_Rule(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedRule(args);
}

pub fn syntax_error_ll_Rule__expected_VariableSymbol(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedRule(args);
}

pub fn syntax_error_ll__AugmentedStart__expected_Start(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedRule(args);
}

pub fn syntax_error_ll_RulesTail__expected_NewLines_or_end_of_RulesTail(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedNewline(args);
}

pub fn syntax_error_ll_NewLines__expected_generative_terminal_new_line(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedNewline(args);
}

pub fn syntax_error_ll_generative_terminal_new_line__expected_generative_terminal_new_line(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedNewline(args);
}

pub fn syntax_error_ll_VariableSymbol__expected_UppercaseId_or_terminal__(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedVariable(args);
}

pub fn syntax_error_ll_UppercaseId__expected_generative_terminal_uppercase_letter(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedVariable(args);
}

pub fn syntax_error_ll_ProcedureTail__expected_end_of_ProcedureTail_or_terminal__x64(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedProcedureTail(args);
}

pub fn syntax_error_ll_terminal__x64__expected_terminal__x64(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedProcedureName(args);
}

pub fn syntax_error_ll_CamelCaseId__expected_generative_terminal_lowercase_letter(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedProcedureName(args);
}

pub fn syntax_error_ll_RightHandSides__expected_RightHandSideLine(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedRhsLine(args);
}

pub fn syntax_error_ll_RightHandSideLine__expected_terminal__x124_or_terminal__x35(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedRhsLine(args);
}

pub fn syntax_error_ll_terminal__x124__expected_terminal__x124(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedRhsLine(args);
}

pub fn syntax_error_ll_RightHandSide__expected_end_of_RightHandSide_or_generative_terminal_space(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedSpaceSeparatedSymbol(args);
}

pub fn syntax_error_ll_generative_terminal_space__expected_generative_terminal_space(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedSpaceSeparatedSymbol(args);
}

pub fn syntax_error_ll_RightHandSideTail__expected_end_of_RightHandSideTail_or_generative_terminal_space(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedSpaceSeparatedSymbol(args);
}

pub fn syntax_error_ll_Symbol__expected_GenerativeTerminalSymbol_or_TerminalSymbol_or_VariableSymbol(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedSymbol(args);
}

pub fn syntax_error_ll_TerminalSymbol__expected_terminal__x34_or_terminal__x39(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedQuotedTerminal(args);
}

pub fn syntax_error_ll_GenerativeTerminalSymbol__expected_LowercaseId(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedGenerativeTerminal(args);
}

pub fn syntax_error_ll_LowercaseId__expected_generative_terminal_lowercase_letter(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedGenerativeTerminal(args);
}

pub fn syntax_error_ll_GenerativeTerminalExceptions__expected_end_of_GenerativeTerminalExceptions_or_terminal__x94(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedGenerativeException(args);
}

pub fn syntax_error_ll_terminal__x94__expected_terminal__x94(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedGenerativeException(args);
}

// Added by `galley --fill-error-messages`.

pub fn syntax_error_ll_NewLinesTail__expected_end_of_NewLinesTail_or_generative_terminal_new_line_or_terminal__x35(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedNewlineOrComment(args);
}
pub fn syntax_error_ll_terminal__x35__expected_terminal__x35(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedCommentStart(args);
}
pub fn syntax_error_ll_AnyContent__expected_ControlCharacter_or_generative_terminal_character_x94_x34_x92n_x34(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedCommentContent(args);
}
pub fn syntax_error_ll_RightHandSidesTail__expected_RightHandSideLine_or_end_of_RightHandSidesTail(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedNextRhsLineOrRuleSeparator(args);
}
pub fn syntax_error_ll_terminal____expected_terminal__(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedHelperVariableMarker(args);
}
pub fn syntax_error_ll_terminal__x39__expected_terminal__x39(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedSingleQuotedTerminalBoundary(args);
}
pub fn syntax_error_ll_StringContent__expected_end_of_StringContent_or_generative_terminal_character(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedSingleQuotedTerminalContent(args);
}
pub fn syntax_error_ll_terminal__x92x03__expected_terminal__x92x03(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedSingleQuotedTerminalBoundary(args);
}
pub fn syntax_error_ll_terminal__x34__expected_terminal__x34(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedDoubleQuotedTerminalBoundary(args);
}
pub fn syntax_error_ll_SimpleStringContent__expected_end_of_SimpleStringContent_or_generative_terminal_character_x94_x39_x34_x92x03(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedDoubleQuotedTerminalContent(args);
}
pub fn syntax_error_ll_generative_terminal_character__expected_generative_terminal_character(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedTerminalCharacter(args);
}
pub fn syntax_error_ll_generative_terminal_character_x94_x39_x34_x92x03__expected_generative_terminal_character_x94_x39_x34_x92x03(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedTerminalCharacter(args);
}
pub fn syntax_error_ll_ControlCharacter__expected_terminal__x92x01_or_terminal__x92x03_or_terminal__x92x04(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedControlCharacter(args);
}
pub fn syntax_error_ll_terminal__x92x01__expected_terminal__x92x01(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedControlCharacterEscape(args);
}
pub fn syntax_error_ll_terminal__x92x04__expected_terminal__x92x04(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedControlCharacterEscape(args);
}
pub fn syntax_error_ll_generative_terminal_character_x94_x34_x92n_x34__expected_generative_terminal_character_x94_x34_x92n_x34(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedCommentContent(args);
}
pub fn syntax_error_ll_AnyContentTail__expected_ControlCharacter_or_end_of_AnyContentTail_or_generative_terminal_character_x94_x34_x92n_x34(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedCommentContent(args);
}
pub fn syntax_error_ll_IdTail__expected_end_of_IdTail_or_generative_terminal_digit_or_generative_terminal_letter_or_terminal__(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedIdentifierTail(args);
}
pub fn syntax_error_ll_generative_terminal_letter__expected_generative_terminal_letter(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedLetter(args);
}
pub fn syntax_error_ll_generative_terminal_digit__expected_generative_terminal_digit(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedDigit(args);
}
pub fn syntax_error_ll_generative_terminal_lowercase_letter__expected_generative_terminal_lowercase_letter(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedGenerativeTerminal(args);
}
pub fn syntax_error_ll_generative_terminal_uppercase_letter__expected_generative_terminal_uppercase_letter(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedVariable(args);
}
pub fn syntax_error_ll_CamelCaseIdTail__expected_end_of_CamelCaseIdTail_or_generative_terminal_digit_or_generative_terminal_letter(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedProcedureNameTail(args);
}
pub fn syntax_error_ll_special_EOF__expected_special_EOF(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return expectedEndOfGrammar(args);
}
