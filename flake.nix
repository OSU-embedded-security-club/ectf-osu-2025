{
  description = "Python development environment with local packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        mkPythonPackage = path: pkgs.python3Packages.buildPythonPackage {
          pname = builtins.baseNameOf path;
          version = "0.1.0";
          src = path;
          format = "pyproject";
          propagatedBuildInputs = with pkgs.python3Packages; [ setuptools loguru pyserial tqdm ];  # Add dependencies if needed
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

          shellHook = ''
            # Detect shell and set up completions accordingly
            if [ -n "$BASH" ]; then
              source <(task --completion bash)
            elif [ -n "$ZSH_NAME" ]; then
              source <(task --completion zsh)
            elif [ -n "$FISH_VERSION" ]; then
              TMPFILE=$(mktemp)
              task --completion-script fish > $TMPFILE
              source $TMPFILE
              rm $TMPFILE
            fi

            echo "go-task development environment loaded"
          '';
        };
      }
    );
}