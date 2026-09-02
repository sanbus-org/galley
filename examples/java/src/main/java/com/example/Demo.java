package com.example;

import org.sanbus.galley.*;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/**
 * Parses a small key/value document through the Galley Java bindings,
 * mirroring examples/python/demo.py, examples/go/demo/demo.go,
 * examples/rust/src/demo.rs, and examples/typescript/demo.ts
 * byte-for-byte in output.
 */
public final class Demo {

    private static final String VALID_SAMPLE = "alpha:12,beta:3";
    private static final String BROKEN_SAMPLE = "alpha:";
    private static final String MULTI_ERROR_SAMPLE = "alpha:13x,beta:,gamma:q";
    private static final String SAMPLE_PATH = "/tmp/galley-java-example.json";

    private Demo() {}

    private static void printTree(Node node, int depth) {
        byte[] nameBytes = node.symbolName();
        byte[] textBytes = node.text();
        if (nameBytes == null || textBytes == null) System.exit(1);
        String name = new String(nameBytes, StandardCharsets.UTF_8);
        int line = 0;
        int[] pos = node.lineColumn();
        if (pos != null) line = pos[0];
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < depth; i++) sb.append("  ");
        sb.append(name).append(" [line ").append(line).append(", ").append(textBytes.length).append(" bytes]");
        System.out.println(sb);
        for (Node child : node) {
            printTree(child, depth + 1);
        }
    }

    public static void main(String[] args) throws Exception {
        // Register procedure hooks (mirrors Python's auto-import of procedures.py)
        try {
            // Try to load procedures class from same directory as grammar if available
            // The example's procedures.java is at the language-dir root; at runtime we
            // manually register them here. In a real consumer, call Procedures.installProcedure
            // for each hook you need.
            Class<?> procClass = Class.forName("procedures");
            procClass.getMethod("register").invoke(null);
        } catch (ClassNotFoundException ignored) {
            // Fallback: manually install via Demo-local hooks (none) - still try example's procedures
            // If not found on classpath, ensure the grammar's procedures.java was compiled with this demo
        } catch (Exception e) {
            System.err.println("failed to register procedures: " + e);
        }

        System.out.println("galley version: " + Galley.version());
        SessionOptions opts = SessionOptions.builder()
                .maxErrors(10)
                .messageOverride("Number", "expected a number after ':' (digits only) at line {line}")
                .build();
        Session session;
        try {
            session = new Session(opts);
        } catch (GalleyException e) {
            System.err.println("failed to create a parser session");
            System.exit(1);
            return;
        }

        try {
            // With a path argument: parse the file and nothing else.
            if (args.length > 0) {
                try {
                    int parsed = session.parseFile(args[0]);
                    System.out.println("parsed " + parsed + " bytes");
                    return;
                } catch (GalleyException e) {
                    Diagnostic d = e.getDiagnostic();
                    int line = d != null ? d.getLine() : 0;
                    int col = d != null ? d.getColumn() : 0;
                    String msg = d != null ? d.getMessage() : "";
                    System.err.println(args[0] + ":" + line + ":" + col + ": " + msg);
                    System.exit(1);
                    return;
                }
            }

            // Successful parse: walk the tree.
            int parsed;
            try {
                parsed = session.parseSentinel(VALID_SAMPLE);
            } catch (GalleyException e) {
                System.err.println("unexpected failure: " + e + " (" + e.getCode() + ")");
                System.exit(1);
                return;
            }
            System.out.println("parsed " + parsed + " bytes, " + session.nodeCount() + " AST nodes");
            if (!Galley.hasAst()) {
                System.out.println("AST construction disabled; skipping tree walk");
            } else {
                Node root = session.rootNode();
                if (root != null) printTree(root, 1);
            }

            // Failed parse: inspect the diagnostic.
            try {
                session.parseSentinel(BROKEN_SAMPLE);
                System.err.println("expected the broken sample to fail");
                System.exit(1);
                return;
            } catch (GalleyException e) {
                // expected
            }
            Diagnostic diagnostic = session.diagnostic();
            if (diagnostic == null) {
                System.err.println("expected a diagnostic for the broken sample");
                System.exit(1);
                return;
            }
            System.out.println("diagnostic at " + diagnostic.getLine() + ":" + diagnostic.getColumn() + ": " + diagnostic.getMessage());

            StringBuilder expected = new StringBuilder("expected one of: ");
            List<byte[]> tokens = diagnostic.getExpectedTokens();
            for (int i = 0; i < tokens.size(); i++) {
                if (i != 0) expected.append(", ");
                expected.append("'").append(new String(tokens.get(i), StandardCharsets.UTF_8)).append("'");
            }
            System.out.println(expected);

            StringBuilder context = new StringBuilder("while parsing (innermost first):");
            for (String name : diagnostic.getContext()) context.append(" ").append(name);
            System.out.println(context);

            // Multi-error parse
            try {
                session.parse(MULTI_ERROR_SAMPLE.getBytes(StandardCharsets.UTF_8));
                System.err.println("expected the multi-error sample to fail");
                System.exit(1);
                return;
            } catch (GalleyException ignored) {}
            List<Diagnostic> recorded = session.diagnostics();
            System.out.println("recorded diagnostics: " + recorded.size());
            for (int i = 0; i < recorded.size(); i++) {
                Diagnostic d = recorded.get(i);
                String kindName = d.getKind() == Diagnostic.KIND_SYNTAX ? "syntax" : d.getKind() == Diagnostic.KIND_INDENTATION ? "indentation" : "none";
                String unexpected = d.getUnexpectedToken() != null ? new String(d.getUnexpectedToken(), StandardCharsets.UTF_8) : "";
                System.out.println("  [" + i + "] " + kindName + " at " + d.getLine() + ":" + d.getColumn() + " near '" + unexpected + "'");
            }

            // File parsing
            Path tmp = Path.of(SAMPLE_PATH);
            Files.writeString(tmp, VALID_SAMPLE, StandardCharsets.UTF_8);
            try {
                parsed = session.parseFile(SAMPLE_PATH);
            } catch (GalleyException e) {
                System.err.println("file parse failed: " + e + " (" + e.getCode() + ")");
                System.exit(1);
                return;
            }
            int[] pos = session.lastPosition();
            if (pos == null) {
                System.err.println("expected a position after file parse");
                System.exit(1);
                return;
            }
            System.out.println("file parse: " + parsed + " bytes, ended at " + pos[0] + ":" + pos[1]);

            // Tree editing
            if (Galley.hasAst()) {
                Node root = session.rootNode();
                if (root == null) {
                    System.err.println("expected the root to have children");
                    System.exit(1);
                    return;
                }
                int childrenBefore = root.length();
                Node head = root.cleanChildren();
                if (head == null) {
                    System.err.println("expected the root to have children");
                    System.exit(1);
                    return;
                }
                root.appendChildren(head);
                System.out.println("tree edit: " + childrenBefore + " children before, " + root.length() + " after reattach");
            }

        } finally {
            session.close();
        }
    }
}
