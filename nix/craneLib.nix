let
  inherit (builtins) currentSystem;
  getFlake = import ./getFlake.nix;
in
{ system ? currentSystem
, pkgs ? import (getFlake "nixpkgs") { inherit system; }
, crane ? pkgs.callPackage (getFlake "crane") { }
, rust-toolchain ? pkgs.callPackage ./rust-toolchain.nix { }
}:
crane.overrideToolchain rust-toolchain
