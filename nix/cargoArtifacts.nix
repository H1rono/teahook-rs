let
  inherit (builtins) currentSystem;
  getFlake = import ./getFlake.nix;
in
{ system ? currentSystem
, pkgs ? import (getFlake "nixpkgs") { inherit system; }
, lib ? pkgs.lib
, craneLib ? pkgs.callPackage ./craneLib.nix { }
}@inputs:
let
  rustCommonArgs = import ./rustCommonArgs.nix inputs;
in
craneLib.buildDepsOnly rustCommonArgs
