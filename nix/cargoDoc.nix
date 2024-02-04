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
  rustBuildFull = import ./rustBuildFull.nix inputs;
in
craneLib.cargoDoc (rustBuildArgs // {
  cargoArtifacts = rustBuildFull;
  postBuild = ''
    cat > ./target/doc/index.html << EOF
    <!DOCTYPE html>
    <html>
      <head>
        <meta http-equiv="Refresh" content="0; URL=./teahook" />
      </head>
      <body></body>
    </html>
    EOF
  '';
})
