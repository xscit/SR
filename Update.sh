#!/bin/bash

# Build shadowrocket.conf from Conf.conf template
# Processes all RULE-SET / DOMAIN-SET directives (both local and remote)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/Conf.conf"
OUTPUT="$SCRIPT_DIR/VPS.conf"
TEMP_DIR=$(mktemp -d)

trap "rm -rf $TEMP_DIR" EXIT

# Expand a RULE-SET source: append ,POLICY to each rule line
expand_ruleset() {
  local src="$1" policy="$2"
  while IFS= read -r rule || [[ -n "$rule" ]]; do
    [[ -z "$rule" || "$rule" == \#* ]] && continue
    echo "${rule},${policy}"
  done < "$src"
}

# Expand a DOMAIN-SET source: convert domains to DOMAIN/DOMAIN-SUFFIX
expand_domainset() {
  local src="$1" policy="$2"
  while IFS= read -r domain || [[ -n "$domain" ]]; do
    [[ -z "$domain" || "$domain" == \#* ]] && continue
    if [[ "$domain" == .* ]]; then
      echo "DOMAIN-SUFFIX,${domain#.},${policy}"
    else
      echo "DOMAIN,${domain},${policy}"
    fi
  done < "$src"
}

# Download a URL to a temp file, return path via stdout
download() {
  local url="$1"
  local dest="$TEMP_DIR/dl_$(echo "$url" | md5sum 2>/dev/null | cut -d' ' -f1 || md5 -q -s "$url")"
  curl -sS --retry 3 --max-time 30 -o "$dest" "$url" 2>/dev/null && echo "$dest"
}

# --- Single-pass processing ---
while IFS= read -r line || [[ -n "$line" ]]; do

  # Commented local RULE-SET: # RULE-SET,<file>,POLICY
  if [[ "$line" =~ ^#\ RULE-SET,([^,]+),([^,]+)$ ]]; then
    src="${BASH_REMATCH[1]}" policy="${BASH_REMATCH[2]}"
    local_file="$SCRIPT_DIR/$src"
    echo "$line"
    if [ -f "$local_file" ] && [ -s "$local_file" ]; then
      expand_ruleset "$local_file" "$policy"
    fi

  # Remote RULE-SET
  elif [[ "$line" =~ ^RULE-SET,https?:// ]]; then
    url=$(echo "$line" | cut -d',' -f2)
    policy=$(echo "$line" | cut -d',' -f3)
    echo "# $line"
    dest=$(download "$url")
    if [ -n "$dest" ]; then
      expand_ruleset "$dest" "$policy"
    else
      echo "# ⚠️ Failed to download: $url"
      echo "$line"
    fi

  # Remote DOMAIN-SET
  elif [[ "$line" =~ ^DOMAIN-SET,https?:// ]]; then
    url=$(echo "$line" | cut -d',' -f2)
    policy=$(echo "$line" | cut -d',' -f3)
    echo "# $line"
    dest=$(download "$url")
    if [ -n "$dest" ]; then
      expand_domainset "$dest" "$policy"
    else
      echo "# ⚠️ Failed to download: $url"
      echo "$line"
    fi

  else
    echo "$line"
  fi

done < "$TEMPLATE" > "$OUTPUT"

echo "✅ shadowrocket.conf generated at $(date)"