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
    _pkgs = (import nixpkgs {});
    fetchFromGitHub = { owner, repo, rev, sha256 }: (
      builtins.fetchTarball {
        inherit sha256;
        url = "https://github.com/${owner}/${repo}/tarball/${rev}";
      }
    );

    mkPegasus = lua: lua.pkgs.buildLuarocksPackage {
      pname = "pegasus";
      version = "1.0.9-0";
      src = builtins.fetchTarball {
        url = "https://github.com/EvandroLG/pegasus.lua/archive/refs/tags/v1.0.9.tar.gz";
        sha256 = "sha256:0k264w899xpjfpkz96c2bdmdsk98xpmd5fn2362k9g8ggml927bl";
      };
      knownRockspec = ./pegasus-1.0.9-0.rockspec;
      propagatedBuildInputs = [
        lua.pkgs.lua-zlib
        lua.pkgs.mimetypes
        lua.pkgs.luasocket
        lua.pkgs.lua
        lua.pkgs.luafilesystem
      ];
    };
    mkLuaColors = lua: lua.pkgs.buildLuarocksPackage {
      pname = "lua-color";
      version = "1.2-5";
      knownRockspec = ./lua-color-1.2-5.rockspec;
      src = fetchFromGitHub {
        owner = "Firanel";
        repo = "lua-color";
        rev = "v1.2-5";
        sha256 = "sha256-YBtkCLHI1GH1BzjM7zTppyzJd/w6nuJGnehJyupHhSY=";
      };
    };
    /*
    mkNeorg = env: env.luaPackages.buildLuarocksPackage {
      pname = "neorg";
      version = "1.0.9-0";
      src = builtins.fetchTarball {
        url = "https://github.com/nvim-neorg/neorg/archive/refs/tags/v9.4.0.tar.gz";
        sha256 = "sha256:0k264w899xpjfpkz96c2bdmdsk98xpmd5fn2362k9g8ggml927bl";
      };
      knownRockspec = ./pegasus-1.0.9-0.rockspec;
      propagatedBuildInputs = [
        env.luaPackages.lua
        env.luaPackages.lua-utils-nvim
        env.luaPackages.nui-nvim
        env.luaPackages.nvim-nio
        env.luaPackages.plenary-nvim
      ];
    };
    */
    mkFnlFmt = lua: lua.stdenv.mkDerivation {
      pname = "fnlfmt";
      version = "0.3.2";
      src = ./REPO/fnlfmt/.;
      nativeBuildInputs = [ lua.pkgs.fennel ];
      buildInputs = [ lua ];
      propogatedBuildInputs = [ lua ];
      buildPhase = ''
        mkdir -p $out/bin
        echo "#!${lua}/bin/lua" > $out/bin/fnlfmt
        ${lua.pkgs.fennel}/bin/fennel \
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
    mkZnFnlImpl = (envExtra: srcPath:
      let
        props = import (srcPath + "/flake.dz-fnl.nix");
        mkDefaultLuaOfProps = (
          { mkDefaultLua ? (p: p.luajit), ...}: mkDefaultLua
        );
        mkDefaultLua = (mkDefaultLuaOfProps props);
        mkLua = pkgs@{ __BASE_LUA ? 0, ... }: (
          if __BASE_LUA == 0 then (mkDefaultLua pkgs) else __BASE_LUA
        );
        __e = pkgs: pkgs // envExtra // {
          luajit = pkgs.luajit;
          lua5_1 = pkgs.lua5_1;
          lua5_2 = pkgs.lua5_2;
          lua5_3 = pkgs.lua5_3;
          lua5_4 = pkgs.lua5_4;
        };
        _lua = pkgs: mkLua (__e pkgs);
        _e = pkgs: (__e pkgs) // {
          inherit pkgs;
          __BASE_LUA = _lua pkgs;
          lua = _lua pkgs;
          luaPackages = (_lua pkgs).pkgs // {
            lua-colors = mkLuaColors (_lua pkgs);
            pegasus = mkPegasus (_lua pkgs);
          };
        };
        _lp = pkgs: (_lua pkgs).pkgs;
        mkLuaDeps = pkgs: (props.mkLuaDeps (_e pkgs)) ++ [(_lp pkgs).busted (_lp pkgs).fennel];
        mkLuaPkg = pkgs: ((_lp pkgs).lua.withPackages (_: (mkLuaDeps pkgs)));
        mkMacroPath = pkgs: (
          builtins.concatStringsSep
          ";"
          (map (pkg: "${pkg}/macro-path/?.fnl") (mkLuaDeps pkgs))
        );
        mkExtraBuildInputsOfProps = (
          { mkBuildInputs ? (_: []), ... }: mkBuildInputs
        );
        mkExtraBuildInputs = mkExtraBuildInputsOfProps props;
        mkBuildInputs = pkgs: ((mkExtraBuildInputs pkgs) ++ [
          (mkLuaPkg pkgs)
          (mkFnlFmt (_lua pkgs))
          pkgs.fennel-ls
          pkgs.rlwrap
        ]);
        mkPropagatedBuildInputsOfProps = (
          { mkPropagatedBuildInputs ? (_: []), ... }: mkPropagatedBuildInputs
        );
        mkPropagatedBuildInputs = mkPropagatedBuildInputsOfProps props;
        mkRawPkg = pkgs: (_lp pkgs).buildLuarocksPackage rec {
          pname = props.name;
          version = props.version;
          src = srcPath;
          buildInputs = mkBuildInputs pkgs;
          propagatedBuildInputs = mkPropagatedBuildInputs (_e pkgs);
          preBuild = ''
            rm -rf dist
            mkdir dist
            export FENNEL_MACRO_PATH="${mkMacroPath pkgs}"
            export FENNEL_MACRO_PATH="${./fnl/macro-path}/?.fnl;$FENNEL_MACRO_PATH"
            export FENNEL_PATH="${srcPath}/src/?.fnl"
            ${(_lp pkgs).fennel}/bin/fennel --require-as-include --compile src/${pname}.fnl > dist/${pname}.lua
          '';
          postInstall = ''
            if [[ -d macro-path ]]; then
              cp -r macro-path $out
            fi
          '';
          knownRockspec = "${srcPath}/rockspecs/${pname}-${version}.rockspec";
          disabled = ((_lp pkgs).luaOlder "5.1") || ((_lp pkgs).luaAtLeast "5.4");
        };
        mkShellHook = pkgs: ''
          export LUA_PATH_EXTRA="$(
          ${mkLuaPkg pkgs}/bin/lua -e 'print(package.path)'
          )"
          export FENNEL_MACRO_PATH="${mkMacroPath pkgs}"
          export FENNEL_MACRO_PATH="${./fnl/macro-path}/?.fnl;$FENNEL_MACRO_PATH"

          function getDzFnlFlakeRoot {
            d=$(pwd)
            if [[ -f "$d/flake.dz-fnl.nix" ]]; then
              echo $d
            elif [[ "$d" == "/" ]]; then
              echo ""
            else
              cd ..
              getDzFnlFlakeRoot
            fi
          }
          export FLAKE_ROOT=$(getDzFnlFlakeRoot)

          if [[ "$FLAKE_ROOT" == "" ]]; then
            :
          else
          ## REST OF SCRIPT IS ELSE BRANCH

          TEMP_DIR=$(mktemp -d --)
          trap 'rm -rf "$TEMP_DIR"' EXIT

          export FENNEL_MACRO_PATH="$FLAKE_ROOT/macro-path/?.fnl;$FENNEL_MACRO_PATH"
          export FENNEL_PATH="$FLAKE_ROOT/src/?.fnl"

          echo "{:fennel-path \"$FENNEL_PATH\""       > $TEMP_DIR/nixMinimal.fnl
          echo " :macro-path \"$FENNEL_MACRO_PATH\"" >> $TEMP_DIR/nixMinimal.fnl
          echo " :extra-globals \"it describe\""     >> $TEMP_DIR/nixMinimal.fnl
          echo "}"                                   >> $TEMP_DIR/nixMinimal.fnl

          cp "$FLAKE_ROOT/flsproject.template.fnl" "$TEMP_DIR/template.fnl" 2> /dev/null
          if [ ! -f "$TEMP_DIR/template.fnl" ]; then
            echo "{}" > "$TEMP_DIR/template.fnl"
          fi
          pushd "$TEMP_DIR"
          read -r -d "" FENNEL_EVAL_STR << EOF
          (let [fennel (require :fennel)
                nix-min (fennel.dofile "./nixMinimal.fnl")
                template (fennel.dofile "./template.fnl")]
            (set template.fennel-path (.. nix-min.fennel-path ";" (or template.fennel-path "")))
            (set template.macro-path (.. nix-min.macro-path ";" (or template.macro-path "")))
            (set template.extra-globals (.. nix-min.extra-globals " " (or template.extra-globals "")))
            (fennel.view template))
          EOF


          fennel --eval "$FENNEL_EVAL_STR" > $FLAKE_ROOT/flsproject.fnl
          popd

          mkdir -p $FLAKE_ROOT/.vscode
          vscodeSettingsPath="$FLAKE_ROOT/.vscode/settings.json"
          echo "{\"fennel-ls.fennel-path\": \"$FENNEL_PATH\","       > $vscodeSettingsPath
          echo " \"fennel-ls.macro-path\": \"$FENNEL_MACRO_PATH\"," >> $vscodeSettingsPath
          echo " \"fennel-ls.extra-globals\": \"it describe\","     >> $vscodeSettingsPath
          echo " \"customLocalFormatters.formatters\": [{"          >> $vscodeSettingsPath
          echo "   \"command\": \"fnlfmt $""{file}\","              >> $vscodeSettingsPath
          echo "   \"languages\": [\"fennel\"]"                     >> $vscodeSettingsPath
          echo " }]}"                                               >> $vscodeSettingsPath

          fennel_path=$(which fennel)

          echo "#!/usr/bin/env bash"                            > $TEMP_DIR/fennel
          echo "export LUA_PATH=\"$LUA_PATH;$LUA_PATH_EXTRA\"" >> $TEMP_DIR/fennel
          echo "rlwrap \"$fennel_path\" \"\$@\""               >> $TEMP_DIR/fennel
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
          fi
        '';
        mkPkg = pkgs: mkRawPkg pkgs;
        madeOutputs = {
          inherit mkPkg mkShellHook mkBuildInputs;
        }; in madeOutputs // flake-utils.lib.eachDefaultSystem (
        system: let
          pkgs = nixpkgs.legacyPackages.${system};
          nativeBuildInputs = with pkgs; [];
          buildInputs = with pkgs; [
            (mkLuaPkg pkgs)
            (mkFnlFmt (_lua pkgs))
            fennel-ls
            rlwrap
          ] ++ (mkExtraBuildInputs pkgs);
        in {
          packages.default = mkPkg pkgs;
          devShells.default = pkgs.mkShell {
            inherit nativeBuildInputs buildInputs;
            shellHook = mkShellHook pkgs;
          };
        }
      )
    );
  in {
    mkNixWork = pkgs: pkgs.writeShellScriptBin "nix-work" ''
      ${pkgs.bash}/bin/bash ${./nix-work.bash}
    '';
    mkPegasus = mkPegasus;
    mkLuaColors = mkLuaColors;
    # mkNeorg = mkNeorg;
    mkFnlFmt = mkFnlFmt;
    mkZnFnl = arg1:
      (if (builtins.isPath arg1)
        then (mkZnFnlImpl {} arg1)
        else (srcPath: (mkZnFnlImpl arg1 srcPath)));
  };
}
