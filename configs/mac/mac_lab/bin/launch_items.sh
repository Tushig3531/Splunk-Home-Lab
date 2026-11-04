for d in /Library/LaunchAgents /Library/LaunchDaemons "$HOME/Library/LaunchAgents"; do
  for f in "$d"/*.plist; do
    [ -e "$f" ] && echo "launch_item=\"$f\""
  done
done
