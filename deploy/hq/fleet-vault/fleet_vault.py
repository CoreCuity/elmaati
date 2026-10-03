"""fleet_vault — the rules of the fleet's vault, in one place.

The vault is a folder of Markdown notes on corecuity-HQ (/var/lib/fleet-vault) that Obsidian can open:

    Home.md
    clients/<client>/card.md        founder-approved, shipped from the Mac        (read-only)
    clients/<client>/timeline.md    founder-approved seed chronology              (read-only)
    clients/<client>/journal/YYYY-MM.md   what the fleet recorded itself          (append-only)
    fleet/journal/YYYY-MM.md        lessons about doing the job                   (append-only)

Everything is root-owned; svc-hermes can read it and nothing else. The fleet adds to it only through
`fleet-note`, which drops a request in an inbox; the root service `fleet-vault-ingest` applies the
checks below and appends the entry. The same checks gate what the founders ship from the Mac
(tools/fleet-vault/vault.py imports this file).

Source of truth: core/elmaati/deploy/hq/fleet-vault/ (installed by install.sh).
"""
import datetime
import hashlib
import json
import os
import re
import zoneinfo

VAULT = "/var/lib/fleet-vault"
INBOX = "/home/svc-hermes/.local/state/fleet-vault/inbox"     # svc-hermes writes requests here
OUTBOX = os.path.join(VAULT, ".results")                      # root writes the receipt for each request
STATE = os.path.join(VAULT, ".state.json")                    # today's counter + recent entry hashes
TZ = zoneinfo.ZoneInfo("Africa/Casablanca")

KINDS = ("event", "decision", "finding", "waiting", "lesson")
FOUNDERS = ("Najlaa", "Massine")
SOURCE_RE = re.compile(r"^(founder:(?:%s)|receipt:[\w.:#/-]{3,80}|plane:[A-Z]{2,6}-\d{1,5}|sentinel|observation)$"
                       % "|".join(FOUNDERS))
CLIENT_RE = re.compile(r"^[a-z0-9-]{2,30}$")
NOTE_ID_RE = re.compile(r"^n-\d{8}-\d{6}-[0-9a-f]{4}$")
TEXT_MIN, TEXT_MAX = 15, 500
REF_MAX = 120
MAX_PER_DAY = 40
REQUEST_MAX_BYTES = 4096

# What never goes into the vault, from either side. A hit refuses the entry or the file.
LEAKS = [
    ("an email address", re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")),
    ("a phone number", re.compile(r"(?<![\w.-])(?:\+|00)\d{1,3}(?:[\s.-]?\d{1,3}){3,6}\b|(?<![\d.-])0[5-7](?:[\s.-]?\d{2}){4}\b")),
    ("an amount of money", re.compile(r"(?i)(?:[€$£]\s?\d|\b\d[\d\s.,]*\s?(?:€|\$|dh|dhs|mad|eur|usd|dirhams?|euros?)\b)")),
    ("a secret-looking string", re.compile(r"\b(?:sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|plane_api_[A-Za-z0-9]{16,}|EAA[A-Za-z0-9]{30,}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,})")),
    ("a credential", re.compile(r"(?i)\b(?:password|passwd|api[ _-]?key|secret|token)\s*[:=]\s*\S{6,}")),
]


def leaks(text, other_clients=()):
    """Reasons this text may not be stored (empty list = clean)."""
    found = []
    for what, rx in LEAKS:
        m = rx.search(text)
        if m:
            found.append(f"contains {what} (“{m.group(0)[:30]}”)")
    for name in other_clients:
        if re.search(rf"(?i)(?<![\w-]){re.escape(name)}(?![\w-])", text):
            found.append(f"names another client ({name})")
    return found


def clients(vault=None):
    """Client keys = the folders the founders created under clients/. The fleet cannot add one."""
    d = os.path.join(vault or VAULT, "clients")
    try:
        return sorted(n for n in os.listdir(d) if CLIENT_RE.match(n) and os.path.isdir(os.path.join(d, n)))
    except OSError:
        return []


def other_names(client, vault=None):
    """Every name another client goes by: folder keys, plus the display names the founders shipped."""
    try:
        extra = json.load(open(os.path.join(vault or VAULT, ".client-names.json")))
    except (OSError, ValueError):
        extra = {}
    names = set(extra.get("_others", []))
    for key in set(clients(vault)) | set(k for k in extra if not k.startswith("_")):
        if key != client:
            names.add(key)
            names.update(extra.get(key, []))
    return sorted(names)


def clean_text(text):
    return re.sub(r"\s+", " ", text or "").strip()


def validate(req, vault=None):
    """(normalised entry, None) or (None, reason). `req` = {client, kind, source, text, ref?}."""
    if not isinstance(req, dict):
        return None, "request is not an object"
    client, kind, source = (str(req.get(k) or "").strip() for k in ("client", "kind", "source"))
    text, ref = clean_text(str(req.get("text") or "")), clean_text(str(req.get("ref") or ""))
    known = clients(vault)
    if client != "fleet" and client not in known:
        return None, f"unknown client '{client}'. Use one of: {', '.join(known + ['fleet'])}"
    if kind not in KINDS:
        return None, f"unknown kind '{kind}'. Use one of: {', '.join(KINDS)}"
    if not SOURCE_RE.match(source):
        return None, ("bad source. Use founder:Najlaa, founder:Massine, receipt:<id>, plane:<ID-n>, "
                      "sentinel, or observation")
    if kind == "decision" and not source.startswith("founder:"):
        return None, "a decision is only recorded when a founder took it: source must be founder:<name>"
    if kind == "lesson" and client != "fleet":
        return None, "a lesson goes in the fleet journal: use client 'fleet'"
    if not TEXT_MIN <= len(text) <= TEXT_MAX:
        return None, f"text must be {TEXT_MIN}–{TEXT_MAX} characters (got {len(text)})"
    if len(ref) > REF_MAX:
        return None, f"ref is over {REF_MAX} characters"
    for field in (text, ref):
        if re.search(r"[\x00-\x08\x0b-\x1f]|```|^\s*#|^\s*---", field):
            return None, "text must be one plain sentence or two: no headings, fences or control characters"
    why = leaks(text + " " + ref, other_names(client, vault) if client != "fleet" else [])
    if why:
        return None, "; ".join(why)
    return {"client": client, "kind": kind, "source": source, "text": text, "ref": ref}, None


def journal_path(client, when, vault=None):
    vault = vault or VAULT
    base = os.path.join(vault, "fleet") if client == "fleet" else os.path.join(vault, "clients", client)
    return os.path.join(base, "journal", when.strftime("%Y-%m") + ".md")


def render(entry, when, note_id):
    lines = [f"## {when.strftime('%Y-%m-%d %H:%M')} · {entry['kind']}", "", entry["text"], "",
             f"- source: {entry['source']}"]
    if entry["ref"]:
        lines.append(f"- ref: {entry['ref']}")
    lines += ["- by: elmaati", f"- id: {note_id}", "", ""]
    return "\n".join(lines)


def month_header(client, when):
    title = "Fleet" if client == "fleet" else client
    return (f"---\nclient: {client}\ntype: journal\nmonth: {when.strftime('%Y-%m')}\nwritten_by: fleet\n---\n"
            f"# {title} — journal {when.strftime('%Y-%m')}\n\n"
            "Written by the fleet through `fleet-note`. Append-only. Founder-approved facts are in "
            + ("[[Home]].\n\n" if client == "fleet" else f"[[clients/{client}/card|the card]] and "
               f"[[clients/{client}/timeline|the timeline]].\n\n"))


def now():
    return datetime.datetime.now(TZ)


def text_hash(entry):
    return hashlib.sha256(f"{entry['client']}|{entry['kind']}|{entry['text'].lower()}".encode()).hexdigest()[:16]


def load_state(path=None):
    try:
        return json.load(open(path or STATE))
    except (OSError, ValueError):
        return {}
