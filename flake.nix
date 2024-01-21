{
  description = "gitea webhook payload types in rust";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-23.11";
    flake-utils.url = "github:numtide/flake-utils";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, fenix, crane, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        inherit (pkgs) lib;
        toolchain = fenix.packages.${system}.fromToolchainFile {
          file = ./rust-toolchain.toml;
          sha256 = "sha256-SXRtAuO4IqNOQq+nLbrsDFbVk+3aVA8NNpSZsKlVH/8=";
        };
        craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;
        src = craneLib.cleanCargoSource (craneLib.path ./.);

        rustCommonArgs = {
          inherit src;
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

          # Additional environment variables can be set directly
          CARGO_PROFILE = "";
        };

        goBuild = pkgs.buildGoModule {
          pname = "teahook-rs";
          version = "0.1.0";
          vendorHash = "sha256-1gM31i5NIZClDp26D4YCyHcbyZlp1eCR82GACy3SCmc=";
          src = ./.;
        };

        cargoArtifacts = craneLib.buildDepsOnly rustCommonArgs;
        rustBuild = craneLib.buildPackage (rustCommonArgs // {
          inherit cargoArtifacts;
        });
      in
      {
        devShells.default = craneLib.devShell {
          checks = {
            inherit rustBuild;
          };
          packages = with pkgs; [ go_1_21 ];
          shellHook = ''
            unset GOROOT
            unset GOPATH
            unset GOTOOLDIR
          '';
        };
        packages = {
          default = goBuild;
          rustDeps = cargoArtifacts;
          inherit goBuild rustBuild;
        };
      });
}
