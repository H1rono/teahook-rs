let
  inherit (builtins) currentSystem;
  getFlake = import ./getFlake.nix;
in
{ system ? currentSystem
, pkgs ? import (getFlake "nixpkgs") { inherit system; }
, lib ? pkgs.lib
, craneLib ? pkgs.callPackage ./craneLib.nix { }
, gitea ? (getFlake "gitea").outPath
}@inputs:
let
  ins = builtins.removeAttrs inputs [ "gitea" ];
  rustCommonArgs = import ./rustCommonArgs.nix ins;
  cargoArtifacts = import ./cargoArtifacts.nix ins;
  goBuild = pkgs.callPackage ./goBuild.nix { };
in
rustCommonArgs // {
  inherit cargoArtifacts;
  GITEA_SOURCE_ROOT = "${gitea}";
  GITEA_TRANSPILER_PATH = "${goBuild}/bin/teahook-rs";
}
