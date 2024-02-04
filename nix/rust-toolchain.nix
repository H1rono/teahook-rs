let
  inherit (builtins) currentSystem;
  getFlake = import ./getFlake.nix;
in
{ system ? currentSystem
, pkgs ? import (getFlake "nixpkgs") { inherit system; }
, fenix ? import (getFlake "fenix") { inherit pkgs; }
}: fenix.fromToolchainFile {
  file = ../rust-toolchain.toml;
  sha256 = "sha256-SXRtAuO4IqNOQq+nLbrsDFbVk+3aVA8NNpSZsKlVH/8=";
}
