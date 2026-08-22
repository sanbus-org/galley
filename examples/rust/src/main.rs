use galley_bindings::{NodeHandle, Session};

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
    let mut session = Session::with_options(Default::default()).expect("session");

    // With a path argument: parse the file and nothing else.
    let args: Vec<String> = std::env::args().collect();
    if args.len() > 1 {
        match session.parse_file(&args[1]) {
            Ok(bytes) => println!("parsed {bytes} bytes"),
            Err(e) => {
                if let Some(d) = session.diagnostic() {
                    eprintln!(
                        "{}:{}:{}: {}\n{}",
                        args[1],
                        d.line,
                        d.column,
                        e.description(),
                        d.message
                    );
                } else {
                    eprintln!("parse failed: {e}");
                }
                std::process::exit(1);
            }
        }
        return;
    }

    // Demo: successful parse with a tree walk.
    let valid = "alpha:12,beta:3";
    let parsed = session.parse_sentinel(valid).expect("unexpected failure");
    println!("parsed {parsed} bytes, {} AST nodes", session.node_count());
    if !galley_bindings::has_ast() {
        println!("AST construction disabled; skipping tree walk");
    } else if let Some(root) = session.root_node() {
        print_tree(&session, root, 1);
    }

    // Demo: failed parse with the structured diagnostic.
    session
        .parse_sentinel("alpha:")
        .expect_err("expected the broken sample to fail");
    let diagnostic = session.diagnostic().expect("diagnostic");
    println!(
        "diagnostic at {}:{}: {}\nwhile parsing (innermost first): {:?}\nexpected: {:?}",
        diagnostic.line,
        diagnostic.column,
        diagnostic.message,
        diagnostic.context,
        diagnostic.expected_tokens
    );
}
