//! JSON throughput through the Galley Rust bindings: no AST, no procedures,
//! no error recovery. Parses languages/json/samples/code-01.json 50,000 times
//! on one session and reports bytes/s.

use galley_bindings::Session;
use std::path::{Path, PathBuf};
use std::time::Instant;

const LOGICAL_INPUT: &str = "languages/json/samples/code-01.json";
const DEFAULT_ITERATIONS: usize = 50_000;

fn resolve_input(explicit: Option<&str>) -> PathBuf {
    if let Some(path) = explicit {
        return PathBuf::from(path);
    }
    if let Ok(checkout) = std::env::var("GALLEY_CHECKOUT") {
        if !checkout.is_empty() {
            let candidate = Path::new(&checkout).join(LOGICAL_INPUT);
            if candidate.is_file() {
                return candidate;
            }
        }
    }
    let from_manifest = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .join(LOGICAL_INPUT);
    if from_manifest.is_file() {
        return from_manifest;
    }
    Path::new("../..").join(LOGICAL_INPUT)
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut iterations = DEFAULT_ITERATIONS;
    let explicit = args.first().map(String::as_str);
    if let Some(value) = args.get(1) {
        match value.parse::<usize>() {
            Ok(count) if count >= 1 => iterations = count,
            _ => {
                eprintln!("iterations must be >= 1");
                std::process::exit(1);
            }
        }
    }

    let path = resolve_input(explicit);
    let data = match std::fs::read_to_string(&path) {
        Ok(data) => data,
        Err(_) => {
            eprintln!("failed to read {LOGICAL_INPUT}");
            std::process::exit(1);
        }
    };

    let mut session = match Session::new() {
        Ok(session) => session,
        Err(_) => {
            eprintln!("failed to create a parser session");
            std::process::exit(1);
        }
    };

    match session.parse_sentinel(&data) {
        Ok(parsed) if parsed == data.len() => {}
        Ok(parsed) => {
            eprintln!(
                "warmup parse failed: parsed {parsed} of {} bytes",
                data.len()
            );
            std::process::exit(1);
        }
        Err(error) => {
            eprintln!("warmup parse failed: {error}");
            std::process::exit(1);
        }
    }

    let start = Instant::now();
    for index in 0..iterations {
        match session.parse_sentinel(&data) {
            Ok(parsed) if parsed == data.len() => {}
            Ok(parsed) => {
                eprintln!(
                    "parse failed at iteration {index}: parsed {parsed} of {} bytes",
                    data.len()
                );
                std::process::exit(1);
            }
            Err(error) => {
                eprintln!("parse failed at iteration {index}: {error}");
                std::process::exit(1);
            }
        }
    }
    let elapsed = start.elapsed().as_nanos();
    let total = data.len() as u128 * iterations as u128;
    let bps = if elapsed == 0 {
        0
    } else {
        total * 1_000_000_000 / elapsed
    };

    println!("input: {LOGICAL_INPUT}");
    println!("bytes: {}", with_thousands(data.len() as u128));
    println!("iterations: {}", with_thousands(iterations as u128));
    println!("parsed_bytes: {}", with_thousands(total));
    println!("duration_ns: {}", with_thousands(elapsed));
    println!("bytes_per_second: {}", with_thousands(bps));
}

fn with_thousands(n: u128) -> String {
    let digits = n.to_string();
    let mut out = String::new();
    for (i, ch) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i) % 3 == 0 {
            out.push(',');
        }
        out.push(ch);
    }
    out
}
