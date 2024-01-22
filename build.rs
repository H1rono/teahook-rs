use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::str::from_utf8;
use std::{env, fs, io, process};

use anyhow::Context;
use flate2::bufread::GzDecoder;
use serde::{Deserialize, Serialize};
use tar::Archive;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct GiteaMetadata {
    repository: String,
    version: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PkgMetadata {
    gitea: GiteaMetadata,
}

fn read_package_metadata(manifest_dir: &str, package_name: &str) -> anyhow::Result<PkgMetadata> {
    let metadata = cargo_metadata::MetadataCommand::new()
        .manifest_path(format!("{}/Cargo.toml", manifest_dir))
        .no_deps()
        .exec()?;
    let package = metadata
        .packages
        .into_iter()
        .find(|p| p.name == package_name)
        .ok_or(anyhow::anyhow!(
            "no metadata found for package `{}`",
            package_name
        ))?;
    let pkg_metadata = serde_json::from_value(package.metadata)?;
    Ok(pkg_metadata)
}

fn env_var(name: &str) -> Result<String, env::VarError> {
    println!("cargo:rerun-if-env-changed={}", name);
    env::var(name)
}

fn try_exists(path: &str) -> io::Result<bool> {
    println!("cargo:rerun-if-changed={}", path);
    let path = Path::new(path);
    path.try_exists()
}

fn fetch_gitea_source(gitea_root: &str, gitea: &GiteaMetadata) -> anyhow::Result<()> {
    fs::create_dir_all(gitea_root)?;
    let gitea_root = Path::new(gitea_root).canonicalize()?;

    let url = format!(
        "https://github.com/{}/archive/refs/tags/v{}.tar.gz",
        gitea.repository, gitea.version
    );
    let res = minreq::get(&url)
        .send()
        .with_context(|| format!("could not GET {}", &url))?;
    if res.status_code < 200 || res.status_code >= 300 {
        anyhow::bail!(
            "failed to fetch gitea source with status code {}",
            res.status_code
        );
    }

    let tar_gz = res.as_bytes();
    let tar = GzDecoder::new(tar_gz);
    let mut archive = Archive::new(tar);

    let entry_prefix = format!("gitea-{}", gitea.version);
    let entries = archive
        .entries()?
        .map(|e| -> anyhow::Result<_> {
            let e = e?;
            let path = e
                .path()?
                .strip_prefix(&entry_prefix)
                .map(PathBuf::from)
                .ok();
            Ok((path, e))
        })
        .filter_map(|r| match r {
            Ok((path, e)) => path.map(|p| Ok((gitea_root.join(p), e))),
            Err(e) => Some(Err(e)),
        });
    for r in entries {
        let (p, mut e) = r?;
        e.unpack(p)?;
    }
    Ok(())
}

fn gopath() -> which::Result<PathBuf> {
    println!("cargo:rerun-if-env-changed=PATH");
    which::which("go")
}

fn build_transpiler(
    current_dir: impl AsRef<Path>,
    gopath: impl AsRef<OsStr>,
    transpiler_path: impl AsRef<OsStr>,
) -> anyhow::Result<()> {
    let out = process::Command::new(gopath)
        .arg("build")
        .arg("-o")
        .arg(transpiler_path)
        .current_dir(current_dir)
        .output()?;
    if !out.status.success() {
        let stderr = from_utf8(&out.stderr)?;
        anyhow::bail!("failed to build transpiler:\n{}", stderr);
    }
    Ok(())
}

fn main() -> anyhow::Result<()> {
    let out_dir = env_var("OUT_DIR").context("could not get environment variable `OUT_DIR`")?;
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let package_name = env!("CARGO_PKG_NAME");
    let metadata = read_package_metadata(manifest_dir, package_name)?;
    let gitea_root = env_var("GITEA_SOURCE_ROOT").unwrap_or_else(|_| format!("{}/gitea", out_dir));
    let go_structs_dir = format!("{}/modules/structs", gitea_root);
    let transpiler_path =
        env_var("GITEA_TRANSPILER_PATH").unwrap_or_else(|_| format!("{}/teahook-rs", manifest_dir));
    let transpile_out = format!("{}/types.rs", out_dir);

    if !try_exists(&gitea_root)? {
        fetch_gitea_source(&gitea_root, &metadata.gitea)?;
    }

    if !try_exists(&transpiler_path)? {
        let gopath = gopath()?;
        build_transpiler(manifest_dir, gopath, &transpiler_path)?;
    }

    let struct_files = fs::read_dir(&go_structs_dir)
        .with_context(|| format!("could not read {} as directory", go_structs_dir))?
        .map(|e| e.map(|e| e.path()))
        .collect::<Result<Vec<_>, _>>()?;
    let transpile_output = process::Command::new(transpiler_path)
        .args(struct_files)
        .output()?;
    if !transpile_output.status.success() {
        let stderr = from_utf8(&transpile_output.stderr)?;
        anyhow::bail!("transpling failed:\n{}", stderr);
    }
    let transpiled = from_utf8(&transpile_output.stdout)?;
    fs::write(transpile_out, transpiled)?;
    Ok(())
}
