//! Build-script helper for consuming a Galley-generated parser from Rust.
//!
//! Call [`generate_and_link`] from your `build.rs` with the directory that
//! contains your grammar (`ll.grm`) and optional `galley.json`:
//!
//! ```no_run
//! // build.rs
//! fn main() {
//!     galley_bindings::build_helper::generate_and_link("language-dir");
//! }
//! ```
//!
//! The helper resolves Galley (`GALLEY_CHECKOUT` env var wins; otherwise it
//! shallow-clones `GALLEY_REPOSITORY` at `GALLEY_TAG`, skipping submodules),
//! builds the generator CLI, generates the parser, compiles the C-API shared
//! library, and emits the cargo directives that link your binary against it.
//! When the language directory contains a generated `procedures.zig` and a
//! `procedures.c` implementing its hooks, both are compiled into the shared
//! library — mirroring the C and C++ consumers' contract.

use std::path::{Path, PathBuf};
use std::process::Command;

const GALLEY_REPOSITORY: &str = "https://github.com/sanbus-org/galley.git";

/// Resolved locations produced (or reused) by this helper.
pub struct GalleyLayout {
    /// The Galley checkout used (fetched copy or `GALLEY_CHECKOUT`).
    pub source_dir: PathBuf,
    /// Shared library file (`lib<name>.dylib` / `.so`).
    pub library: PathBuf,
    /// Installed header location, for reference.
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

fn resolve_galley(out_dir: &Path) -> PathBuf {
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

    let tag = env("GALLEY_TAG").unwrap_or_else(|| "main".into());
    let repository = env("GALLEY_REPOSITORY").unwrap_or_else(|| GALLEY_REPOSITORY.into());
    println!("cargo:rerun-if-env-changed=GALLEY_REPOSITORY");
    println!("cargo:rerun-if-env-changed=GALLEY_TAG");

    let source_dir = out_dir.join("galley-src");
    let stamp = out_dir.join("galley-tag");
    let git = |args: &[&str]| {
        let mut c = Command::new("git");
        c.args(args);
        run_or_panic(c)
    };

    if source_dir.exists() {
        // Reuse an earlier fetch; refresh only when GALLEY_TAG changed.
        let stamp = out_dir.join("galley-tag");
        let previous = std::fs::read_to_string(&stamp).unwrap_or_default();
        if previous.trim_end() == tag {
            return source_dir;
        }
    }
    let _ = std::fs::remove_dir_all(&source_dir);
    git(&[
        "clone",
        "--depth",
        "1",
        "--branch",
        &tag,
        "--single-branch",
        "--recurse-submodules=false",
        &repository,
        source_dir.to_str().expect("non-utf8 OUT_DIR"),
    ]);
    std::fs::write(&stamp, &tag).expect("write galley tag stamp");
    source_dir
}

/// Generates the parser for `language_dir` (must contain `ll.grm` and an
/// optional `galley.json`) and emits cargo directives linking the current
/// crate's binary against the resulting shared library.
///
/// Environment overrides: `GALLEY_CHECKOUT`, `GALLEY_REPOSITORY`,
/// `GALLEY_TAG`. The library is always built in ReleaseFast.
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
        language_dir.join("galley.json").display()
    );

    let out_dir = PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR unset"));
    let galley_source = resolve_galley(&out_dir);

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
             point GALLEY_CHECKOUT at a current Galley checkout, or remove the stale copy and \
             update GALLEY_TAG so a fresh Galley is fetched",
            galley_source.display()
        );
    }

    // Generate the parser into the language directory.
    // All generation options come from galley.json in the language dir;
    // the CLI is invoked without flags so the config file owns them.
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
    let generated_parser = language_dir.join("_ll-parser.zig");
    println!("cargo:rerun-if-changed={}", generated_parser.display());

    // Hook implementations live next to the grammar: procedures.zig (the
    // generated extern declarations), procedures.c (the consumer's
    // implementations, compiled into the shared library), and an optional
    // ll_error_messages.zig with customized syntax-error message hooks.
    let procedures_zig = language_dir.join("procedures.zig");
    let procedures_c = language_dir.join("procedures.c");
    let error_messages_zig = language_dir.join("ll_error_messages.zig");

    // Compile the shared library through the generic consumer build file.
    let prefix = out_dir.join("galley-capi");
    let generated_absolute = generated_parser
        .canonicalize()
        .unwrap_or_else(|_| generated_parser.clone());
    run_or_panic({
        let mut c = Command::new(zig_executable());
        c.arg("build")
            .arg("--build-file")
            .arg(galley_source.join("bindings/c/consumer/build.zig"))
            .arg(format!("-Dparser-source={}", generated_absolute.display()))
            .arg("-Dparser-type=ll")
            .arg("-Dlib-name=galley-rust")
            .arg("-Doptimize=ReleaseFast")
            .arg("--prefix")
            .arg(&prefix)
            .arg("install")
            .current_dir(&galley_source);
        if procedures_zig.exists() {
            println!("cargo:rerun-if-changed={}", procedures_zig.display());
            c.arg(format!(
                "-Dprocedures-zig-source={}",
                procedures_zig
                    .canonicalize()
                    .unwrap_or(procedures_zig.clone())
                    .display()
            ));
        }
        if procedures_c.exists() {
            println!("cargo:rerun-if-changed={}", procedures_c.display());
            c.arg(format!(
                "-Dprocedures-c-source={}",
                procedures_c
                    .canonicalize()
                    .unwrap_or(procedures_c.clone())
                    .display()
            ));
        }
        if error_messages_zig.exists() {
            println!("cargo:rerun-if-changed={}", error_messages_zig.display());
            c.arg(format!(
                "-Derror-messages-zig-source={}",
                error_messages_zig
                    .canonicalize()
                    .unwrap_or(error_messages_zig.clone())
                    .display()
            ));
        }
        c
    });

    let library = if cfg!(target_os = "macos") {
        prefix.join("lib/libgalley-rust.dylib")
    } else {
        prefix.join("lib/libgalley-rust.so")
    };
    let include_dir = prefix.join("include");

    println!(
        "cargo:rustc-link-search=native={}",
        prefix.join("lib").display()
    );
    println!("cargo:rustc-link-lib=dylib=galley-rust");
    // Locate the dylib when the example runs from target/debug.
    println!(
        "cargo:rustc-link-arg=-Wl,-rpath,{}",
        prefix.join("lib").display()
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
