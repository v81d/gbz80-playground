{
  description = "A flake environment for Game Boy development.";

  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-darwin" "aarch64-linux" "x86_64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [
          rgbds
          gearboy
          gnumake
          gcc
          asm-lsp
          python3
        ];
      };
    });
  };
}
