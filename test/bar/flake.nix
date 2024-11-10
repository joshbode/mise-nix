{
  description = "Test flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    {
      systems,
      nixpkgs,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;

      eachSystem =
        f:
        lib.genAttrs (import systems) (
          system:
          f (
            import nixpkgs {
              inherit system;
            }
          )
        );
    in
    {
      devShells = eachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [ yash ];
          shellHook = ''
            export FOO=bar
          '';
        };
      });
    };
}
