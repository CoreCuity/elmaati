#!/usr/bin/env python3
"""Elmaati tool backend: search the CoreCuity MemPalace.

Called by the bridge (server/bridge.mjs) when Gemini issues a `mempalace_search`
tool call. Reads the query from argv[1], prints a compact JSON result to stdout.
Uses the same hybrid (vector + BM25) path the MemPalace MCP server uses.
"""
import sys
import os
import json

PALACE = os.environ.get("PALACE_PATH", "/Users/najlio/Projects/corecuity/.palace")


def main() -> None:
    query = sys.argv[1].strip() if len(sys.argv) > 1 else ""
    if not query:
        print(json.dumps({"results": [], "error": "empty query"}))
        return
    try:
        from mempalace.searcher import search_memories
        res = search_memories(query, PALACE, n_results=5, candidate_strategy="union")
    except Exception as e:  # noqa: BLE001 — surface any failure to the model
        print(json.dumps({"results": [], "error": str(e)}))
        return

    out = []
    for r in (res.get("results") or [])[:5]:
        text = (r.get("text") or "").strip()
        # Strip YAML frontmatter noise; keep it short for a spoken answer.
        out.append({
            "text": text[:600],
            "wing": r.get("wing"),
            "room": r.get("room"),
        })
    print(json.dumps({"query": query, "results": out}, ensure_ascii=False))


if __name__ == "__main__":
    main()
