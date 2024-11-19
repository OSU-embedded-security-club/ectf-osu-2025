{
  description = "A devShell example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/1.tar.gz";
    msdk = {
      url = "github:Analog-Devices-MSDK/msdk/v2023_06?shallow=1";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    msdk,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
      in {
        devShells = {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              zig
              zls
              clang-tools
              bear
              alejandra

              gnumake
              python39
              gcc-arm-embedded
              poetry
              cacert
              (pkgs.callPackage pkgs/analog_openocd.nix {})
              minicom
            ];

            GCC_ARM_EMBDEDDED = pkgs.gcc-arm-embedded;

            shellHook = ''
              cp -r ${msdk} $PWD/msdk
              chmod -R u+rwX,go+rX,go-w $PWD/msdk
              export MAXIM_PATH=$PWD/msdk
            '';
          };

          ectf = pkgs.mkShell {
            buildInputs = with pkgs; [
              zig
              gnumake
              python39
              gcc-arm-embedded
              poetry
            ];

            GCC_ARM_EMBDEDDED = pkgs.gcc-arm-embedded;

            shellHook = ''
              cp -r ${msdk} $PWD/msdk
              chmod -R u+rwX,go+rX,go-w $PWD/msdk
              export MAXIM_PATH=$PWD/msdk
            '';
          };
        };
      }
    );
}
