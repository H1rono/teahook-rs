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
    {
      overlays.rust-toolchain = final: prev: rec {
        rust-toolchain = prev.callPackage ./nix/rust-toolchain.nix { };
      };
      overlays.crane = final: prev: {
        crane = prev.callPackage crane { };
      };
      overlays.craneLib = final: prev: {
        craneLib = prev.callPackage ./nix/craneLib.nix { };
      };
      overlays.goBuild = final: prev: {
        goBuild = prev.callPackage ./nix/goBuild.nix { };
      };
      overlays.rustBuild = final: prev: {
        rustBuild = prev.callPackage ./nix/rustBuild.nix { inherit gitea; };
      };
      overlays.rustBuildFull = final: prev: {
        rustBuildFull = prev.callPackage ./nix/rustBuildFull.nix { inherit gitea; };
      };
      overlays.cargoDoc = final: prev: {
        cargoDoc = prev.callPackage ./nix/cargoDoc.nix { inherit gitea; };
      };
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            fenix.overlays.default
            self.overlays.rust-toolchain
            self.overlays.crane
            self.overlays.craneLib
            self.overlays.goBuild
            self.overlays.rustBuild
            self.overlays.cargoDoc
          ];
        };
        inherit (pkgs) lib goBuild craneLib;
        toolchain = pkgs.rust-toolchain;
        src = craneLib.cleanCargoSource (craneLib.path ./.);

        cargoArtifacts = import ./nix/cargoArtifacts.nix {
          inherit system pkgs craneLib;
        };
        rustBuild = pkgs.rustBuild;
        rustBuildFull = pkgs.rustBuildFull;
        doc = pkgs.cargoDoc;
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
