#!/bin/bash

# ============================================================
# NCSSM Summer 2026 -- ADAS AI Lab
# Deploy lab files to all kit Pis
#
# ------------------------------------------------------------
# FIRST RUN: two files you must create from templates
# ------------------------------------------------------------
# This script holds NO addresses, usernames or passwords. Every
# site-specific value comes from two files that sit beside it and
# are listed in .gitignore, so they are never committed:
#
#   deploy/kit-env.sh    ssh user + password
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
# Then every time you deploy:
#   source ./kit-env.sh && ./deploy_to_kits.sh
#
# Both scripts refuse to run while any <STUB> is left unreplaced.
#
# If your directory layout differs, override the defaults:
#   SUMMER26_REPO=/path/to/summer26-adasai ./deploy_to_kits.sh
#   KITS_FILE=/path/to/kits.txt            ./deploy_to_kits.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Paths. This script lives in <repo>/deploy/, so the lab repo is one ----
# ---- level up, and the two config files sit beside this script.         ----
BASE_DIR="${SUMMER26_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"   # lab repo to deploy FROM
KITS_FILE="${KITS_FILE:-$SCRIPT_DIR/kits.txt}"               # which kits to deploy TO
LAB_DIR="$BASE_DIR/lab"
SMARTCAR_DIR="$BASE_DIR/mySmartCar"
PYTHON_DIR="$BASE_DIR/mypython"

# ---- Credentials. REQUIRED, and only ever from the environment. ----
# Do NOT assign literal values here: this file is committed to the repo.
# Set them in ./kit-env.sh (see kit-env.sh.template).
PI_USER="${PI_USER:?not set -- run: source ./kit-env.sh (copy it from kit-env.sh.template first)}"
PI_PASS="${PI_PASS:?not set -- run: source ./kit-env.sh (copy it from kit-env.sh.template first)}"

# OLLAMA_HOST is derived from this machine's en0 address further down.
# Never hardcode it here -- it changes with the network you are on.

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # no color

# ============================================================
# Pre-flight checks
# ============================================================
echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  NCSSM ADAS AI Lab -- Kit Deployment Script${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

# Check required tools are installed (ported from the previous version)
MISSING_TOOLS=()
for tool in sshpass rsync curl ping; do
    command -v "$tool" > /dev/null 2>&1 || MISSING_TOOLS+=("$tool")
done
if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo -e "${RED}ERROR: Missing required tools: ${MISSING_TOOLS[*]}${NC}"
    echo "Install them (e.g. 'brew install sshpass rsync') before running this script."
    exit 1
fi

# Check the kits file exists and has no unreplaced template stubs
if [ ! -f "$KITS_FILE" ]; then
    echo -e "${RED}ERROR: kits file not found at $KITS_FILE${NC}"
    echo -e "${YELLOW}  Create it from the template beside this script:${NC}"
    echo    "    mkdir -p \"$(dirname "$KITS_FILE")\""
    echo    "    cp \"$SCRIPT_DIR/kits.txt.template\" \"$KITS_FILE\""
    echo    "    \$EDITOR \"$KITS_FILE\"   # replace each <STUB> with a real IP"
    exit 1
fi
# (comment lines are skipped -- the template documents its own stubs)
STUB_LINES=$(grep -nE "<[A-Z0-9_]+>" "$KITS_FILE" | grep -vE "^[0-9]+:[[:space:]]*#")
if [ -n "$STUB_LINES" ]; then
    echo -e "${RED}ERROR: $KITS_FILE still has template placeholders in it:${NC}"
    echo "$STUB_LINES" | sed "s/^/      /"
    echo -e "${YELLOW}  Replace each <STUB> above with that kit's real IP address.${NC}"
    exit 1
fi

# Check source folders exist
for dir in "$LAB_DIR" "$SMARTCAR_DIR" "$PYTHON_DIR"; do
    if [ ! -d "$dir" ]; then
        echo -e "${RED}ERROR: Folder not found: $dir${NC}"
        exit 1
    fi
done

# Get MacBook IP
OLLAMA_HOST=$(ipconfig getifaddr en0 2>/dev/null)
if [ -z "$OLLAMA_HOST" ]; then
    echo -e "${RED}ERROR: Could not get MacBook IP. Are you on the right network?${NC}"
    exit 1
fi
echo -e "MacBook IP: ${GREEN}$OLLAMA_HOST${NC}"

# Check Ollama is running
OLLAMA_STATUS=$(curl -s --max-time 3 "http://$OLLAMA_HOST:11434" 2>/dev/null)
if [[ "$OLLAMA_STATUS" == *"running"* ]]; then
    echo -e "Ollama:     ${GREEN}running${NC}"
else
    echo -e "Ollama:     ${RED}NOT RUNNING -- start Ollama before deploying${NC}"
    echo ""
    read -p "Continue anyway? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}Source folders:${NC}"
echo "  Lab:      $LAB_DIR"
echo "  SmartCar: $SMARTCAR_DIR → ncssm-smartcar"
echo "  Python:   $PYTHON_DIR → ncssm-python"
echo ""
echo -e "${BLUE}Kits to deploy:${NC}"
cat "$KITS_FILE"
echo ""
read -p "Deploy to all kits? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "Cancelled."
    exit 0
fi

# ============================================================
# Deploy to each kit
# ============================================================
echo ""
PASS_COUNT=0
FAIL_COUNT=0
declare -A KIT_STATUS

while IFS=' ' read -r kit_name kit_ip; do
    # skip empty lines and comments
    [[ -z "$kit_name" || "$kit_name" == \#* ]] && continue

    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${BLUE}  $kit_name  |  $kit_ip${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"

    KIT_ERRORS=0

    # -- Ping check --
    echo -n "  Ping...                "
    if ping -c 1 -W 2 "$kit_ip" > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL -- skipping this kit${NC}"
        KIT_STATUS[$kit_name]="FAIL (unreachable)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo ""
        continue
    fi

    # -- SSH check --
    echo -n "  SSH...                 "
    SSH_TEST=$(sshpass -p "$PI_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$PI_USER@$kit_ip" "echo OK" 2>/dev/null)
    if [ "$SSH_TEST" == "OK" ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL -- check SSH and password${NC}"
        KIT_STATUS[$kit_name]="FAIL (SSH failed)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo ""
        continue
    fi

    # -- Transfer ncssm-lab --
    echo -n "  Transferring lab...    "
    sshpass -p "$PI_PASS" rsync -az --delete \
        -e "ssh -o StrictHostKeyChecking=no" \
        "$LAB_DIR/" "$PI_USER@$kit_ip:~/ncssm-lab/" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL${NC}"
        KIT_ERRORS=$((KIT_ERRORS + 1))
    fi

    # -- Point ai_driver.py at this machine's Ollama, ON THE KIT --
    # Deliberately done remotely, after the transfer. Rewriting
    # "$LAB_DIR/ai_driver.py" locally would modify a TRACKED repo file and
    # leave this machine's IP sitting in git status, one `git commit -a`
    # away from being published. Never sed the local copy.
    echo -n "  Setting Ollama IP...   "
    if sshpass -p "$PI_PASS" ssh -o StrictHostKeyChecking=no "$PI_USER@$kit_ip" \
        "sed -i \"s|^OLLAMA_HOST = os.environ.get.*|OLLAMA_HOST = os.environ.get('OLLAMA_HOST', '$OLLAMA_HOST')|\" ~/ncssm-lab/ai_driver.py" 2>/dev/null; then
        echo -e "${GREEN}$OLLAMA_HOST${NC}"
    else
        echo -e "${RED}FAIL${NC}"
        KIT_ERRORS=$((KIT_ERRORS + 1))
    fi

    # -- Transfer ncssm-smartcar --
    echo -n "  Transferring smartcar  "
    sshpass -p "$PI_PASS" rsync -az --delete \
        -e "ssh -o StrictHostKeyChecking=no" \
        "$SMARTCAR_DIR/" "$PI_USER@$kit_ip:~/ncssm-smartcar/" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL${NC}"
        KIT_ERRORS=$((KIT_ERRORS + 1))
    fi

    # -- Transfer ncssm-python --
    echo -n "  Transferring python... "
    sshpass -p "$PI_PASS" rsync -az --delete \
        -e "ssh -o StrictHostKeyChecking=no" \
        "$PYTHON_DIR/" "$PI_USER@$kit_ip:~/ncssm-python/" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL${NC}"
        KIT_ERRORS=$((KIT_ERRORS + 1))
    fi

    # -- Ollama connectivity test from Pi --
    echo -n "  Ollama from Pi...      "
    OLLAMA_TEST=$(sshpass -p "$PI_PASS" ssh -o StrictHostKeyChecking=no "$PI_USER@$kit_ip" \
        "curl -s --max-time 5 http://$OLLAMA_HOST:11434" 2>/dev/null)
    if [[ "$OLLAMA_TEST" == *"running"* ]]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL -- Pi cannot reach Ollama${NC}"
        KIT_ERRORS=$((KIT_ERRORS + 1))
    fi

    # -- Jupyter check --
    echo -n "  Jupyter...             "
    JUPYTER_TEST=$(sshpass -p "$PI_PASS" ssh -o StrictHostKeyChecking=no "$PI_USER@$kit_ip" \
        "curl -s --max-time 5 http://localhost:8888" 2>/dev/null)
    if [[ "$JUPYTER_TEST" == *"jupyter"* ]] || [[ "$JUPYTER_TEST" == *"Jupyter"* ]]; then
        echo -e "${GREEN}running${NC}"
    else
        echo -e "${YELLOW}not running -- starting${NC}"
        sshpass -p "$PI_PASS" ssh -o StrictHostKeyChecking=no "$PI_USER@$kit_ip" \
            "nohup jupyter lab --ip=0.0.0.0 --no-browser > /tmp/jupyter.log 2>&1 &" 2>/dev/null
        sleep 3
        echo -e "  Jupyter started"
    fi

    # -- Kit summary --
    echo ""
    if [ $KIT_ERRORS -eq 0 ]; then
        echo -e "  ${GREEN}✓ $kit_name PASS${NC}"
        KIT_STATUS[$kit_name]="PASS"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "  ${RED}✗ $kit_name FAIL ($KIT_ERRORS errors)${NC}"
        KIT_STATUS[$kit_name]="FAIL ($KIT_ERRORS errors)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    echo ""

done < "$KITS_FILE"

# ============================================================
# Summary report
# ============================================================
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  DEPLOYMENT SUMMARY${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
while IFS=' ' read -r kit_name kit_ip; do
    [[ -z "$kit_name" || "$kit_name" == \#* ]] && continue
    STATUS="${KIT_STATUS[$kit_name]}"
    if [[ "$STATUS" == "PASS" ]]; then
        echo -e "  ${GREEN}✓${NC}  $kit_name  ($kit_ip)  --  ${GREEN}$STATUS${NC}"
    else
        echo -e "  ${RED}✗${NC}  $kit_name  ($kit_ip)  --  ${RED}$STATUS${NC}"
    fi
done < "$KITS_FILE"
echo ""
echo -e "  Passed: ${GREEN}$PASS_COUNT${NC}   Failed: ${RED}$FAIL_COUNT${NC}"
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${YELLOW}Some kits failed. Resolve issues before camp starts.${NC}"
else
    echo -e "${GREEN}All kits deployed successfully. Ready for camp.${NC}"
fi
echo ""
