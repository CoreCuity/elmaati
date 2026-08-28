#!/usr/bin/env bash
# mac-provision-elmaati.sh — create (and verify) the sealed `elmaati` service user on this Mac.
#
#   sudo bash mac-provision-elmaati.sh provision   # create group + user, no admin, no FileVault
#   sudo bash mac-provision-elmaati.sh verify      # prove the seal holds (safe, read-only)
#   sudo bash mac-provision-elmaati.sh remove      # tear it all down
#
# Why a dedicated group: /Users/najlio is 750 group=staff, and sysadminctl puts new users in
# staff by default — which would let elmaati traverse and list the operator's home. Giving it
# its own primary group (gid 502) is what makes "no repo access" a filesystem fact.
#
# Ref: core/elmaati/docs/HERMES-MAC-RELOCATION.md
set -uo pipefail

USER_NAME=elmaati
FULL_NAME="Elmaati (Hermes agent)"
NEW_UID=502
NEW_GID=502
HOME_DIR="/Users/${USER_NAME}"
OPERATOR_HOME="/Users/najlio"
REPO="${OPERATOR_HOME}/Projects/corecuity"

die() { printf '\033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }
ok()  { printf '\033[32m ok \033[0m %s\n' "$*"; }
warn(){ printf '\033[33mwarn\033[0m %s\n' "$*"; }
step(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }

[[ $(id -u) -eq 0 ]] || die "run with sudo"

id_taken() { dscl . -list /Users UniqueID  | awk -v n="$1" '$2==n {found=1} END{exit !found}'; }
gid_taken(){ dscl . -list /Groups PrimaryGroupID | awk -v n="$1" '$2==n {found=1} END{exit !found}'; }
user_exists(){ dscl . -read "/Users/$1" >/dev/null 2>&1; }

provision() {
  step "Pre-flight"
  if user_exists "$USER_NAME"; then
    warn "user '$USER_NAME' already exists — skipping creation, will re-assert group + ownership"
  else
    id_taken  "$NEW_UID" && die "uid $NEW_UID is taken; pick another"
    ok "uid $NEW_UID free"
  fi
  gid_taken "$NEW_GID" && warn "gid $NEW_GID already in use — verify it is the '$USER_NAME' group"

  step "Dedicated group (NOT staff)"
  dseditgroup -o read "$USER_NAME" >/dev/null 2>&1 \
    || dseditgroup -o create -i "$NEW_GID" "$USER_NAME" \
    || die "could not create group $USER_NAME"
  ok "group $USER_NAME (gid $NEW_GID)"

  step "User"
  if ! user_exists "$USER_NAME"; then
    echo "You will be prompted for the new account's password."
    echo "It is needed ONCE for a GUI login (fast user switching) so macOS TCC prompts"
    echo "can be approved. Use a long random password from your manager, not a memorable one."
    sysadminctl -addUser "$USER_NAME" \
      -fullName "$FULL_NAME" \
      -UID "$NEW_UID" \
      -shell /bin/zsh \
      -home "$HOME_DIR" \
      -password - \
      || die "sysadminctl -addUser failed"
    ok "user $USER_NAME created (standard, no -admin flag)"
  fi

  step "Re-parent to its own group"
  dscl . -create "/Users/${USER_NAME}" PrimaryGroupID "$NEW_GID" || die "could not set PrimaryGroupID"
  # PrimaryGroupID 20 == staff on macOS; moving off it is what drops staff membership.
  chown -R "${NEW_UID}:${NEW_GID}" "$HOME_DIR" 2>/dev/null || warn "chown -R on $HOME_DIR incomplete"
  chmod 700 "$HOME_DIR"
  ok "primary group -> $USER_NAME, home 700"

  step "Notes (deliberate non-actions)"
  echo "  · NOT added to admin group  -> no sudo"
  echo "  · NOT added to FileVault    -> cannot unlock the disk at boot (operator only)"
  echo "  · NOT given any SSH key     -> cannot reach server-architect"
  echo "  · Remote Login (sshd) left as-is — do not enable it for this account"
  echo
  echo "Next: bash mac-provision-elmaati.sh verify"
}

# Assert that running as $USER_NAME CANNOT read a path.
refute_read() {
  local path="$1" label="$2"
  if [[ ! -e "$path" ]]; then warn "$label — path absent, nothing to test ($path)"; return; fi
  if sudo -u "$USER_NAME" -H /bin/bash -c "test -r '$path'" 2>/dev/null; then
    printf '\033[31mLEAK\033[0m %s IS READABLE by %s -> %s\n' "$label" "$USER_NAME" "$path"
    LEAKS=$((LEAKS+1))
  else
    ok "$label sealed"
  fi
}

verify() {
  user_exists "$USER_NAME" || die "user $USER_NAME does not exist"
  LEAKS=0

  step "Identity"
  echo "  uid/gid: $(sudo -u "$USER_NAME" id)"
  sudo -u "$USER_NAME" id -Gn | tr ' ' '\n' | grep -qx staff \
    && { printf '\033[31mLEAK\033[0m still in group staff — can traverse %s\n' "$OPERATOR_HOME"; LEAKS=$((LEAKS+1)); } \
    || ok "not in staff"
  sudo -u "$USER_NAME" id -Gn | tr ' ' '\n' | grep -qx admin \
    && { printf '\033[31mLEAK\033[0m in group admin\n'; LEAKS=$((LEAKS+1)); } \
    || ok "not in admin"

  step "Privilege escalation"
  if sudo -u "$USER_NAME" -H /bin/bash -c 'sudo -n true' 2>/dev/null; then
    printf '\033[31mLEAK\033[0m passwordless sudo available\n'; LEAKS=$((LEAKS+1))
  else
    ok "no passwordless sudo"
  fi

  step "Operator data (all of these MUST be sealed in phase 1)"
  refute_read "$OPERATOR_HOME"                  "operator home"
  refute_read "$REPO"                           "corecuity repo"
  refute_read "$REPO/.palace"                   "MemPalace"
  refute_read "$OPERATOR_HOME/.ssh"             "SSH keys"
  refute_read "$OPERATOR_HOME/.claude"          "Claude Code creds"
  refute_read "$OPERATOR_HOME/.config"          "~/.config"
  refute_read "$OPERATOR_HOME/.docker"          "Docker socket dir"
  refute_read "$OPERATOR_HOME/Library/Keychains" "operator keychain"
  refute_read "$OPERATOR_HOME/Library/Messages"  "Messages database"

  step "Result"
  if [[ $LEAKS -eq 0 ]]; then
    ok "seal holds — $USER_NAME can reach nothing of the operator's"
  else
    die "$LEAKS leak(s) — do NOT install Hermes until these are closed"
  fi
}

remove() {
  step "Removing $USER_NAME"
  read -r -p "Delete user $USER_NAME and $HOME_DIR? [y/N] " a
  [[ "$a" == "y" ]] || die "aborted"
  sysadminctl -deleteUser "$USER_NAME" -secure 2>/dev/null || warn "deleteUser reported an issue"
  dseditgroup -o delete "$USER_NAME" 2>/dev/null || true
  [[ -d "$HOME_DIR" ]] && rm -rf "$HOME_DIR"
  ok "removed"
}

case "${1:-}" in
  provision) provision ;;
  verify)    verify ;;
  remove)    remove ;;
  *) echo "usage: sudo bash $0 {provision|verify|remove}"; exit 2 ;;
esac
