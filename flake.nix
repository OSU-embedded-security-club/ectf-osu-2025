{
  description = "Python development environment with local packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    msdk = {
      url = "github:Analog-Devices-MSDK/msdk/v2024_02?shallow=1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, msdk }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        mkPythonPackage = path: pkgs.python3Packages.buildPythonPackage {
          pname = builtins.baseNameOf path;
          version = "0.1.0";
          src = path;
          format = "pyproject";
          propagatedBuildInputs = with pkgs.python3Packages; [ setuptools loguru pyserial tqdm blake3 pycryptodome ];
        };

        toolsPackage = mkPythonPackage ./tools;
        designPackage = mkPythonPackage ./design;

      in {
        devShells.default = pkgs.mkShell {
          name = "ectf-zig";

          buildInputs = with pkgs; [
            toolsPackage
            designPackage

            zig
            go-task
            zls
            clang-tools
          ];

          GCC_ARM_EMBDEDDED = pkgs.gcc-arm-embedded;
          MAXIM_PATH = msdk;

          shellHook = ''
            export SECRETS=$PWD/secrets/secrets.json
          '';
        };
      }
    );
}