#!/usr/bin/env bash

FD=$(pwd)
WD=$(mktemp -d)

trap 'rm -rf "$WD"' EXIT

cd $WD || exit

####       UNUSED WITH NEW METHOD FOR RELOADING
#
# mkfifo "$WD/pipe"
#
# echo "#!/usr/bin/env fish"      > $WD/killer.fish
# echo "read -l cmd < $WD/pipe"  >> $WD/killer.fish
# echo "echo \$cmd > $WD/cmd"    >> $WD/killer.fish
# echo "set pid \$(cat $WD/pid)" >> $WD/killer.fish
# echo "kill -TERM \$pid"          >> $WD/killer.fish
# echo ""                        >> $WD/killer.fish
# chmod +x $WD/killer.fish
#
# echo "#!/usr/bin/env fish"  > $WD/spawn_killer.fish
# echo "$WD/killer.fish &"   >> $WD/spawn_killer.fish
# chmod +x $WD/spawn_killer.fish
#
# mkdir "$WD/bin"
# echo "#!/usr/bin/env fish"     > $WD/bin/nix-reload
# echo "echo reload > $WD/pipe" >> $WD/bin/nix-reload
# chmod +x $WD/bin/nix-reload
#
#### /END  UNUSED WITH NEW METHOD FOR RELOADING

echo "function nix-reload"     > $WD/source.fish
echo "  cd $WD/project"        >> $WD/source.fish
echo "  nix flake update"      >> $WD/source.fish
echo "  echo reload > $WD/cmd" >> $WD/source.fish
echo "  exit 0"                >> $WD/source.fish
echo "end"                     >> $WD/source.fish

function launch_shell {
  sh -c "cd $WD/project && nix develop --command fish -C 'cd \$(readlink -f ./)' -C 'source $WD/source.fish' -C pwd -C 'git status' -C 'echo welcome to flake project'"
}

ln -s "$FD" project

while true; do
  launch_shell
  cmd=$(cat ./cmd 2>/dev/null)
  echo "CMD: [ $cmd ]"
  if [[ "$cmd" == "reload" ]]; then
    echo "reloading..."
    rm ./cmd
  else
    echo "clearing tmp directory and exiting..."
    exit 0
  fi
done
