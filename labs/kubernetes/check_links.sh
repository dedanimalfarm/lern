#!/bin/bash
for f in $(find . -name "*.md"); do
  dir=$(dirname "$f")
  # Extract links like [text](path)
  grep -oP '\]\([^http][^\)]+\)' "$f" | sed 's/^\](//; s/)$//' | while read link; do
    # Remove #anchors
    file_path=$(echo "$link" | cut -d'#' -f1)
    if [ -z "$file_path" ]; then continue; fi
    # Check if exists
    if [ ! -e "$dir/$file_path" ]; then
      echo "BROKEN LINK in $f: $link"
    fi
  done
done
