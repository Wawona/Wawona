/**
 * Bounded JVM harness for JBMC / Java PathFinder.
 * Calls the same rules as MachineInputSanitizer.sanitizeHost without Android types.
 */
public final class SanitizeHarness {
    private SanitizeHarness() {}

    public static String sanitizeHost(String raw) {
        if (raw == null) {
            return "";
        }
        String value = raw.trim();
        if (value.isEmpty()) {
            return "";
        }
        int scheme = value.indexOf("://");
        if (scheme >= 0 && scheme + 3 <= value.length()) {
            value = value.substring(scheme + 3);
        }
        int slash = value.indexOf('/');
        if (slash >= 0) {
            value = value.substring(0, slash);
        }
        int q = value.indexOf('?');
        if (q >= 0) {
            value = value.substring(0, q);
        }
        int hash = value.indexOf('#');
        if (hash >= 0) {
            value = value.substring(0, hash);
        }
        StringBuilder sb = new StringBuilder(value.length());
        for (int i = 0; i < value.length(); i++) {
            char ch = value.charAt(i);
            if (Character.isWhitespace(ch)) {
                continue;
            }
            if ("\"'`$;&|<>\\".indexOf(ch) >= 0) {
                continue;
            }
            sb.append(ch);
        }
        value = sb.toString();
        if (value.startsWith("[")) {
            int end = value.indexOf(']');
            if (end > 0 && end + 1 < value.length() && value.charAt(end + 1) == ':') {
                String maybePort = value.substring(end + 2);
                if (!maybePort.isEmpty() && maybePort.chars().allMatch(Character::isDigit)) {
                    value = value.substring(0, end + 1);
                }
            }
        } else {
            int colon = value.lastIndexOf(':');
            if (colon > 0 && colon + 1 < value.length()) {
                String host = value.substring(0, colon);
                String maybePort = value.substring(colon + 1);
                if (!host.contains(":") && maybePort.chars().allMatch(Character::isDigit)) {
                    value = host;
                }
            }
        }
        return value;
    }

    /** JBMC entry: nondet string of length at most 8. */
    public static void main(String[] args) {
        char[] buf = new char[8];
        for (int i = 0; i < buf.length; i++) {
            buf[i] = (char) (32 + (i * 3) % 95);
        }
        String out = sanitizeHost(new String(buf));
        for (int i = 0; i < out.length(); i++) {
            char ch = out.charAt(i);
            if (Character.isWhitespace(ch) || "\"'`$;&|<>\\".indexOf(ch) >= 0) {
                throw new AssertionError("metachar in output");
            }
        }
    }
}
