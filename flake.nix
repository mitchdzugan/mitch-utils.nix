{
  description = "Empty Template";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }: {
    mkNixWork = pkgs: pkgs.writeShellScriptBin "nix-work" ''
      ${pkgs.bash}/bin/bash ${./nix-work.bash}
    '';
    mkZnFnl = (pname: version: mkLuaDeps: srcPath:
      let
        mkLua = luaPkgs: (luaPkgs.lua.withPackages mkLuaDeps);
        mkMacroPath = luaPkgs: (
          builtins.concatStringsSep
          ";"
          (map (pkg: "${pkg}/macro-path/?.fnl") (mkLuaDeps luaPkgs))
        );
        mkPkg = luaPkgs: luaPkgs.buildLuarocksPackage {
          pname = pname;
          version = version;
          src = srcPath;
          buildInputs = [(mkLua luaPkgs)];
          preBuild = ''
            rm -rf dist
            mkdir dist
            fennel --compile src/${pname}.fnl > dist/${pname}.lua
          '';
          postInstall = ''
            if [[ -d macro-path ]]; then
              cp -r macro-path $out
            fi
          '';
          knownRockspec = "${srcPath}/rockspecs/${pname}-${version}.rockspec";
          disabled = (luaPkgs.luaOlder "5.1") || (luaPkgs.luaAtLeast "5.4");
        }; in { mkPkg = mkPkg; } // flake-utils.lib.eachDefaultSystem (
        system: let
          pkgs = nixpkgs.legacyPackages.${system};
          luaPkgs = pkgs.lua5_1.pkgs;
          nativeBuildInputs = with pkgs; [];
          buildInputs = with pkgs; [
              (mkLua luaPkgs)
              rlwrap
            ];
        in {
          packages.default = mkPkg pkgs.lua5_1.pkgs;
          devShells.default = pkgs.mkShell {
            inherit nativeBuildInputs buildInputs;
            shellHook = ''
              function getFlakeRoot {
                d=$(pwd)
                if [[ -f "$d/flake.nix" ]]; then
                  echo $d
                elif [[ "$d" == "/" ]]; then
                  echo $1
                else
                  cd ..
                  getFlakeRoot $1
                fi
              }
              function f {
                rlwrap fennel "$@"
              }
              export FLAKE_ROOT=$(getFlakeRoot $(pwd))
              export FENNEL_MACRO_PATH="$FLAKE_ROOT/macro-path/?.fnl;${mkMacroPath(luaPkgs)}"
              export FENNEL_PATH="$FLAKE_ROOT/src/?.fnl"
              function pretest {
                for fspec in $FLAKE_ROOT/**/*_spec.fnl; do
                  lspec=$fspec.lua
                  FENNEL_MACRO_PATH="${./fnl/macro-path}/?.fnl;$FENNEL_MACRO_PATH" f \
                    --require-as-include \
                    --correlate \
                    --compile \
                    $fspec > $lspec
                done
              }
              function t {
                pretest && busted "$@"
              }
            '';
          };
        }
      )
    );
  };
}
