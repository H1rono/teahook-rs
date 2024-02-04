let
  inherit (builtins) currentSystem;
  getFlake = import ./getFlake.nix;
in
{ system ? currentSystem
, pkgs ? import (getFlake "nixpkgs") { inherit system; }
, lib ? pkgs.lib
, craneLib ? pkgs.callPackage ./craneLib.nix { }
}: {
  src = craneLib.cleanCargoSource (craneLib.path ../.);
  strictDeps = true;
  nativeBuildInputs = [ pkgs.pkg-config ];
  # Common arguments can be set here to avoid repeating them later
  buildInputs = with pkgs; [
    # Add additional build inputs here
    openssl
  ] ++ lib.optionals stdenvNoCC.isDarwin [
    # Additional darwin specific inputs can be set here
    libiconv
    darwin.Security
    darwin.apple_sdk.frameworks.SystemConfiguration
  ];
  doCheck = true;

  # Additional environment variables can be set directly
  CARGO_PROFILE = "";
}
