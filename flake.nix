{
  description = "A devShell example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/1.tar.gz";
    msdk = { url = "github:Analog-Devices-MSDK/msdk/v2023_06"; flake = false; };
    # analog-openocd = { url = "git+https://github.com/analogdevicesinc/openocd?submodules=1"; flake = false; };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    msdk,
    # analog-openocd,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
      in
        with pkgs; {
          devShells.default = mkShell {
            buildInputs = [
              zig
              zls
              gnumake
              python39
              bear
              gcc-arm-embedded
              poetry
              cacert
              # (pkgs.callPackage pkgs/analog_openocd.nix { inherit analog-openocd; })
              # (pkgs.callPackage pkgs/analog_openocd.nix { })
              minicom
            ];

            GCC_ARM_EMBDEDDED = gcc-arm-embedded;

            MAXIM_PATH = "/var/home/mbund/dev/ectf/gold/msdk";
            shellHook = ''
              # cp -r $msdk $PWD/msdk
              # chmod -R u+rwX,go+rX,go-w $PWD/msdk
              # export MAXIM_PATH=$PWD/msdk
            '';
          };
        }
    );
}
