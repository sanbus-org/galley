//! Parse throughput through the Galley Rust bindings: parses the given
//! sample on one session and reports bytes/s.

use galley::Session;
use std::path::PathBuf;
use std::time::Instant;

const DEFAULT_ITERATIONS: usize = 10;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() {
        eprintln!("usage: benchmark <sample-file> [iterations]");
        std::process::exit(1);
    }
    let path = PathBuf::from(&args[0]);
    let mut iterations = DEFAULT_ITERATIONS;
    if let Some(value) = args.get(1) {
        match value.parse::<usize>() {
            Ok(count) if count >= 1 => iterations = count,
            _ => {
                eprintln!("iterations must be >= 1");
                std::process::exit(1);
            }
        }
    }

    let data = match std::fs::read_to_string(&path) {
        Ok(data) => data,
        Err(_) => {
            eprintln!("failed to read {}", path.display());
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

    // The first two parses are cold: the session arena grows during the first and is reallocated for the second.
    for _ in 0..2 {
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

    println!("input: {}", path.display());
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
