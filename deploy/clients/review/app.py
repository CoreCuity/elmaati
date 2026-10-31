"""review.corecuity.com — answer CoreCuity review documents on the page.

A review is a JSON file in reviews/ (sections → items with today / proposal).
The founder picks Oui / Non / À discuter per item and may comment; Save stores the
answers in data/<slug>.json and posts a summary to Discord (webhook in .env).

Standard library only. Listens on 127.0.0.1; Caddy in front adds TLS and basic auth.
"""
import html
import json
import os
import pathlib
import threading
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = pathlib.Path(__file__).resolve().parent
REVIEWS = HERE / "reviews"
DATA = HERE / "data"
PORT = int(os.environ.get("REVIEW_PORT", "8130"))
WEBHOOK = os.environ.get("DISCORD_WEBHOOK_URL", "")
CHOICES = {"oui": "Oui", "non": "Non", "discuter": "À discuter"}
MAX_BODY = 200_000
LOCK = threading.Lock()


def load_env():
    env = HERE / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip())


def reviews():
    out = {}
    for path in sorted(REVIEWS.glob("[!.]*.json")):  # skip hidden/macOS "._" files
        review = json.loads(path.read_text(encoding="utf-8"))
        out[review["slug"]] = review
    return out


def saved(slug):
    path = DATA / f"{slug}.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"answers": {}, "history": []}


def e(text):
    return html.escape(str(text or ""), quote=True)


CSS = """
:root { --bg:#111214; --card:#1a1b1e; --line:#2c2d31; --ink:#ecebe7; --mute:#9a9ca3; --gold:#D4AF37; --ok:#3fae5d; --no:#d9534f; --talk:#e0a33a; }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--ink); font:16px/1.5 -apple-system, "Helvetica Neue", Arial, sans-serif; }
main { max-width:860px; margin:0 auto; padding:20px 16px 120px; }
h1 { font-size:1.6rem; margin:0 0 4px; } h2 { font-size:1.15rem; margin:28px 0 10px; padding-bottom:4px; border-bottom:2px solid var(--gold); }
.sub { color:var(--mute); margin:0 0 14px; font-size:.92rem; }
.intro { background:var(--card); border-left:3px solid var(--gold); padding:10px 14px; border-radius:6px; font-size:.95rem; }
.item { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:14px; margin:0 0 12px; }
.item h3 { margin:0 0 6px; font-size:1.02rem; } .meta { color:var(--mute); font-size:.82rem; margin-bottom:8px; }
.rec { color:var(--ok); font-weight:600; } .grid { display:grid; grid-template-columns:1fr 1fr; gap:12px; font-size:.93rem; }
.lab { color:var(--mute); font-size:.72rem; text-transform:uppercase; letter-spacing:.05em; }
.choices { display:flex; gap:8px; flex-wrap:wrap; margin-top:12px; }
.choices label { flex:1 1 0; min-width:96px; text-align:center; border:1.5px solid var(--line); border-radius:8px; padding:10px 6px; cursor:pointer; font-weight:600; user-select:none; min-height:44px; }
.choices input { position:absolute; opacity:0; pointer-events:none; }
.choices input:focus-visible + span { outline:2px solid var(--gold); outline-offset:4px; }
.choices label:has(input[value=oui]:checked) { border-color:var(--ok); background:rgba(63,174,93,.15); }
.choices label:has(input[value=non]:checked) { border-color:var(--no); background:rgba(217,83,79,.15); }
.choices label:has(input[value=discuter]:checked) { border-color:var(--talk); background:rgba(224,163,58,.15); }
textarea { width:100%; margin-top:8px; background:#0d0e10; color:var(--ink); border:1px solid var(--line); border-radius:8px; padding:8px; font:inherit; min-height:44px; }
.bar { position:fixed; left:0; right:0; bottom:0; background:rgba(17,18,20,.96); border-top:1px solid var(--line); padding:12px 16px; }
.bar .in { max-width:860px; margin:0 auto; display:flex; gap:10px; align-items:center; flex-wrap:wrap; }
button { font:inherit; font-weight:600; border-radius:8px; padding:10px 16px; min-height:44px; cursor:pointer; border:1.5px solid var(--line); background:transparent; color:var(--ink); }
button.primary { background:var(--gold); border-color:var(--gold); color:#111; }
#status { color:var(--mute); font-size:.9rem; flex:1 1 200px; }
a { color:var(--gold); } ul { padding-left:18px; }
@media (max-width:640px) { .grid { grid-template-columns:1fr; } h1 { font-size:1.35rem; } }
"""

JS = """
const form = document.getElementById('f'), status = document.getElementById('status');
document.getElementById('allrec').onclick = () => {
  document.querySelectorAll('[data-rec="1"] input[value=oui]').forEach(i => { if (!i.closest('.item').querySelector('input:checked')) i.checked = true; });
  status.textContent = 'Recommended items set to Oui (not saved yet).';
};
form.onsubmit = async (ev) => {
  ev.preventDefault();
  const answers = {};
  document.querySelectorAll('.item').forEach(el => {
    const id = el.dataset.id, c = el.querySelector('input:checked'), t = el.querySelector('textarea').value.trim();
    if (c || t) answers[id] = { choice: c ? c.value : '', comment: t };
  });
  status.textContent = 'Saving…';
  try {
    const r = await fetch(location.pathname, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ answers, note: document.getElementById('note').value.trim() }) });
    const j = await r.json();
    status.textContent = r.ok ? `Saved ${j.count} answer(s) at ${j.at}${j.discord ? ' — sent to Discord' : ''}.` : (j.error || 'Error');
  } catch (e) { status.textContent = 'Could not save — check the connection and try again.'; }
};
"""


def page(title, body):
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex, nofollow">
<title>{e(title)}</title><style>{CSS}</style></head><body><main>{body}</main></body></html>"""


def render_index():
    rows = "".join(f'<li><a href="/r/{e(s)}">{e(r["client"])} — {e(r["title"])}</a> <span class="sub">{e(r.get("subtitle"))}</span></li>'
                   for s, r in reviews().items())
    return page("Reviews", f"<h1>Reviews</h1><p class='sub'>CoreCuity · private</p><ul>{rows or '<li>No review yet.</li>'}</ul>")


def render_review(review):
    state = saved(review["slug"])
    answers = state.get("answers", {})
    parts = [f"<h1>{e(review['client'])} — {e(review['title'])}</h1>",
             f"<p class='sub'>{e(review.get('subtitle'))}</p>",
             f"<div class='intro'>{e(review.get('intro'))}</div><form id='f'>"]
    for section in review["sections"]:
        parts.append(f"<h2>{e(section['id'])}. {e(section['title'])}</h2>")
        for item in section["items"]:
            current = answers.get(item["id"], {})
            rec = "<span class='rec'>Recommended</span> · " if item.get("recommended") else ""
            radios = "".join(
                f"<label><input type='radio' name='c_{e(item['id'])}' value='{k}'{' checked' if current.get('choice') == k else ''}><span>{v}</span></label>"
                for k, v in CHOICES.items())
            parts.append(
                f"<div class='item' data-id='{e(item['id'])}' data-rec='{1 if item.get('recommended') else 0}'>"
                f"<h3>{e(item['id'])} · {e(item['title'])}</h3>"
                f"<div class='meta'>{rec}effort {e(item.get('effort'))} · risk {e(item.get('risk'))}</div>"
                f"<div class='grid'><div><div class='lab'>Today</div>{e(item.get('today'))}</div>"
                f"<div><div class='lab'>Proposal</div>{e(item.get('proposal'))}</div></div>"
                f"<div class='choices'>{radios}</div>"
                f"<textarea placeholder='Comment (optional)' aria-label='Comment for {e(item['id'])}'>{e(current.get('comment'))}</textarea></div>")
    parts.append(f"<h2>General note</h2><textarea id='note' placeholder='Anything else (optional)'>{e(state.get('note'))}</textarea>")
    last = state["history"][-1]["at"] if state.get("history") else ""
    parts.append("</form><div class='bar'><div class='in'>"
                 "<button type='button' id='allrec'>All recommended → Oui</button>"
                 "<button class='primary' type='submit' form='f'>Save</button>"
                 f"<span id='status'>{'Last saved ' + e(last) if last else 'Not saved yet.'}</span></div></div>"
                 f"<script>{JS}</script>")
    return page(f"{review['client']} — {review['title']}", "".join(parts))


def post_discord(review, answers, note):
    if not WEBHOOK:
        return False
    lines = [f"📝 **{review['client']} — {review['title']}**: answers saved on review.corecuity.com"]
    order = [item["id"] for s in review["sections"] for item in s["items"]]
    for item_id in order:
        a = answers.get(item_id)
        if not a:
            continue
        text = f"{item_id} {CHOICES.get(a.get('choice'), '—')}"
        if a.get("comment"):
            text += f" — {a['comment']}"
        lines.append(text)
    if note:
        lines.append(f"Note: {note}")
    content = "\n".join(lines)
    ok = True
    for start in range(0, len(content), 1900):
        req = urllib.request.Request(WEBHOOK, data=json.dumps({"content": content[start:start + 1900],
                                     "allowed_mentions": {"parse": []}}).encode(),
                                     headers={"Content-Type": "application/json", "User-Agent": "corecuity-review/1"})
        try:
            urllib.request.urlopen(req, timeout=10).read()
        except Exception:
            ok = False
    return ok


class Handler(BaseHTTPRequestHandler):
    server_version = "review"

    def _send(self, code, body, ctype="text/html; charset=utf-8"):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Robots-Tag", "noindex, nofollow, noarchive")
        self.end_headers()
        self.wfile.write(data)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj, ensure_ascii=False), "application/json; charset=utf-8")

    def do_GET(self):
        path = self.path.split("?", 1)[0].rstrip("/") or "/"
        if path == "/":
            return self._send(200, render_index())
        if path == "/healthz":
            return self._send(200, "ok", "text/plain")
        if path.startswith("/r/"):
            review = reviews().get(path[3:])
            if review:
                return self._send(200, render_review(review))
        self._send(404, page("Not found", "<h1>Not found</h1>"))

    def do_POST(self):
        path = self.path.split("?", 1)[0].rstrip("/")
        review = reviews().get(path[3:]) if path.startswith("/r/") else None
        if not review:
            return self._json(404, {"error": "Unknown review"})
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY:
            return self._json(400, {"error": "Bad request"})
        try:
            body = json.loads(self.rfile.read(length))
        except ValueError:
            return self._json(400, {"error": "Bad JSON"})
        valid_ids = {item["id"] for s in review["sections"] for item in s["items"]}
        answers = {}
        for item_id, a in (body.get("answers") or {}).items():
            if item_id in valid_ids and isinstance(a, dict):
                choice = a.get("choice") if a.get("choice") in CHOICES else ""
                answers[item_id] = {"choice": choice, "comment": str(a.get("comment") or "")[:2000]}
        note = str(body.get("note") or "")[:4000]
        at = datetime.now(timezone.utc).astimezone().strftime("%d/%m/%Y %H:%M")
        with LOCK:
            DATA.mkdir(exist_ok=True)
            state = saved(review["slug"])
            state["answers"], state["note"] = answers, note
            state.setdefault("history", []).append({"at": at, "answers": answers, "note": note})
            tmp = DATA / f"{review['slug']}.json.tmp"
            tmp.write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding="utf-8")
            tmp.replace(DATA / f"{review['slug']}.json")
        sent = post_discord(review, answers, note)
        self._json(200, {"count": len(answers), "at": at, "discord": sent})

    def log_message(self, fmt, *args):
        pass  # Caddy keeps the access log


if __name__ == "__main__":
    load_env()
    WEBHOOK = os.environ.get("DISCORD_WEBHOOK_URL", "")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
