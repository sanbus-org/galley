//! Parses a small key/value document through the Galley Rust bindings,
//! mirroring examples/c, examples/cpp, and examples/go byte-for-byte in
//! output.

use galley_bindings::{NodeHandle, Session};

const VALID_SAMPLE: &str = "alpha:12,beta:3";
const BROKEN_SAMPLE: &str = "alpha:";
const MULTI_ERROR_SAMPLE: &str = "alpha:13x,beta:,gamma:q";

fn print_tree(session: &Session, node: NodeHandle, depth: usize) {
    let name = session
        .symbol_name(node)
        .map(String::from_utf8_lossy)
        .unwrap_or_default();
    let text = session
        .text(node)
        .map(String::from_utf8_lossy)
        .unwrap_or_default();
    let (line, _) = session.line_column(node).unwrap_or((0, 0));

    for _ in 0..depth {
        print!("  ");
    }
    println!("{name} [line {line}, {} bytes]", text.len());

    for child in session.children(node) {
        print_tree(session, child, depth + 1);
    }
}

fn main() {
    println!("galley version: {}", galley_bindings::version());
    let mut session = match Session::with_options(Default::default()) {
        Ok(session) => session,
        Err(_) => {
            eprintln!("failed to create a parser session");
            std::process::exit(1);
        }
    };

    // With a path argument: parse the file and nothing else.
    let args: Vec<String> = std::env::args().collect();
    if args.len() > 1 {
        match session.parse_file(&args[1]) {
            Ok(bytes) => println!("parsed {bytes} bytes"),
            Err(e) => {
                if let Some(d) = session.diagnostic() {
                    eprintln!("{}:{}:{}: {}", args[1], d.line, d.column, d.message);
                } else {
                    eprintln!("parse failed: {e}");
                }
                std::process::exit(1);
            }
        }
        return;
    }

    /* Successful parse: walk the tree. */
    let parsed = match session.parse_sentinel(VALID_SAMPLE) {
        Ok(parsed) => parsed,
        Err(e) => {
            eprintln!("unexpected failure: {e}");
            std::process::exit(1);
        }
    };
    println!("parsed {parsed} bytes, {} AST nodes", session.node_count());
    if !galley_bindings::has_ast() {
        println!("AST construction disabled; skipping tree walk");
    } else {
        let root = match session.root_node() {
            Some(root) => root,
            None => {
                eprintln!("expected a root node");
                std::process::exit(1);
            }
        };
        print_tree(&session, root, 1);
    }

    /* Failed parse: inspect the diagnostic. */
    if session.parse_sentinel(BROKEN_SAMPLE).is_ok() {
        eprintln!("expected the broken sample to fail");
        std::process::exit(1);
    }
    let diagnostic = match session.diagnostic() {
        Some(diagnostic) => diagnostic,
        None => {
            eprintln!("expected a diagnostic for the broken sample");
            std::process::exit(1);
        }
    };
    println!(
        "diagnostic at {}:{}: {}",
        diagnostic.line, diagnostic.column, diagnostic.message
    );
    print!("expected one of: ");
    for (index, token) in diagnostic.expected_tokens.iter().enumerate() {
        if index != 0 {
            print!(", ");
        }
        print!("'{}'", String::from_utf8_lossy(token));
    }
    println!();
    print!("while parsing (innermost first):");
    for name in &diagnostic.context {
        print!(" {name}");
    }
    println!();

    /* Multi-error parse: every recorded diagnostic stays addressable. */
    if session.parse_sentinel(MULTI_ERROR_SAMPLE).is_ok() {
        eprintln!("expected the multi-error sample to fail");
        std::process::exit(1);
    }
    let diagnostics = session.diagnostics();
    println!("recorded diagnostics: {}", diagnostics.len());
    for (index, d) in diagnostics.iter().enumerate() {
        let kind_name = match d.kind {
            galley_bindings::DiagnosticKind::Syntax => "syntax",
            galley_bindings::DiagnosticKind::Indentation => "indentation",
            _ => "none",
        };
        let unexpected = String::from_utf8_lossy(&d.unexpected_token);
        println!(
            "  [{index}] {kind_name} at {}:{} near '{unexpected}'",
            d.line, d.column
        );
    }

    /* File parsing. */
    let path = "/tmp/galley-rust-example.json";
    if std::fs::write(path, VALID_SAMPLE).is_err() {
        eprintln!("failed to write {path}");
        std::process::exit(1);
    }
    let parsed = match session.parse_file(path) {
        Ok(parsed) => parsed,
        Err(e) => {
            eprintln!("file parse failed: {e}");
            std::process::exit(1);
        }
    };
    let info = session.info().expect("parse info");
    let (end_line, end_column) = info.end_position.unwrap_or((0, 0));
    println!("file parse: {parsed} bytes, ended at {end_line}:{end_column}");

    /* Tree editing: detach the root's children, then reattach them. */
    if galley_bindings::has_ast() {
        let root = match session.root_node() {
            Some(root) => root,
            None => {
                eprintln!("expected a root node");
                std::process::exit(1);
            }
        };
        let children_before = session.child_count(root);
        let head = match session.tree_clean_children(root) {
            Ok(Some(head)) => head,
            Ok(None) => {
                eprintln!("expected the root to have children");
                std::process::exit(1);
            }
            Err(e) => {
                eprintln!("failed to clean children: {e}");
                std::process::exit(1);
            }
        };
        if let Err(e) = session.tree_append_children(root, head) {
            eprintln!("failed to reattach children: {e}");
            std::process::exit(1);
        }
        println!(
            "tree edit: {children_before} children before, {} after reattach",
            session.child_count(root)
        );
    }
}
