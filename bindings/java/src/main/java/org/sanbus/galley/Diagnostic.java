package org.sanbus.galley;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * Read-only snapshot of a parse diagnostic, mirroring Python's Diagnostic
 * and the C API's recorded diagnostics.
 */
public final class Diagnostic {
    public static final int KIND_NONE = 0;
    public static final int KIND_SYNTAX = 1;
    public static final int KIND_INDENTATION = 2;

    public static final int RECOVERY_TARGET_NONE = 0;
    public static final int RECOVERY_TARGET_LHS_VARIABLE = 1;
    public static final int RECOVERY_TARGET_PRODUCTION = 2;
    public static final int RECOVERY_TARGET_OCCURRENCE = 3;

    public static final int RESUME_BEFORE = 0;
    public static final int RESUME_AFTER = 1;

    private final int kind;
    private final int line;
    private final int column;
    private final String message;
    private final String messageAnsi;
    private final byte[] unexpectedToken; // nullable
    private final List<byte[]> expectedTokens;
    private final List<String> context;
    private final int syntaxErrorCount;
    private final int[] indentation; // nullable: [spaces, width]
    private final Integer recoveryKind;
    private final byte[] recoveryTerminal;
    private final Integer recoveryResume;
    private final String recoveryLhsVariable;
    private final RecoveryProduction recoveryProduction;
    private final RecoveryOccurrence recoveryOccurrence;

    public static final class RecoveryProduction {
        public final String variable;
        public final int rhsIndex;
        public RecoveryProduction(String variable, int rhsIndex) {
            this.variable = variable;
            this.rhsIndex = rhsIndex;
        }
        @Override public String toString() { return variable + ":" + rhsIndex; }
    }

    public static final class RecoveryOccurrence {
        public final String parentVariable;
        public final int rhsIndex;
        public final int symbolIndex;
        public final String variable;
        public RecoveryOccurrence(String parentVariable, int rhsIndex, int symbolIndex, String variable) {
            this.parentVariable = parentVariable;
            this.rhsIndex = rhsIndex;
            this.symbolIndex = symbolIndex;
            this.variable = variable;
        }
        @Override public String toString() { return parentVariable + ":" + rhsIndex + ":" + symbolIndex + ":" + variable; }
    }

    public Diagnostic(int kind, int line, int column, String message, String messageAnsi,
                      byte[] unexpectedToken, List<byte[]> expectedTokens, List<String> context,
                      int syntaxErrorCount, int[] indentation,
                      Integer recoveryKind, byte[] recoveryTerminal, Integer recoveryResume,
                      String recoveryLhsVariable, RecoveryProduction recoveryProduction,
                      RecoveryOccurrence recoveryOccurrence) {
        this.kind = kind;
        this.line = line;
        this.column = column;
        this.message = message != null ? message : "";
        this.messageAnsi = messageAnsi != null ? messageAnsi : "";
        this.unexpectedToken = unexpectedToken;
        this.expectedTokens = expectedTokens != null ? Collections.unmodifiableList(expectedTokens) : Collections.emptyList();
        this.context = context != null ? Collections.unmodifiableList(context) : Collections.emptyList();
        this.syntaxErrorCount = syntaxErrorCount;
        this.indentation = indentation;
        this.recoveryKind = recoveryKind;
        this.recoveryTerminal = recoveryTerminal;
        this.recoveryResume = recoveryResume;
        this.recoveryLhsVariable = recoveryLhsVariable;
        this.recoveryProduction = recoveryProduction;
        this.recoveryOccurrence = recoveryOccurrence;
    }

    public int getKind() { return kind; }
    public int getLine() { return line; }
    public int getColumn() { return column; }
    public String getMessage() { return message; }
    public String getMessageAnsi() { return messageAnsi; }
    public byte[] getUnexpectedToken() { return unexpectedToken; }
    public List<byte[]> getExpectedTokens() { return expectedTokens; }
    public List<String> getContext() { return context; }
    public int getSyntaxErrorCount() { return syntaxErrorCount; }
    public int[] getIndentation() { return indentation; }
    public Integer getRecoveryKind() { return recoveryKind; }
    public byte[] getRecoveryTerminal() { return recoveryTerminal; }
    public Integer getRecoveryResume() { return recoveryResume; }
    public String getRecoveryLhsVariable() { return recoveryLhsVariable; }
    public RecoveryProduction getRecoveryProduction() { return recoveryProduction; }
    public RecoveryOccurrence getRecoveryOccurrence() { return recoveryOccurrence; }

    // Convenience aliases matching Python's attribute names for direct port
    public String message() { return message; }
    public String messageAnsi() { return messageAnsi; }
    public byte[] unexpectedToken() { return unexpectedToken; }
    public List<byte[]> expectedTokens() { return expectedTokens; }

    @Override
    public String toString() {
        return "Diagnostic{kind=" + kind + ", line=" + line + ", column=" + column + ", message='" + message + "'}";
    }
}
