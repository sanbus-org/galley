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

    /* Successful parse: walk the tree. */
    let valid_sample = "alpha:12,beta:3";
    let parsed = session
        .parse_sentinel(valid_sample)
        .expect("unexpected failure");
    println!("parsed {parsed} bytes, {} AST nodes", session.node_count());
    if !galley_bindings::has_ast() {
        println!("AST construction disabled; skipping tree walk");
    } else if let Some(root) = session.root_node() {
        print_tree(&session, root, 1);
    }

    /* Failed parse: inspect the diagnostic. */
    session
        .parse_sentinel("alpha:")
        .expect_err("expected the broken sample to fail");
    let diagnostic = session.diagnostic().expect("diagnostic");
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

    /* File parsing. */
    let path = "/tmp/galley-rust-example.json";
    std::fs::write(path, valid_sample).expect("failed to write sample file");
    let parsed = session.parse_file(path).expect("file parse failed");
    let info = session.info().expect("parse info");
    let (end_line, end_column) = info.end_position.unwrap_or((0, 0));
    println!("file parse: {parsed} bytes, ended at {end_line}:{end_column}");

    /* Tree editing: detach the root's children, then reattach them. */
    if galley_bindings::has_ast() {
        let root = session.root_node().expect("root node");
        let children_before = session.child_count(root);
        let head = session
            .tree_clean_children(root)
            .expect("clean children")
            .expect("expected the root to have children");
        session
            .tree_append_children(root, head)
            .expect("reattach children");
        println!(
            "tree edit: {children_before} children before, {} after reattach",
            session.child_count(root)
        );
    }
}
