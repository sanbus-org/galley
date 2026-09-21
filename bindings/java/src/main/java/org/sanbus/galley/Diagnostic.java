package org.sanbus.galley;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Read-only snapshot of a parse diagnostic, mirroring Python's Diagnostic
 * and the C API's recorded diagnostics.
 *
 * Frozen at raise time: every array is deep-copied on construction and
 * every getter returns a copy, so later parses — and callers — cannot
 * mutate a diagnostic carried by a {@link GalleyException}.
 */
public final class Diagnostic {
    private final DiagnosticKind kind;
    private final int line;
    private final int column;
    private final String message;
    private final String messageAnsi;
    private final byte[] unexpectedToken; // nullable
    private final List<byte[]> expectedTokens;
    private final List<String> context;
    private final List<byte[]> contextBytes;
    private final int syntaxErrorCount;
    private final int semanticErrorCount;
    private final String[] semantic; // nullable: [variable, message]
    private final int[] indentation; // nullable: [spaces, width]
    private final RecoveryTarget recoveryKind;
    private final byte[] recoveryTerminal;
    private final ResumeSide recoveryResume;
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

    private static List<byte[]> copyBytes(List<byte[]> values) {
        if (values == null) return Collections.emptyList();
        List<byte[]> out = new ArrayList<>(values.size());
        for (byte[] value : values) out.add(value != null ? value.clone() : null);
        return out;
    }

    public Diagnostic(DiagnosticKind kind, int line, int column, String message, String messageAnsi,
                      byte[] unexpectedToken, List<byte[]> expectedTokens, List<String> context,
                      List<byte[]> contextBytes,
                      int syntaxErrorCount, int semanticErrorCount, String[] semantic, int[] indentation,
                      RecoveryTarget recoveryKind, byte[] recoveryTerminal, ResumeSide recoveryResume,
                      String recoveryLhsVariable, RecoveryProduction recoveryProduction,
                      RecoveryOccurrence recoveryOccurrence) {
        this.kind = kind != null ? kind : DiagnosticKind.UNKNOWN;
        this.line = line;
        this.column = column;
        this.message = message != null ? message : "";
        this.messageAnsi = messageAnsi != null ? messageAnsi : "";
        this.unexpectedToken = unexpectedToken != null ? unexpectedToken.clone() : null;
        this.expectedTokens = Collections.unmodifiableList(copyBytes(expectedTokens));
        this.context = context != null
                ? Collections.unmodifiableList(new ArrayList<>(context))
                : Collections.emptyList();
        this.contextBytes = Collections.unmodifiableList(copyBytes(contextBytes));
        this.syntaxErrorCount = syntaxErrorCount;
        this.semanticErrorCount = semanticErrorCount;
        this.semantic = semantic != null ? semantic.clone() : null;
        this.indentation = indentation != null ? indentation.clone() : null;
        this.recoveryKind = recoveryKind;
        this.recoveryTerminal = recoveryTerminal != null ? recoveryTerminal.clone() : null;
        this.recoveryResume = recoveryResume;
        this.recoveryLhsVariable = recoveryLhsVariable;
        this.recoveryProduction = recoveryProduction;
        this.recoveryOccurrence = recoveryOccurrence;
    }

    public DiagnosticKind getKind() { return kind; }
    public int getLine() { return line; }
    public int getColumn() { return column; }
    public String getMessage() { return message; }
    public String getMessageAnsi() { return messageAnsi; }
    public byte[] getUnexpectedToken() { return unexpectedToken != null ? unexpectedToken.clone() : null; }
    public List<byte[]> getExpectedTokens() { return Collections.unmodifiableList(copyBytes(expectedTokens)); }
    public List<String> getContext() { return context; }
    /** Raw bytes behind {@link #getContext()}, one entry per name. */
    public List<byte[]> getContextBytes() { return Collections.unmodifiableList(copyBytes(contextBytes)); }
    public int getSyntaxErrorCount() { return syntaxErrorCount; }
    public int getSemanticErrorCount() { return semanticErrorCount; }
    public String[] getSemantic() { return semantic != null ? semantic.clone() : null; }
    public int[] getIndentation() { return indentation != null ? indentation.clone() : null; }
    public RecoveryTarget getRecoveryKind() { return recoveryKind; }
    public byte[] getRecoveryTerminal() { return recoveryTerminal != null ? recoveryTerminal.clone() : null; }
    public ResumeSide getRecoveryResume() { return recoveryResume; }
    public String getRecoveryLhsVariable() { return recoveryLhsVariable; }
    public RecoveryProduction getRecoveryProduction() { return recoveryProduction; }
    public RecoveryOccurrence getRecoveryOccurrence() { return recoveryOccurrence; }

    // Python-doc attribute names; not unused duplicates of the getters.
    public String message() { return message; }
    public String messageAnsi() { return messageAnsi; }
    public byte[] unexpectedToken() { return getUnexpectedToken(); }
    public List<byte[]> expectedTokens() { return getExpectedTokens(); }

    @Override
    public String toString() {
        return "Diagnostic{kind=" + kind + ", line=" + line + ", column=" + column + ", message='" + message + "'}";
    }
}
