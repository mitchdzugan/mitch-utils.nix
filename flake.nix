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
    mkZnFnl = (pname: version: mkLuaDepsRaw: srcPath:
      let
        mkFnlFmt = luaPackages: luaPackages.lua.stdenv.mkDerivation {
          pname = "fnlfmt";
          version = "0.3.2";
          src = ./REPO/fnlfmt/.;
          nativeBuildInputs = [ luaPackages.fennel ];
          buildInputs = [ luaPackages.lua ];
          makeFlags = [
            "PREFIX=$(out)"
            "FENNEL=${luaPackages.fennel}/bin/fennel"
          ];
          sourceRoot = "${./REPO/fnlfmt/.}";
          preBuild = ''
            mkdir -p $out/wd
            cp -r co $out/wd
            cd $out/wd
          '';
          doInstallCheck = true;
          installCheckPhase = ''
            runHook preInstallCheck
            $out/bin/fnlfmt --help > /dev/null
            runHook postInstallCheck
          '';
        };
        mkLuaDeps = lp: (mkLuaDepsRaw lp) ++ (
          [lp.busted lp.fennel (mkFnlFmt lp)]
        );
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
            export FENNEL_PATH="${srcPath}/src/?.fnl"
            fennel --require-as-include --compile src/${pname}.fnl > dist/${pname}.lua
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
              fennel-ls
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
              export FLAKE_ROOT=$(getFlakeRoot $(pwd))
              export FENNEL_MACRO_PATH="$FLAKE_ROOT/macro-path/?.fnl;${mkMacroPath(luaPkgs)}"
              export FENNEL_MACRO_PATH="${./fnl/macro-path}/?.fnl;$FENNEL_MACRO_PATH"
              export FENNEL_PATH="$FLAKE_ROOT/src/?.fnl"
              echo "{:fennel-path \"$FENNEL_PATH\""       > $FLAKE_ROOT/flsproject.fnl
              echo " :macro-path \"$FENNEL_MACRO_PATH\"" >> $FLAKE_ROOT/flsproject.fnl
              echo " :extra-globals \"it describe\""     >> $FLAKE_ROOT/flsproject.fnl
              echo "}"                                   >> $FLAKE_ROOT/flsproject.fnl

              TEMP_DIR=$(mktemp -d --)
              trap 'rm -rf "$TEMP_DIR"' EXIT

              fennel_path=$(which fennel)
              echo "#!/usr/bin/env bash"              > $TEMP_DIR/fennel
              echo "rlwrap \"$fennel_path\" \"\$@\"" >> $TEMP_DIR/fennel
              chmod +x $TEMP_DIR/fennel


              echo "#!/usr/bin/env bash"                          > $TEMP_DIR/pretest
              echo "cd $FLAKE_ROOT"                              >> $TEMP_DIR/pretest
              echo "for fspec in \$FLAKE_ROOT/**/*_spec.fnl; do" >> $TEMP_DIR/pretest
              echo "  lspec=\$fspec.lua"                         >> $TEMP_DIR/pretest
              echo "  fennel \\"                                 >> $TEMP_DIR/pretest
              echo "    --require-as-include \\"                 >> $TEMP_DIR/pretest
              echo "    --correlate \\"                          >> $TEMP_DIR/pretest
              echo "    --compile \\"                            >> $TEMP_DIR/pretest
              echo "    \$fspec > \$lspec"                       >> $TEMP_DIR/pretest
              echo "done"                                        >> $TEMP_DIR/pretest
              chmod +x $TEMP_DIR/pretest

              echo "#!/usr/bin/env bash"        > $TEMP_DIR/fusted
              echo "cd $FLAKE_ROOT"            >> $TEMP_DIR/fusted
              echo "pretest && busted \"\$@\"" >> $TEMP_DIR/fusted
              chmod +x $TEMP_DIR/fusted

              export PATH="$TEMP_DIR:$PATH"
            '';
          };
        }
      )
    );
  };
}
