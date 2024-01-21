{
  description = "gitea webhook payload types in rust";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-23.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        inherit (pkgs) lib;
        pname = "teahook-rs";
        version = "0.1.0";
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ go_1_21 ];
          shellHook = ''
            unset GOPATH
          '';
        };
        packages.default = pkgs.buildGoModule {
          inherit pname version;
          vendorHash = "sha256-1gM31i5NIZClDp26D4YCyHcbyZlp1eCR82GACy3SCmc=";
          src = ./.;
        };
      });
}
