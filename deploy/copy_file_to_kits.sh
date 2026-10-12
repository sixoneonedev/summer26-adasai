#!/bin/bash

# ============================================================
# NCSSM Summer 2026 -- ADAS AI Lab
# Copy ONE file to every kit listed in the kits file.
#
# ------------------------------------------------------------
# FIRST RUN: two files you must create from templates
# ------------------------------------------------------------
# This script holds NO addresses, usernames or passwords. Every
# site-specific value comes from two files that sit beside it and
# are listed in .gitignore, so they are never committed:
#
#   deploy/kit-env.sh    ssh user (PI_USER)
#   deploy/kits.txt      kit name -> IP address list
#
# Create both from the templates shipped beside this script, and
# replace every <STUB> placeholder with a real value:
#
#   cd deploy
#   cp kit-env.sh.template ./kit-env.sh
#   cp kits.txt.template   ./kits.txt
#   chmod 600 ./kit-env.sh ./kits.txt
#   $EDITOR ./kit-env.sh    # <- set PI_USER / PI_PASS
#   $EDITOR ./kits.txt      # <- set one IP per kit
#
# Usage:
#   source ./kit-env.sh
#   ./copy_file_to_kits.sh <file> [remote-destination]
#
# Override the kits file location if your layout differs:
#   KITS_FILE=/path/to/kits.txt ./copy_file_to_kits.sh <file>
#
# NOTE: this script authenticates with plain scp (ssh keys or an
# interactive password prompt). Unlike deploy_to_kits.sh it does
# not use sshpass, so PI_PASS is not required here.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Which kits to copy to. Default: kits.txt beside this script. ----
KITS_FILE="${KITS_FILE:-$SCRIPT_DIR/kits.txt}"

# ---- Credential. REQUIRED, and only ever from the environment. ----
# Do NOT assign a literal value here: this file is committed to the repo.
PI_USER="${PI_USER:?not set -- run: source ./kit-env.sh (copy it from kit-env.sh.template first)}"

FILE="$1"
DEST="${2:-/home/$PI_USER/}"     # default remote destination: the user's home

if [ -z "$FILE" ]; then
    echo "Usage: $0 <file> [remote-destination]"
    echo "   e.g. $0 ai_driver.py"
    echo "        $0 notes.pdf /home/$PI_USER/Desktop/"
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo "ERROR: no such file: $FILE"
    exit 1
fi

# Check the kits file exists and has no unreplaced template stubs
if [ ! -f "$KITS_FILE" ]; then
    echo "ERROR: kits file not found at $KITS_FILE"
    echo "  Create it from the template beside this script:"
    echo "    mkdir -p \"$(dirname "$KITS_FILE")\""
    echo "    cp \"$SCRIPT_DIR/kits.txt.template\" \"$KITS_FILE\""
    echo "    \$EDITOR \"$KITS_FILE\"   # replace each <STUB> with a real IP"
    exit 1
fi

# (comment lines are skipped -- the template documents its own stubs)
STUB_LINES=$(grep -nE "<[A-Z0-9_]+>" "$KITS_FILE" | grep -vE "^[0-9]+:[[:space:]]*#")
if [ -n "$STUB_LINES" ]; then
    echo "ERROR: $KITS_FILE still has template placeholders in it:"
    echo "$STUB_LINES" | sed "s/^/      /"
    echo "  Replace each <STUB> above with that kit's real IP address."
    exit 1
fi

# ---- Copy to every kit. Blank lines and # comments are skipped. ----
ok=0
failed=0
while read -r kit_name kit_ip; do
    case "$kit_name" in ''|\#*) continue ;; esac
    [ -z "$kit_ip" ] && continue
    echo "Copying to $kit_name ($kit_ip)..."
    if scp "$FILE" "$PI_USER@$kit_ip:$DEST"; then
        echo "  OK"
        ok=$((ok+1))
    else
        echo "  FAILED"
        failed=$((failed+1))
    fi
done < "$KITS_FILE"

echo
echo "Done: $ok succeeded, $failed failed"
[ "$failed" -gt 0 ] && exit 1
exit 0
