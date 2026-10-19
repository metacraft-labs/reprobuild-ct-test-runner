{
  description = "CodeTracer test framework (ct-test): TestBinary interface + per-framework adapters";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        nim = pkgs.nim;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            # Tools for the complete committed portable hook rules.
            pkgs.pre-commit
            pkgs.uv
            pkgs.git
            pkgs.bash
            pkgs.editorconfig-checker
            pkgs.nixfmt-rfc-style
            pkgs.prettier
            pkgs.opentofu
            nim
            pkgs.just
            pkgs.gcc
          ];
        };
      }
    );
}
