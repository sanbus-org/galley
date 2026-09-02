package org.sanbus.galley;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

/**
 * Runtime options for Session. Mirrors GalleyCOptions in galley.h and
 * SessionOptions in Rust/Go/Python/TypeScript.
 */
public final class SessionOptions {
    private final int maxErrors;
    private final int recoveryWindow;
    private final boolean stackOverflowRecovery;
    private final int syntaxErrorStackDepth;
    private final int verbosity;
    private final double astPreallocationRatio;
    private final long astPreallocationCap;
    private final Map<String, String> messageOverrides;
    private final String libraryPath;

    private SessionOptions(Builder b) {
        this.maxErrors = b.maxErrors;
        this.recoveryWindow = b.recoveryWindow;
        this.stackOverflowRecovery = b.stackOverflowRecovery;
        this.syntaxErrorStackDepth = b.syntaxErrorStackDepth;
        this.verbosity = b.verbosity;
        this.astPreallocationRatio = b.astPreallocationRatio;
        this.astPreallocationCap = b.astPreallocationCap;
        this.messageOverrides = Collections.unmodifiableMap(new HashMap<>(b.messageOverrides));
        this.libraryPath = b.libraryPath;
    }

    public int getMaxErrors() { return maxErrors; }
    public int getRecoveryWindow() { return recoveryWindow; }
    public boolean isStackOverflowRecovery() { return stackOverflowRecovery; }
    public int getSyntaxErrorStackDepth() { return syntaxErrorStackDepth; }
    public int getVerbosity() { return verbosity; }
    public double getAstPreallocationRatio() { return astPreallocationRatio; }
    public long getAstPreallocationCap() { return astPreallocationCap; }
    public Map<String, String> getMessageOverrides() { return messageOverrides; }
    public String getLibraryPath() { return libraryPath; }

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
        private final Map<String, String> messageOverrides = new HashMap<>();
        private String libraryPath = null;

        public Builder maxErrors(int v) { this.maxErrors = v; return this; }
        public Builder recoveryWindow(int v) { this.recoveryWindow = v; return this; }
        public Builder stackOverflowRecovery(boolean v) { this.stackOverflowRecovery = v; return this; }
        public Builder syntaxErrorStackDepth(int v) { this.syntaxErrorStackDepth = v; return this; }
        public Builder verbosity(int v) { this.verbosity = v; return this; }
        public Builder astPreallocationRatio(double v) { this.astPreallocationRatio = v; return this; }
        public Builder astPreallocationCap(long v) { this.astPreallocationCap = v; return this; }
        public Builder messageOverride(String name, String message) { this.messageOverrides.put(name, message); return this; }
        public Builder messageOverrides(Map<String, String> m) { this.messageOverrides.putAll(m); return this; }
        public Builder libraryPath(String p) { this.libraryPath = p; return this; }

        public SessionOptions build() { return new SessionOptions(this); }
    }
}
