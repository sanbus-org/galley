//! Build-script helper for consuming a Galley-generated parser from Rust.
//!
//! Call [`generate_and_link`] from your `build.rs` with the directory that
//! contains your grammar (`ll.grm`) and the language's `config.zig`:
//!
//! ```no_run
//! // build.rs
//! fn main() {
//!     galley_bindings::build_helper::generate_and_link("language-dir");
//! }
//! ```
//!
//! The helper requires `GALLEY_CHECKOUT` (an existing Galley working tree),
//! builds the generator CLI, generates the parser, compiles the C-API shared
//! library directly next to the grammar, and emits the cargo directives that
//! link your binary against it.
//! Hooks are written in Rust: when the language directory contains a
//! generated `procedures.zig` and a `procedures.rs` implementing its hooks,
//! the helper compiles `procedures.rs` with rustc into a static archive and
//! links it into the shared library — no C anywhere on the consumer side.

use std::path::{Path, PathBuf};
use std::process::Command;

/// Resolved locations produced (or reused) by this helper.
pub struct GalleyLayout {
    /// The Galley checkout used (`GALLEY_CHECKOUT`).
    pub source_dir: PathBuf,
    /// Shared library file next to the grammar (`lib<name>.dylib` / `.so`).
    pub library: PathBuf,
    /// Header directory in the checkout (`<galley>/bindings/c`).
    pub include_dir: PathBuf,
}

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

fn run_or_panic(mut command: Command) {
    let status = command.status().unwrap_or_else(|e| {
        panic!("failed to spawn {:?}: {e}", command.get_program());
    });
    if !status.success() {
        panic!("command failed: {:?}", command);
    }
}

fn resolve_galley() -> PathBuf {
    if let Some(checkout) = env("GALLEY_CHECKOUT") {
        let checkout = PathBuf::from(checkout);
        assert!(
            checkout.join("build.zig").exists(),
            "GALLEY_CHECKOUT={} is not a Galley repository checkout (no build.zig)",
            checkout.display()
        );
        println!("cargo:rerun-if-env-changed=GALLEY_CHECKOUT");
        return checkout;
    }
    panic!(
        "GALLEY_CHECKOUT is not set; point it at a Galley checkout \
         (examples/scripts/fetch-galley.sh can fetch one — that cache is an \
         examples-only convenience, not part of the bindings)"
    );
}

/// Generates the parser for `language_dir` (must contain `ll.grm` and the
/// language's `config.zig`) and emits cargo directives linking the current
/// crate's binary against the resulting shared library.
///
/// Requires `GALLEY_CHECKOUT`. The library is always built in ReleaseFast,
/// directly next to the grammar (`OUT_DIR` keeps only the procedures archive).
pub fn generate_and_link(language_dir: impl AsRef<Path>) -> GalleyLayout {
    let language_dir = language_dir.as_ref();
    assert!(
        language_dir.join("ll.grm").exists(),
        "{} does not contain ll.grm",
        language_dir.display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        language_dir.join("ll.grm").display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        language_dir.join("config.zig").display()
    );

    let out_dir = PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR unset"));
    let galley_source = resolve_galley();
    println!(
        "cargo:rerun-if-changed={}",
        galley_source.join("bindings/c/capi.zig").display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        galley_source.join("bindings/c/galley.h").display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        galley_source
            .join("bindings/c/consumer/build.zig")
            .display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        galley_source
            .join("bindings/rust/src/procedure.rs")
            .display()
    );

    let cli = galley_source.join("zig-out/bin/galley");
    if !cli.exists() {
        run_or_panic({
            let mut c = Command::new(zig_executable());
            c.arg("build")
                .arg("-Doptimize=ReleaseFast")
                .arg("install")
                .current_dir(&galley_source);
            c
        });
    }

    // Parser generation relies on CLI flags introduced alongside the
    // bindings workflow (--emit-metadata). Refuse with guidance when the
    // resolved Galley predates them instead of failing deep inside
    // generation.
    let help = Command::new(&cli)
        .arg("--help")
        .output()
        .unwrap_or_else(|e| panic!("failed to spawn {}: {e}", cli.display()));
    if !String::from_utf8_lossy(&help.stdout).contains("--emit-metadata") {
        panic!(
            "the Galley at {} is too old for the bindings workflow (no --emit-metadata support); \
             point GALLEY_CHECKOUT at a current Galley checkout",
            galley_source.display()
        );
    }

    // Generate the parser into the language directory.
    // All generation-time options come from config.zig in the language
    // dir; the CLI is invoked without flags so the config file owns them.
    // --emit-metadata also produces procedures.zig with the extern
    // declarations for every hook the grammar requires.
    run_or_panic({
        let language_dir = language_dir
            .canonicalize()
            .expect("canonicalize language dir");
        let mut c = Command::new(&cli);
        c.arg("--emit-metadata").arg(&language_dir);
        c
    });

    // Hook implementations live next to the grammar: procedures.zig (the
    // generated extern declarations), procedures.rs (the consumer's Rust
    // implementations, compiled here into a static archive and linked into
    // the shared library), and an optional ll_error_messages.zig /
    // lr_error_messages.zig with customized syntax-error message hooks.
    let procedures_zig = language_dir.join("procedures.zig");
    let procedures_rs = language_dir.join("procedures.rs");

    // One library embeds one parser; the consumer build locates the file
    // generation produced from the language dir and infers the family
    // from the filename.
    for candidate in ["_ll-parser.zig", "_lr-parser.zig"] {
        let path = language_dir.join(candidate);
        if path.exists() {
            println!("cargo:rerun-if-changed={}", path.display());
        }
    }
    for candidate in ["ll_error_messages.zig", "lr_error_messages.zig"] {
        let path = language_dir.join(candidate);
        if path.exists() {
            println!("cargo:rerun-if-changed={}", path.display());
        }
    }

    // Compile the shared library through the generic consumer build file,
    // directly next to the grammar.
    let language_absolute = language_dir
        .canonicalize()
        .unwrap_or_else(|_| language_dir.to_path_buf());
    let library_file: &str = if cfg!(target_os = "macos") {
        "libgalley-rust.dylib"
    } else {
        "libgalley-rust.so"
    };
    run_or_panic({
        let mut c = Command::new(zig_executable());
        c.arg("build")
            .arg("--build-file")
            .arg(galley_source.join("bindings/c/consumer/build.zig"))
            .arg(format!("-Dlanguage-dir={}", language_absolute.display()))
            .arg("-Dlib-name=galley-rust")
            .arg(format!("-Doutput={library_file}"))
            .arg("-Doptimize=ReleaseFast")
            .arg("--prefix")
            .arg(&language_absolute)
            .arg("install")
            .current_dir(&galley_source);
        if procedures_zig.exists() {
            println!("cargo:rerun-if-changed={}", procedures_zig.display());
        }
        // config.zig and {ll,lr}_error_messages.zig next to the parser are
        // inferred by the consumer build when omitted.
        if procedures_rs.exists() {
            println!("cargo:rerun-if-changed={}", procedures_rs.display());
            let archive = compile_procedures_archive(&procedures_rs, &out_dir);
            c.arg(format!("-Dprocedures-object={}", archive.display()));
        }
        let config_zig = language_dir.join("config.zig");
        if config_zig.exists() {
            println!("cargo:rerun-if-changed={}", config_zig.display());
        }
        c
    });

    let library = language_absolute.join(library_file);
    let include_dir = galley_source.join("bindings/c");

    println!(
        "cargo:rustc-link-search=native={}",
        language_absolute.display()
    );
    println!("cargo:rustc-link-lib=dylib=galley-rust");
    // Locate the dylib when the example runs from target/debug.
    // The path is absolute, so moving the folder afterwards breaks the link.
    println!(
        "cargo:rustc-link-arg=-Wl,-rpath,{}",
        language_absolute.display()
    );

    GalleyLayout {
        source_dir: galley_source,
        library,
        include_dir,
    }
}

fn zig_executable() -> String {
    env("ZIG_EXECUTABLE").unwrap_or_else(|| "zig".into())
}

/// Compiles the consumer's `procedures.rs` into a static archive with
/// rustc so the generic consumer build file can link it into the shared
/// library. `panic=abort` keeps unwinding from ever crossing the parser's
/// call frames: hooks are `extern "C"` functions, and a panic inside one
/// aborts the process rather than unwinding through generated Zig code.
fn compile_procedures_archive(source: &Path, out_dir: &Path) -> PathBuf {
    let archive = out_dir.join("libgalley_procedures.a");
    run_or_panic({
        let mut c = Command::new(env("RUSTC").unwrap_or_else(|| "rustc".into()));
        c.arg("--edition=2021")
            .arg("--crate-name=galley_procedures")
            .arg("--crate-type=staticlib")
            .arg("-Cpanic=abort")
            .arg("-Copt-level=3")
            .arg("-o")
            .arg(&archive)
            .arg(source);
        c
    });
    archive
}
