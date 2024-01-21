use std::{env, fs, process};

use anyhow::Context;
use flate2::bufread::GzDecoder;
use tar::Archive;

fn main() -> anyhow::Result<()> {
    let out_dir = env::var("OUT_DIR").context("could not get environment variable `OUT_DIR`")?;
    let gitea_root = format!("{}/gitea", out_dir);
    let go_structs_dir = format!("{}/gitea-1.21.4/modules/structs", gitea_root);
    let transpiler_path = format!("{}/teahook-rs", env::current_dir()?.display());
    let transpile_out = format!("{}/types.rs", out_dir);

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
    archive
        .unpack(&gitea_root)
        .context("could not unpack tarball of gitea source code")?;

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
