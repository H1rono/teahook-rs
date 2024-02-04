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
    gitea = {
      url = "github:go-gitea/gitea/v1.21.4";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, fenix, crane, gitea, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            fenix.overlays.default
          ];
        };
        inherit (pkgs) lib;
        toolchain = pkgs.fenix.fromToolchainFile {
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
          doCheck = true;

          # Additional environment variables can be set directly
          CARGO_PROFILE = "";
        };
        rustBuildArgs = rustCommonArgs // {
          inherit cargoArtifacts;
          GITEA_SOURCE_ROOT = "${gitea}";
          GITEA_TRANSPILER_PATH = "${goBuild}/bin/teahook-rs";
        };

        goBuild = pkgs.buildGoModule {
          pname = "teahook-rs";
          version = "0.1.0";
          vendorHash = "sha256-1gM31i5NIZClDp26D4YCyHcbyZlp1eCR82GACy3SCmc=";
          src = ./.;
        };

        cargoArtifacts = craneLib.buildDepsOnly rustCommonArgs;
        rustBuild = craneLib.buildPackage (rustBuildArgs // {
          inherit cargoArtifacts;
        });
        rustBuildFull = craneLib.buildPackage (rustBuildArgs // {
          inherit cargoArtifacts;
          doInstallCargoArtifacts = true;
        });
        doc = craneLib.cargoDoc (rustBuildArgs // {
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
          default = rustBuild;
          rustDeps = cargoArtifacts;
          inherit goBuild rustBuild rustBuildFull doc;
        };
      });
}
