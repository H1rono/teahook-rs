let
  inherit (builtins) currentSystem;
  getFlake = import ./getFlake.nix;
in
{ system ? currentSystem
, pkgs ? import (getFlake "nixpkgs") { inherit system; }
}: pkgs.buildGoModule {
  pname = "teahook-rs";
  version = "0.1.0";
  vendorHash = "sha256-1gM31i5NIZClDp26D4YCyHcbyZlp1eCR82GACy3SCmc=";
  src = ../.;
}
