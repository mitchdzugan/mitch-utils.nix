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
  }:
  let
    mkPegasus = env: env.luaPackages.buildLuarocksPackage {
      pname = "pegasus";
      version = "1.0.9-0";
      src = builtins.fetchTarball {
        url = "https://github.com/EvandroLG/pegasus.lua/archive/refs/tags/v1.0.9.tar.gz";
        sha256 = "sha256:0k264w899xpjfpkz96c2bdmdsk98xpmd5fn2362k9g8ggml927bl";
      };
      knownRockspec = ./pegasus-1.0.9-0.rockspec;
      propagatedBuildInputs = [
        env.luaPackages.lua-zlib
        env.luaPackages.mimetypes
        env.luaPackages.luasocket
        env.luaPackages.lua
        env.luaPackages.luafilesystem
      ];
    };
    mkZnFnlImpl = (envExtra: srcPath:
      let
        mkFnlFmt = env: env.luaPackages.lua.stdenv.mkDerivation {
          pname = "fnlfmt";
          version = "0.3.2";
          src = ./REPO/fnlfmt/.;
          nativeBuildInputs = [ env.luaPackages.fennel ];
          buildInputs = [ env.luaPackages.lua ];
          propogatedBuildInputs = [ env.luaPackages.lua ];
          buildPhase = ''
            mkdir -p $out/bin
            echo "#!${env.luaPackages.lua}/bin/lua" > $out/bin/fnlfmt
            fennel \
              --require-as-include \
              --add-fennel-path "$(pwd)/co/?.fnl" \
              --compile \
              "$(pwd)/co/cli.fnl" >> $out/bin/fnlfmt
            chmod +x $out/bin/fnlfmt
            echo $out
          '';
          doInstallCheck = true;
          installCheckPhase = ''
            runHook preInstallCheck
            $out/bin/fnlfmt --help > /dev/null
            runHook postInstallCheck
          '';
        };
        mkProps = env: ((import (srcPath + "/flake.dz-fnl.nix")) (env // envExtra // {mkPegasus = mkPegasus;}));
        mkLuaDeps = env: (mkProps env).luaDeps ++ [env.luaPackages.busted env.luaPackages.fennel];
        mkLua = env: (env.luaPackages.lua.withPackages (_: (mkLuaDeps env)));
        mkMacroPath = env: (
          builtins.concatStringsSep
          ";"
          (map (pkg: "${pkg}/macro-path/?.fnl") (mkLuaDeps env))
        );
        extraBuildInputsOfProps = ({ buildInputs ? [], ... }: buildInputs);
        mkExtraBuildInputs = env: (extraBuildInputsOfProps (mkProps env));
        mkPkg = env: env.luaPackages.buildLuarocksPackage rec {
          pname = (mkProps env).name;
          version = (mkProps env).version;
          src = srcPath;
          buildInputs = (mkExtraBuildInputs env) ++ [(mkLua env)];
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
          disabled = (env.luaPackages.luaOlder "5.1") || (env.luaPackages.luaAtLeast "5.4");
        }; in { mkPkg = mkPkg; } // flake-utils.lib.eachDefaultSystem (
        system: let
          pkgs = nixpkgs.legacyPackages.${system};
          lua = pkgs.luajit;
          luaPackages = lua.pkgs;
          env = { luaPackages = luaPackages; pkgs = pkgs; };
          nativeBuildInputs = with pkgs; [];
          buildInputs = with pkgs; [
            (mkLua env)
            (mkFnlFmt env)
            fennel-ls
            rlwrap
          ] ++ (mkExtraBuildInputs env);
        in {
          packages.default = mkPkg lua.pkgs;
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
              export FENNEL_MACRO_PATH="$FLAKE_ROOT/macro-path/?.fnl;${mkMacroPath env}"
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
  in {
    mkNixWork = pkgs: pkgs.writeShellScriptBin "nix-work" ''
      ${pkgs.bash}/bin/bash ${./nix-work.bash}
    '';
    mkPegasus = mkPegasus;
    mkZnFnl = arg1:
      (if (builtins.isPath arg1)
        then (mkZnFnlImpl {} arg1)
        else (srcPath: (mkZnFnlImpl arg1 srcPath)));
  };
}
