package org.sanbus.galley;

import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

/**
 * Runtime options for Session. Mirrors GalleyCOptions in galley.h.
 *
 * Message-override UTF-8 policy: text messages are encoded as UTF-8 once
 * at the boundary; raw-byte messages pass through unmodified with no
 * re-encoding. Override names are UTF-8.
 */
public final class SessionOptions {
    private final int maxErrors;
    private final int recoveryWindow;
    private final boolean stackOverflowRecovery;
    private final int syntaxErrorStackDepth;
    private final int verbosity;
    private final double astPreallocationRatio;
    private final long astPreallocationCap;
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

    public int getMaxErrors() { return maxErrors; }
    public int getRecoveryWindow() { return recoveryWindow; }
    public boolean isStackOverflowRecovery() { return stackOverflowRecovery; }
    public int getSyntaxErrorStackDepth() { return syntaxErrorStackDepth; }
    public int getVerbosity() { return verbosity; }
    public double getAstPreallocationRatio() { return astPreallocationRatio; }
    public long getAstPreallocationCap() { return astPreallocationCap; }
    public Map<String, byte[]> getMessageOverrides() {
        Map<String, byte[]> copy = new HashMap<>();
        for (Map.Entry<String, byte[]> e : messageOverrides.entrySet()) copy.put(e.getKey(), e.getValue().clone());
        return Collections.unmodifiableMap(copy);
    }

    public static Builder builder() { return new Builder(); }

    public static SessionOptions defaults() { return builder().build(); }

    public static final class Builder {
        private int maxErrors = 10;
        private int recoveryWindow = 500;
        private boolean stackOverflowRecovery = false;
        private int syntaxErrorStackDepth = 0;
        private int verbosity = 0;
        private double astPreallocationRatio = -1.0;
        private long astPreallocationCap = 0;
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
