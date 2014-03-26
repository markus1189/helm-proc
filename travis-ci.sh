#!/bin/sh

PATH="$HOME/.cask/bin:$PATH"
RESULT="$(cask exec cask build 2>&1)"

echo "$RESULT"

! echo "$RESULT" | grep -i -e warning -e error
