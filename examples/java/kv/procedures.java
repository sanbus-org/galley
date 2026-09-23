// Procedure hooks for the keyvalue grammar.
//
// Shows ProcedureArguments in action: the current node, its text, children,
// and source position, plus dropIfEmpty on empty tails. Author-defined
// grammar hooks arrive as hook_<name> — Key is annotated @print.
//
// Hooks are registered at runtime via
// parser.installProcedure. The build tool always generates the dispatch
// shim from the metadata hook list; this file only supplies the hook
// implementations that registrations point at.

import org.sanbus.galley.HookDigits;
import org.sanbus.galley.Node;
import org.sanbus.galley.ProcedureArguments;

import java.nio.charset.StandardCharsets;

public final class procedures {

    private procedures() {}

    private static String textOf(Node node) {
        byte[] b = node.text();
        return b == null ? "" : new String(b, StandardCharsets.UTF_8);
    }

    private static String nameOf(Node node) {
        String name = node.symbolName();
        return name != null ? name : "";
    }

    private static int[] posOf(Node node) {
        int[] p = node.lineColumn();
        return p != null ? p : new int[]{0, 0};
    }

    private static int[] countPairs(Node node) {
        if ("Pair".equals(nameOf(node))) {
            String text = textOf(node);
            int colon = text.indexOf(':');
            String number = colon >= 0 ? text.substring(colon + 1) : "";
            return new int[]{1, Math.max(0, HookDigits.cappedDigits(number))};
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
        String text = textOf(node);
        emit("Number " + text + " at " + pos[0] + ":" + pos[1]);
        if (HookDigits.cappedDigits(text) > 999) {
            args.reportSemanticError("value out of range");
        }
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

    // Install all hooks. Called from Demo at startup.
    public static void register(org.sanbus.galley.Parser parser) {
        parser.installProcedure("reduction", procedures::reduction);
        parser.installProcedure("reduction_Key", procedures::reduction_Key);
        parser.installProcedure("reduction_PairList", procedures::reduction_PairList);
        parser.installProcedure("reduction_KeyTail", procedures::reduction_KeyTail);
        parser.installProcedure("reduction_NumberTail", procedures::reduction_NumberTail);
        parser.installProcedure("reduction_PairListTail", procedures::reduction_PairListTail);
        parser.installProcedure("hook_print", procedures::hook_print);
        parser.installProcedure("reduction_Number", procedures::reduction_Number);
        parser.installProcedure("reduction_Pair", procedures::reduction_Pair);
        parser.installProcedure("reduction_Document", procedures::reduction_Document);
    }
}
