//! Build-script helper for consuming a Galley-generated parser from Rust.
//!
//! Call [`generate_and_link`] from your `build.rs` with the directory that
//! contains your grammar (`ll.grm`) and the language's `config.zig`:
//!
//! ```no_run
//! // build.rs
//! fn main() {
//!     galley::build_helper::generate_and_link("language-dir");
//! }
//! ```
//!
//! No checkout is needed: the published crate carries the generator CLI
//! for every platform and the compile inputs (`compile-kit/`).
//! Contributors running from a Galley checkout without an assembled kit
//! fall back to `GALLEY_CHECKOUT` pointing at the checkout — for
//! convenience, `GALLEY_CHECKOUT=$(examples/scripts/fetch-galley.sh)`
//! fetches one into the system cache, but that cache is examples-only,
//! not part of the bindings.
//! The helper generates the parser, compiles the C-API shared
//! library directly next to the grammar, and emits the cargo directives that
//! link your binary against it.
//! Hooks are written in Rust: when the language directory contains a
//! generated `procedures.zig` and a `procedures.rs` implementing its hooks,
//! the helper compiles `procedures.rs` with rustc into a static archive and
//! links it into the shared library — no C anywhere on the consumer side.

use std::path::{Path, PathBuf};
use std::process::Command;

/// The hook-shim source (`src/procedure.rs`) every consumer `procedures.rs`
/// includes. Single source of truth: `generate_and_link` materializes this
/// exact text into the consumer build's `OUT_DIR`, so hook types always
/// match the `galley` crate version in use and no checkout paths leak into
/// consumer sources.
const PROCEDURE_RS: &str = include_str!("procedure.rs");

/// File name (under the consumer build's `OUT_DIR`) that
/// [`generate_and_link`] writes [`PROCEDURE_RS`] to. Consumer
/// `procedures.rs` files open it with:
///
/// ```ignore
/// mod procedure {
///     include!(concat!(env!("OUT_DIR"), "/galley_procedure_types.rs"));
/// }
/// ```
pub const PROCEDURE_TYPES_FILE: &str = "galley_procedure_types.rs";

/// Resolved locations produced (or reused) by this helper.
pub struct GalleyLayout {
    /// The Galley source root used (kit sources or `GALLEY_CHECKOUT`).
    pub source_dir: PathBuf,
    /// Shared library file next to the grammar (`lib<name>.dylib` / `.so`).
    pub library: PathBuf,
    /// C header directory (`<source root>/bindings/c`).
    pub include_dir: PathBuf,
}

/// Directory of the `galley` crate itself. Cargo sets this at compile
/// time, so shipped data (kit, generator) resolves with no environment
/// guessing and no checkout paths leaking into consumers.
const GALLEY_PACKAGE_DIR: &str = env!("CARGO_MANIFEST_DIR");

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

fn resolve_galley() -> Option<PathBuf> {
    let checkout = env("GALLEY_CHECKOUT")?;
    let checkout = PathBuf::from(checkout);
    if !checkout.join("build.zig").exists() {
        return None;
    }
    println!("cargo:rerun-if-env-changed=GALLEY_CHECKOUT");
    Some(checkout)
}

/// Where the consumer build and its sources live: the consumer build
/// file plus the source root its `@import("galley")` resolves against.
/// The published crate carries `compile-kit/` (no checkout needed);
/// contributors running from a checkout without an assembled kit fall
/// back to `GALLEY_CHECKOUT` holding `build.zig`. Anything else panics
/// loudly. Both legs run the same consumer build with the same flags;
/// only the inputs differ.
fn resolve_compile_inputs() -> (PathBuf, PathBuf) {
    let kit = PathBuf::from(GALLEY_PACKAGE_DIR).join("compile-kit");
    if kit.join("build.zig").exists() {
        return (kit.join("build.zig"), kit.join("sources"));
    }
    if let Some(checkout) = resolve_galley() {
        return (checkout.join("bindings/c/consumer/build.zig"), checkout);
    }
    panic!(
        "need compile inputs: the installed galley crate has no compile-kit/ \
         (reinstall it) or, when running from a Galley checkout, set GALLEY_CHECKOUT \
         at the checkout (must contain build.zig) or assemble the kit with \
         scripts/js/assemble_compile_kit.sh"
    );
}

/// Prebuilt generator CLI per platform: directory under `generator/`
/// holding the binary. riscv64 is deliberately skipped (no portable static
/// target); 32-bit and BSD platforms fail loudly through the error below.
fn generator_cli_relative() -> Option<&'static str> {
    match (std::env::consts::OS, std::env::consts::ARCH) {
        ("macos", "aarch64") => Some("cli-darwin-arm64/bin/galley"),
        ("macos", "x86_64") => Some("cli-darwin-x64/bin/galley"),
        ("linux", "x86_64") => Some("cli-linux-x64/bin/galley"),
        ("linux", "aarch64") => Some("cli-linux-arm64/bin/galley"),
        ("windows", "x86_64") => Some("cli-win32-x64/bin/galley.exe"),
        ("windows", "aarch64") => Some("cli-win32-arm64/bin/galley.exe"),
        _ => None,
    }
}

/// The generator CLI to run, without building anything. Explicit
/// `GALLEY_CLI` wins; then the shipped platform binary (present exactly
/// when the crate was installed with its generator data); then a checkout
/// bootstrap, which needs `GALLEY_CHECKOUT` and zig. Anything else panics
/// loudly naming every leg.
fn resolve_generator_cli() -> PathBuf {
    if let Some(explicit) = env("GALLEY_CLI") {
        let explicit = PathBuf::from(explicit);
        assert!(
            explicit.is_file(),
            "GALLEY_CLI={} does not exist",
            explicit.display()
        );
        println!("cargo:rerun-if-env-changed=GALLEY_CLI");
        return explicit;
    }
    if let Some(relative) = generator_cli_relative() {
        let shipped = PathBuf::from(GALLEY_PACKAGE_DIR)
            .join("generator")
            .join(relative);
        if shipped.is_file() {
            return shipped;
        }
    }
    if let Some(checkout) = resolve_galley() {
        let cli = checkout.join("zig-out/bin/galley");
        if !cli.exists() {
            run_or_panic({
                let mut c = Command::new(zig_executable());
                c.arg("build")
                    .arg("-Doptimize=ReleaseFast")
                    .arg("install")
                    .current_dir(&checkout);
                c
            });
        }
        return cli;
    }
    panic!(
        "no generator CLI found (tried GALLEY_CLI, then the shipped platform binary, \
         then a checkout bootstrap). To generate with no toolchain, reinstall the galley \
         crate with its generator data{}. To bootstrap from source, set GALLEY_CHECKOUT \
         at a Galley checkout with zig installed.",
        generator_cli_relative().map_or(
            format!(
                " (no prebuilt generator exists for {}:{})",
                std::env::consts::OS,
                std::env::consts::ARCH
            ),
            |relative| format!(" ({relative})")
        )
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
    // The gate owns all build semantics: generation resolves through the
    // generator CLI, compiling through the compile inputs. Both
    // consumer-build legs run the same build with the same flags; only
    // the inputs differ.
    let cli = resolve_generator_cli();
    let (build_file, source_root) = resolve_compile_inputs();
    println!(
        "cargo:rerun-if-changed={}",
        source_root.join("bindings/c/capi.zig").display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        source_root.join("bindings/c/galley.h").display()
    );
    println!("cargo:rerun-if-changed={}", build_file.display());

    // Parser generation relies on CLI flags introduced alongside the
    // bindings workflow (--emit-metadata). Refuse with guidance when the
    // resolved generator predates them instead of failing deep inside
    // generation.
    let help = Command::new(&cli)
        .arg("--help")
        .output()
        .unwrap_or_else(|e| panic!("failed to spawn {}: {e}", cli.display()));
    if !String::from_utf8_lossy(&help.stdout).contains("--emit-metadata") {
        panic!(
            "the generator at {} is too old for the bindings workflow (no --emit-metadata support); \
             update the galley crate",
            cli.display()
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
            .arg(&build_file)
            .arg(format!("-Dlanguage-dir={}", language_absolute.display()))
            .arg("-Dlib-name=galley-rust")
            .arg(format!("-Doutput={library_file}"))
            .arg("-Doptimize=ReleaseFast")
            .arg("--prefix")
            .arg(&language_absolute)
            .arg("install")
            .current_dir(&language_absolute);
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
    let include_dir = source_root.join("bindings/c");

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
        source_dir: source_root,
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
///
/// Before compiling, materializes [`PROCEDURE_RS`] as
/// [`PROCEDURE_TYPES_FILE`] in `out_dir`, which the hooks file opens with
/// `include!(concat!(env!("OUT_DIR"), ...))`.
fn compile_procedures_archive(source: &Path, out_dir: &Path) -> PathBuf {
    let archive = out_dir.join("libgalley_procedures.a");
    std::fs::write(out_dir.join(PROCEDURE_TYPES_FILE), PROCEDURE_RS)
        .expect("write procedure types file");
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
