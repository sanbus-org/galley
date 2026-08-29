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
//! The helper resolves Galley (`GALLEY_CHECKOUT` env var wins; otherwise it
//! shallow-clones `GALLEY_REPOSITORY` at `GALLEY_TAG`, skipping submodules),
//! builds the generator CLI, generates the parser, compiles the C-API shared
//! library, and emits the cargo directives that link your binary against it.
//! Hooks are written in Rust: when the language directory contains a
//! generated `procedures.zig` and a `procedures.rs` implementing its hooks,
//! the helper compiles `procedures.rs` with rustc into a static archive and
//! links it into the shared library — no C anywhere on the consumer side.

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

/// Generates the parser for `language_dir` (must contain `ll.grm` and the
/// language's `config.zig`) and emits cargo directives linking the current
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
        language_dir.join("config.zig").display()
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

    // One library embeds one parser; detect which family generation
    // produced (both present is ambiguous and unsupported).
    let (parser_source, parser_type) = match detect_parser_family(
        generated_parser_exists(language_dir, "_ll-parser.zig"),
        generated_parser_exists(language_dir, "_lr-parser.zig"),
    ) {
        Ok(detected) => detected,
        Err(message) => panic!("{}: {}", language_dir.display(), message),
    };
    let generated_parser = language_dir.join(parser_source);
    println!("cargo:rerun-if-changed={}", generated_parser.display());
    let error_messages_zig = language_dir.join(format!("{parser_type}_error_messages.zig"));

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
            .arg(format!("-Dparser-type={parser_type}"))
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
        if procedures_rs.exists() {
            println!("cargo:rerun-if-changed={}", procedures_rs.display());
            let archive = compile_procedures_archive(&procedures_rs, &out_dir);
            c.arg(format!("-Dprocedures-object={}", archive.display()));
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
        let config_zig = language_dir.join("config.zig");
        if config_zig.exists() {
            println!("cargo:rerun-if-changed={}", config_zig.display());
            c.arg(format!(
                "-Dconfig-zig-source={}",
                config_zig
                    .canonicalize()
                    .unwrap_or(config_zig.clone())
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

fn generated_parser_exists(language_dir: &Path, file_name: &str) -> bool {
    language_dir.join(file_name).exists()
}

/// One library embeds one parser; detect which family generation produced.
/// Returns the generated source file name and the `-Dparser-type` value.
fn detect_parser_family(
    has_ll: bool,
    has_lr: bool,
) -> Result<(&'static str, &'static str), String> {
    match (has_ll, has_lr) {
        (true, false) => Ok(("_ll-parser.zig", "ll")),
        (false, true) => Ok(("_lr-parser.zig", "lr")),
        (false, false) => Err("generation produced no parser".to_string()),
        (true, true) => Err(
            "both _ll-parser.zig and _lr-parser.zig exist; one library embeds \
             one parser — split the language dirs"
                .to_string(),
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::detect_parser_family;

    #[test]
    fn detects_ll_family() {
        assert_eq!(
            detect_parser_family(true, false),
            Ok(("_ll-parser.zig", "ll"))
        );
    }

    #[test]
    fn detects_lr_family() {
        assert_eq!(
            detect_parser_family(false, true),
            Ok(("_lr-parser.zig", "lr"))
        );
    }

    #[test]
    fn rejects_missing_parser() {
        assert!(detect_parser_family(false, false).is_err());
    }

    #[test]
    fn rejects_ambiguous_families() {
        assert!(detect_parser_family(true, true).is_err());
    }
}
