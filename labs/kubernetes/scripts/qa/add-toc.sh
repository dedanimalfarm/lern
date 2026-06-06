#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../../" # k8s root

for dir in modules/* projects/*; do
  if [[ ! -f "$dir/README.md" ]]; then continue; fi
  
  # Check if TOC already exists
  if grep -q "<!-- TOC -->" "$dir/README.md"; then
    echo "Skipping $dir - TOC exists"
    continue
  fi
  
  echo "Adding TOC to $dir"
  
  # Generate TOC from ## and ### headers, excluding TOC itself
  TOC=$(grep -E '^(##|###) ' "$dir/README.md" | awk '
    {
      level = length($1);
      sub(/^(#)+ /, "");
      title = $0;
      
      link = tolower(title);
      gsub(/[^a-z0-9_ -]/, "", link);
      gsub(/ /, "-", link);
      
      indent = "";
      for (i = 3; i <= level; i++) indent = indent "  ";
      
      print indent "- [" title "](#" link ")"
    }
  ')
  
  # Insert TOC after the main header (# Title)
  # We use awk to do this safely
  awk -v toc="## Оглавление\n<!-- TOC -->\n$TOC\n<!-- /TOC -->\n" '
    /^# / && !done {
      print $0;
      print "\n" toc;
      done=1;
      next
    }
    { print $0 }
  ' "$dir/README.md" > "$dir/README.md.tmp"
  
  mv "$dir/README.md.tmp" "$dir/README.md"
done
