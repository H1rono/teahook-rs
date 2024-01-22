use std::{env, fs, io, process};

use anyhow::Context;
use flate2::bufread::GzDecoder;
use tar::Archive;

fn env_var(name: &str) -> Result<String, env::VarError> {
    println!("cargo:rerun-if-env-changed={}", name);
    env::var(name)
}

fn try_exists(path: &str) -> io::Result<bool> {
    println!("cargo:rerun-if-changed={}", path);
    let path = std::path::Path::new(path);
    path.try_exists()
}

fn fetch_gitea_source(gitea_root: &str) -> anyhow::Result<()> {
    fs::create_dir_all(gitea_root)?;
    let gitea_root = std::path::Path::new(gitea_root).canonicalize()?;

    let url = "https://github.com/go-gitea/gitea/archive/refs/tags/v1.21.4.tar.gz";
    let res = minreq::get(url)
        .send()
        .with_context(|| format!("could not GET {}", url))?;
    if res.status_code < 200 || res.status_code >= 300 {
        anyhow::bail!(
            "failed to fetch gitea source with status code {}",
            res.status_code
        );
    }

    let tar_gz = res.as_bytes();
    let tar = GzDecoder::new(tar_gz);
    let mut archive = Archive::new(tar);

    let entries = archive
        .entries()?
        .map(|e| -> anyhow::Result<_> {
            let e = e?;
            let path = e
                .path()?
                .strip_prefix("gitea-1.21.4")
                .map(|p| p.to_path_buf())
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

fn main() -> anyhow::Result<()> {
    let current_dir = env::current_dir()?;
    let out_dir = env_var("OUT_DIR").context("could not get environment variable `OUT_DIR`")?;
    let gitea_root = env_var("GITEA_SOURCE_ROOT").unwrap_or_else(|_| format!("{}/gitea", out_dir));
    let go_structs_dir = format!("{}/modules/structs", gitea_root);
    let transpiler_path = env_var("GITEA_TRANSPILER_PATH")
        .unwrap_or_else(|_| format!("{}/teahook-rs", current_dir.display()));
    let transpile_out = format!("{}/types.rs", out_dir);

    if !try_exists(&gitea_root)? {
        fetch_gitea_source(&gitea_root)?;
    }

    if !try_exists(&transpiler_path)? {
        anyhow::bail!(
            "file not found in path `{}`. did you run `go build`?",
            transpiler_path
        );
    }

    let struct_files = fs::read_dir(&go_structs_dir)
        .with_context(|| format!("could not read {} as directory", go_structs_dir))?
        .map(|e| e.map(|e| e.path()))
        .collect::<Result<Vec<_>, _>>()?;
    let transpile_output = process::Command::new(transpiler_path)
        .args(struct_files)
        .output()?;
    if !transpile_output.status.success() {
        let stderr = std::str::from_utf8(&transpile_output.stderr)?;
        anyhow::bail!("transpling failed:\n{}", stderr);
    }
    let transpiled = std::str::from_utf8(&transpile_output.stdout)?;
    fs::write(transpile_out, transpiled)?;
    Ok(())
}
