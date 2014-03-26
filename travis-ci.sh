#!/bin/sh
set -e

RESULT="$(cask exec cask build 2>&1)"

if echo "$RESULT" | grep -i -e warning -e error; then
    echo "$RESULT"
    exit 1
else
    exit 0
fi
