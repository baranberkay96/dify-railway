#!/bin/sh
set -eu

HOME_DIR=/home/dify
WORKSPACE_DIR=/workspace

mkdir -p "$HOME_DIR/.snapshots" "$WORKSPACE_DIR"
rm -rf "$HOME_DIR/lost+found"

# Only the top-level directories need fixing; content is created by "dify" itself.
chown dify:dify "$HOME_DIR" "$HOME_DIR/.snapshots" "$WORKSPACE_DIR"
chmod 0700 "$HOME_DIR/.snapshots"

export HOME="$HOME_DIR"
cd "$HOME_DIR"

exec setpriv --reuid=dify --regid=dify --init-groups \
  shellctl serve --listen "${SHELLCTL_LISTEN:-[::]:5004}"
