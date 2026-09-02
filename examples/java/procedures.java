// Procedure hooks for the keyvalue grammar.
//
// Shows ProcedureArguments in action: the current node, its text, children,
// and source position, plus dropIfEmpty on empty tails. Author-defined
// grammar hooks arrive as hook_<name> — Key is annotated @print.
//
// This file is the Java counterpart of examples/python/procedures.py,
// examples/go/demo/procedures.go, examples/rust/procedures.rs, and
// examples/typescript/procedures.ts. Hooks are registered at runtime via
// org.sanbus.galley.Procedures.installProcedure; the file's existence
// next to the grammar triggers the build tool to generate the Zig shim
// (procedures_java.zig) that dispatches through those registrations.

import org.sanbus.galley.Node;
import org.sanbus.galley.ProcedureArguments;
import org.sanbus.galley.Procedures;

import java.nio.charset.StandardCharsets;

public final class procedures {

    private procedures() {}

    private static String textOf(Node node) {
        byte[] b = node.text();
        return b == null ? "" : new String(b, StandardCharsets.UTF_8);
    }

    private static String nameOf(Node node) {
        byte[] b = node.symbolName();
        return b == null ? "" : new String(b, StandardCharsets.UTF_8);
    }

    private static int[] posOf(Node node) {
        int[] p = node.lineColumn();
        return p != null ? p : new int[]{0, 0};
    }

    private static int parseU(String text) {
        int value = 0;
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c >= '0' && c <= '9') value = value * 10 + (c - '0');
        }
        return value;
    }

    private static int[] countPairs(Node node) {
        if ("Pair".equals(nameOf(node))) {
            String text = textOf(node);
            int colon = text.indexOf(':');
            String number = colon >= 0 ? text.substring(colon + 1) : "";
            return new int[]{1, parseU(number)};
        }
        int count = 0, total = 0;
        for (Node child : node) {
            int[] childRes = countPairs(child);
            count += childRes[0];
            total += childRes[1];
        }
        return new int[]{count, total};
    }

    private static void emit(String line) {
        System.err.println(line);
    }

    public static void reduction(ProcedureArguments args) {}

    public static void reduction_Key(ProcedureArguments args) {}

    public static void reduction_PairList(ProcedureArguments args) {}

    public static void reduction_KeyTail(ProcedureArguments args) {
        args.dropIfEmpty();
    }

    public static void reduction_NumberTail(ProcedureArguments args) {
        args.dropIfEmpty();
    }

    public static void reduction_PairListTail(ProcedureArguments args) {
        args.dropIfEmpty();
    }

    public static void hook_print(ProcedureArguments args) {
        Node node = args.currentNode();
        if (node == null) return;
        int[] pos = posOf(node);
        emit("@print \"" + textOf(node) + "\" at " + pos[0] + ":" + pos[1]);
    }

    public static void reduction_Number(ProcedureArguments args) {
        Node node = args.currentNode();
        if (node == null) return;
        int[] pos = posOf(node);
        emit("Number " + textOf(node) + " at " + pos[0] + ":" + pos[1]);
    }

    public static void reduction_Pair(ProcedureArguments args) {
        Node node = args.currentNode();
        if (node == null) return;
        int[] pos = posOf(node);
        String text = textOf(node);
        int colon = text.indexOf(':');
        String key = colon >= 0 ? text.substring(0, colon) : text;
        String number = colon >= 0 ? text.substring(colon + 1) : "";
        emit("Pair " + key + "=" + number + " (" + node.length() + " children) at " + pos[0] + ":" + pos[1]);
    }

    public static void reduction_Document(ProcedureArguments args) {
        Node node = args.currentNode();
        if (node == null) return;
        int[] res = countPairs(node);
        emit("Document " + res[0] + " pairs, sum=" + res[1]);
    }

    // Register all hooks. Called from Demo at startup.
    public static void register() {
        Procedures.installProcedure("reduction", procedures::reduction);
        Procedures.installProcedure("reduction_Key", procedures::reduction_Key);
        Procedures.installProcedure("reduction_PairList", procedures::reduction_PairList);
        Procedures.installProcedure("reduction_KeyTail", procedures::reduction_KeyTail);
        Procedures.installProcedure("reduction_NumberTail", procedures::reduction_NumberTail);
        Procedures.installProcedure("reduction_PairListTail", procedures::reduction_PairListTail);
        Procedures.installProcedure("hook_print", procedures::hook_print);
        Procedures.installProcedure("reduction_Number", procedures::reduction_Number);
        Procedures.installProcedure("reduction_Pair", procedures::reduction_Pair);
        Procedures.installProcedure("reduction_Document", procedures::reduction_Document);
    }
}
