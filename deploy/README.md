# deploy/ — kit deployment tooling

Facilitator tooling for pushing this lab onto the kit Pis.

These scripts contain **no addresses, MAC addresses, usernames or passwords**.
Every site-specific value comes from two files that live in this directory and
are excluded by `.gitignore`:

| file | created from | holds |
|---|---|---|
| `kit-env.sh` | `kit-env.sh.template` | `PI_USER`, `PI_PASS` |
| `kits.txt` | `kits.txt.template` | kit name → IP address |
| `kit-inventory.md` | — (hand-maintained) | kit MAC addresses + condition notes |

`kit-inventory.md` isn't used by the scripts — it's the hardware inventory, kept
here so all local-only kit data lives in one place. It is gitignored for the
same reason as the other two.

## Setup (once, after cloning)

Replace every `<STUB>` with a real value:

```bash
cd deploy
cp kit-env.sh.template ./kit-env.sh
cp kits.txt.template   ./kits.txt
chmod 600 ./kit-env.sh ./kits.txt

$EDITOR ./kit-env.sh    # <SSH_USERNAME_ON_THE_KITS>, <SSH_PASSWORD_ON_THE_KITS>
$EDITOR ./kits.txt      # <KIT1_IP> … <KIT5_IP>
```

Both scripts **refuse to run while any `<STUB>` remains**, so you cannot
accidentally deploy against placeholders. Neither `kit-env.sh` nor `kits.txt`
is tracked — verify with `git check-ignore -v deploy/kit-env.sh` before your
first commit.

## Usage

```bash
source ./kit-env.sh                     # sets PI_USER / PI_PASS
./deploy_to_kits.sh                     # full lab deploy to every kit
./copy_file_to_kits.sh <file> [dest]    # push one file to every kit
```

## Configuration

| variable | default | purpose |
|---|---|---|
| `PI_USER` | *required* | ssh user on the kits (both scripts) |
| `PI_PASS` | *required* | ssh password; `deploy_to_kits.sh` only, via `sshpass` |
| `KITS_FILE` | `./kits.txt` | kit name → IP list |
| `SUMMER26_REPO` | repo root (`..`) | lab tree to deploy from |

Paths resolve from the script's own location, so a fresh clone works with no
editing. `OLLAMA_HOST` is derived at runtime from this machine's `en0` address —
never hardcode it; the script exits if it can't be determined.

`deploy_to_kits.sh` pre-flights for `sshpass`, `rsync`, `curl` and `ping`, and
prompts for confirmation before transferring anything. `copy_file_to_kits.sh`
uses plain `scp` (ssh keys or an interactive prompt), so it needs only `PI_USER`.

## History

This replaces `docs/setup-scripts/`. Credentials are no longer assigned in the
script at all — they come from `kit-env.sh`, which `.gitignore` excludes.

Other fixes made in this move:

- **Quoted tilde paths** (`BASE_DIR="~/..."`) never expand inside double quotes,
  so an earlier copy of this script exited at its own kits-file check before
  doing anything. Paths are now script-relative.
- **`PYTHON_DIR` case.** One copy referenced `myPython` while the directory is
  `mypython` — silently fine on macOS, broken on Linux.
- **Duplicate kit names.** The original `kits.txt` named all five lines `kit1`,
  so per-kit success/failure output could not distinguish them. The template now
  documents that names must be unique.
- **Hardcoded subnet** in `copy_file_to_kits.sh`, whose kit set also disagreed
  with `kits.txt`. It now reads `KITS_FILE`, so both scripts target the same kits.
