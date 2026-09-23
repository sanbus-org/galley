package org.sanbus.galley;

/**
 * Shared digit scan for procedure-hook implementations: {@code -1} when
 * the text holds no digits, otherwise the digit value capped so huge
 * inputs can never overflow an {@code int}. The single implementation of
 * this rule — every hook copy delegates here instead of pasting its own
 * loop.
 */
public final class HookDigits {
    private HookDigits() {}

    public static int cappedDigits(String text) {
        int value = 0;
        boolean hasDigits = false;
        for (int i = 0; i < text.length() && value <= 999; i++) {
            char c = text.charAt(i);
            if (c >= '0' && c <= '9') {
                hasDigits = true;
                value = value * 10 + (c - '0');
            }
        }
        return hasDigits ? value : -1;
    }
}
