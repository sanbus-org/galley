package org.sanbus.galley;

import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

/**
 * Runtime options for Session. Every field is optional: a null field makes
 * no setter call, so the core's default for that option stays in force. The
 * defaults live with the core's runtime API options
 * (docs/configuration.md#runtime-api-options). The core owns validation: a
 * value outside its option's domain is refused with
 * {@link Status#ERROR_INVALID_ARGUMENT}, which session creation throws as a
 * {@link GalleyException}.
 *
 * Domains: {@code maxErrors} and {@code recoveryWindow} are at least 1;
 * {@code verbosity} is at least 0; {@code syntaxErrorStackDepth} is at most
 * 64, where 0 means the generated default; {@code stackOverflowRecovery} is
 * accepted only where the parser's platform offers it;
 * {@code astPreallocationRatio} must be finite and non-negative, where 0
 * drops the scaled contribution; {@code astPreallocationCap} may be any
 * value the target's counts can hold.
 *
 * Message-override UTF-8 policy: text messages are encoded as UTF-8 once
 * at the boundary; raw-byte messages pass through unmodified with no
 * re-encoding. Override names are UTF-8.
 */
public final class SessionOptions {
    private final Integer maxErrors;
    private final Integer recoveryWindow;
    private final Boolean stackOverflowRecovery;
    private final Integer syntaxErrorStackDepth;
    private final Integer verbosity;
    private final Double astPreallocationRatio;
    private final Long astPreallocationCap;
    private final Map<String, byte[]> messageOverrides;

    private SessionOptions(Builder b) {
        this.maxErrors = b.maxErrors;
        this.recoveryWindow = b.recoveryWindow;
        this.stackOverflowRecovery = b.stackOverflowRecovery;
        this.syntaxErrorStackDepth = b.syntaxErrorStackDepth;
        this.verbosity = b.verbosity;
        this.astPreallocationRatio = b.astPreallocationRatio;
        this.astPreallocationCap = b.astPreallocationCap;
        Map<String, byte[]> overrides = new HashMap<>();
        for (Map.Entry<String, byte[]> e : b.messageOverrides.entrySet()) overrides.put(e.getKey(), e.getValue().clone());
        this.messageOverrides = Collections.unmodifiableMap(overrides);
    }

    /** The chosen value, or null when the core's default stays in force. */
    public Integer getMaxErrors() { return maxErrors; }
    public Integer getRecoveryWindow() { return recoveryWindow; }
    public Boolean isStackOverflowRecovery() { return stackOverflowRecovery; }
    public Integer getSyntaxErrorStackDepth() { return syntaxErrorStackDepth; }
    public Integer getVerbosity() { return verbosity; }
    public Double getAstPreallocationRatio() { return astPreallocationRatio; }
    public Long getAstPreallocationCap() { return astPreallocationCap; }
    public Map<String, byte[]> getMessageOverrides() {
        Map<String, byte[]> copy = new HashMap<>();
        for (Map.Entry<String, byte[]> e : messageOverrides.entrySet()) copy.put(e.getKey(), e.getValue().clone());
        return Collections.unmodifiableMap(copy);
    }

    public static Builder builder() { return new Builder(); }

    public static final class Builder {
        private Integer maxErrors;
        private Integer recoveryWindow;
        private Boolean stackOverflowRecovery;
        private Integer syntaxErrorStackDepth;
        private Integer verbosity;
        private Double astPreallocationRatio;
        private Long astPreallocationCap;
        private final Map<String, byte[]> messageOverrides = new HashMap<>();

        public Builder maxErrors(int v) { this.maxErrors = v; return this; }
        public Builder recoveryWindow(int v) { this.recoveryWindow = v; return this; }
        public Builder stackOverflowRecovery(boolean v) { this.stackOverflowRecovery = v; return this; }
        public Builder syntaxErrorStackDepth(int v) { this.syntaxErrorStackDepth = v; return this; }
        public Builder verbosity(int v) { this.verbosity = v; return this; }
        public Builder astPreallocationRatio(double v) { this.astPreallocationRatio = v; return this; }
        public Builder astPreallocationCap(long v) { this.astPreallocationCap = v; return this; }
        /** Text message, encoded as UTF-8 once. Nulls are rejected loudly. */
        public Builder messageOverride(String name, String message) {
            if (name == null || message == null) throw new IllegalArgumentException("name and message required");
            return messageOverride(name, message.getBytes(StandardCharsets.UTF_8));
        }
        /** Raw-byte message, passed through unmodified. Nulls are rejected loudly. */
        public Builder messageOverride(String name, byte[] message) {
            if (name == null || message == null) throw new IllegalArgumentException("name and message required");
            this.messageOverrides.put(name, message.clone());
            return this;
        }
        public Builder messageOverrides(Map<String, String> m) {
            if (m == null) throw new IllegalArgumentException("message overrides is null");
            for (Map.Entry<String, String> e : m.entrySet()) messageOverride(e.getKey(), e.getValue());
            return this;
        }
        /** Bulk raw-byte overrides, passed through unmodified. Nulls are rejected loudly. */
        public Builder messageOverrideBytes(Map<String, byte[]> m) {
            if (m == null) throw new IllegalArgumentException("message overrides is null");
            for (Map.Entry<String, byte[]> e : m.entrySet()) messageOverride(e.getKey(), e.getValue());
            return this;
        }

        public SessionOptions build() { return new SessionOptions(this); }
    }
}
