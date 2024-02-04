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
  rustBuildArgs = import ./rustBuildArgs.nix inputs;
in
craneLib.buildPackage rustBuildArgs
