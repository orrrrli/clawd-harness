#!/usr/bin/env python3
"""Render a backlog markdown page from manifest.json, and optionally inject a
summary section into a PRD and/or mirror both into a wiki clone.

Usage:
  python3 render_docs.py --manifest manifest.json --out docs/engineering-backlog.md
  python3 render_docs.py --manifest manifest.json --out docs/engineering-backlog.md \
      --prd docs/prd.md --prd-section 14 --prd-anchor "## Appendix"
  python3 render_docs.py --manifest manifest.json --out docs/engineering-backlog.md \
      --wiki /tmp/MyRepo.wiki --wiki-backlog Engineering-Backlog.md --wiki-prd PRD.md

Always runs assertions (unique ids; every epic has >=1 story; every story has
area + >=1 task). Idempotent: PRD injection replaces a marked block in place.
"""
import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict

AREA_ORDER = ["fullstack", "backend", "frontend", "design", "qa", "security", "devops",
              "data", "mobile"]
POINTS = {"XS": 1, "S": 2, "M": 3, "L": 5, "XL": 8}
START = "<!-- BACKLOG:START -->"
END = "<!-- BACKLOG:END -->"


def load(path):
    with open(path) as f:
        return normalize(json.load(f))


def normalize(m):
    """Expand string tasks into {id, area, title} dicts; backfill points."""
    for e in m["epics"]:
        for s in e["stories"]:
            s.setdefault("points", POINTS.get(s.get("estimate", ""), 0))
            norm = []
            for i, t in enumerate(s.get("tasks", []), 1):
                if isinstance(t, str):
                    norm.append({"id": f"{s['id']}-T{i}", "area": s["area"], "title": t})
                else:
                    t.setdefault("id", f"{s['id']}-T{i}")
                    t.setdefault("area", s["area"])
                    norm.append(t)
            s["tasks"] = norm
    return m


def counts(m):
    return {"epics": len(m["epics"]),
            "stories": sum(len(e["stories"]) for e in m["epics"]),
            "tasks": sum(len(s["tasks"]) for e in m["epics"] for s in e["stories"])}


def area_counts(stories):
    c = Counter(s["area"] for s in stories)
    extra = [a for a in c if a not in AREA_ORDER]
    return " + ".join(f"{c[a]} {a}" for a in AREA_ORDER + extra if c[a])


def header(m):
    c = counts(m)
    total = sum(c.values())
    proj = ""
    if m.get("project_number"):
        proj = (f"\n**Tracked in:** [Project #{m['project_number']}]"
                f"(https://github.com/users/{m.get('project_owner') or m.get('owner')}"
                f"/projects/{m['project_number']}) · assignee `{m.get('assignee', '')}`.")
    return (f"# Engineering Backlog — {m.get('project_title', m.get('repo', ''))}\n\n"
            f"**Generated from** the backlog manifest (single source of truth — "
            f"edit the manifest and re-run `render_docs.py`).\n"
            f"**Totals:** {c['epics']} epics · {c['stories']} stories · {c['tasks']} "
            f"tasks = **{total} GitHub issues**.{proj}\n\n"
            "| Level | GitHub object | Labels |\n|---|---|---|\n"
            "| Epic | parent Issue | `type:epic`, `epic:<slug>`, `phase:N`, `fr:N` |\n"
            "| Story | sub-issue of epic | `type:story`, `area:*` |\n"
            "| Task | sub-issue of story | `type:task`, `area:*` |\n\n---\n")


def render_sprint_plan(m):
    if not any(e.get("sprint") for e in m["epics"]):
        return ""
    by = defaultdict(list)
    for e in m["epics"]:
        by[e.get("sprint")].append(e)
    rows = []
    for spr in sorted(k for k in by if k is not None):
        es = by[spr]
        phases = ", ".join(sorted({str(e["phase"]) for e in es if e.get("phase") is not None}))
        epics = ", ".join(f"{e['id']} ({e.get('size', '?')})" for e in es)
        rows.append(f"| Sprint {spr} | {phases or '—'} | {epics} |")
    return ("## Sprint plan\n\n| Sprint | Phase | Epics (size) |\n|---|---|---|\n"
            + "\n".join(rows) + "\n\n---\n")


def render_full(m):
    out = [header(m), render_sprint_plan(m)]
    for e in m["epics"]:
        nt = sum(len(s["tasks"]) for s in e["stories"])
        meta = " · ".join(filter(None, [
            e.get("fr"),
            f"phase {e['phase']}" if e.get("phase") is not None else None,
            f"size {e['size']}" if e.get("size") else None,
            f"Sprint {e['sprint']}" if e.get("sprint") else None,
            f"{area_counts(e['stories'])} stories", f"{nt} tasks"]))
        out.append(f"## {e['id']} — {e['title']}")
        out.append(f"*{meta}*\n")
        if e.get("summary"):
            out.append(f"{e['summary']}\n")
        for s in e["stories"]:
            screens = (" · screens: " + ", ".join(s["screens"])) if s.get("screens") else ""
            deps = (" · depends on: " + ", ".join(s["depends_on"])) if s.get("depends_on") else ""
            est = s.get("estimate", "?")
            pts = s.get("points", POINTS.get(est, "?"))
            out.append(f"### {s['id']} — {s['title']}")
            out.append(f"`area:{s['area']}` · estimate {est} ({pts} pts)"
                       f"{(' · Sprint ' + str(s['sprint'])) if s.get('sprint') else ''}"
                       f"{screens}{deps}\n")
            if s.get("acceptance_criteria"):
                out.append("**Acceptance criteria:**")
                out += [f"- {a}" for a in s["acceptance_criteria"]]
            out.append(f"\n**Tasks ({len(s['tasks'])}):**")
            out += [f"- `{t['id']}` {t['title']}" for t in s["tasks"]]
            out.append("")
        out.append("---\n")
    out.append(render_traceability(m))
    return "\n".join(out)


def _frnum(x):
    mm = re.search(r"\d+", x)
    return int(mm.group()) if mm else 0


def render_traceability(m):
    frs = sorted({fr for e in m["epics"] for fr in re.findall(r"FR-?\d+", e.get("fr", ""))},
                 key=_frnum)
    if not frs:
        return ""
    areas = [a for a in AREA_ORDER if any(s["area"] == a
             for e in m["epics"] for s in e["stories"])]
    head = ("## Traceability (FR → stories by area)\n\n"
            "| FR | " + " | ".join(a.capitalize() for a in areas) + " |\n"
            "|---|" + "|".join(["---"] * len(areas)) + "|\n")
    rows = []
    for fr in frs:
        cells = {a: [] for a in areas}
        for e in m["epics"]:
            if fr in re.findall(r"FR-?\d+", e.get("fr", "")):
                for s in e["stories"]:
                    if s["area"] in cells:
                        cells[s["area"]].append(s["id"])
        rows.append("| " + fr + " | "
                    + " | ".join(", ".join(cells[a]) or "—" for a in areas) + " |")
    return head + "\n".join(rows) + "\n"


def render_summary(m, backlog_link):
    c = counts(m)
    total = sum(c.values())
    section = m.get("prd_section", "")
    lines = [START,
             f"## {section + '. ' if section else ''}Engineering Backlog (Epics → Stories → Tasks)\n",
             f"This backlog decomposes the requirements into a GitHub-ready hierarchy: "
             f"**{c['epics']} epics → {c['stories']} stories → {c['tasks']} tasks** "
             f"(**{total} issues**). Full detail (acceptance criteria, tasks, sprint "
             f"plan, traceability) lives in {backlog_link}.\n",
             "| Epic | FR | Ph | Spr | Size | "
             + " | ".join(a[:3].upper() for a in AREA_ORDER[:7]) + " | Tasks |\n"
             + "|---|---|---|---|---|" + "|".join(["---"] * 7) + "|---|"]
    for e in m["epics"]:
        st = e["stories"]
        nt = sum(len(s["tasks"]) for s in st)
        counts_by = [str(sum(1 for s in st if s["area"] == a)) for a in AREA_ORDER[:7]]
        lines.append(f"| {e['id']} {e['title']} | {e.get('fr', '')} | "
                     f"{e.get('phase', '')} | {e.get('sprint', '')} | {e.get('size', '')} | "
                     + " | ".join(counts_by) + f" | {nt} |")
    lines += ["", END]
    return "\n".join(lines)


def inject_prd(path, summary):
    with open(path) as f:
        text = f.read()
    if START in text and END in text:
        text = re.sub(re.escape(START) + r".*?" + re.escape(END), lambda _: summary,
                      text, flags=re.DOTALL)
    else:
        text = text.rstrip() + "\n\n---\n\n" + summary + "\n"
    with open(path, "w") as f:
        f.write(text)


def write(path, content):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w") as f:
        f.write(content if content.endswith("\n") else content + "\n")
    print(f"wrote {path}")


def assertions(m):
    errors = []
    ids = []
    for e in m["epics"]:
        ids.append(e["id"])
        if not e["stories"]:
            errors.append(f"{e['id']}: no stories")
        for s in e["stories"]:
            ids.append(s["id"])
            if not s.get("area"):
                errors.append(f"{s['id']}: missing area")
            if not s["tasks"]:
                errors.append(f"{s['id']}: no tasks")
            for t in s["tasks"]:
                ids.append(t["id"])
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    if dupes:
        errors.append(f"duplicate ids: {dupes}")
    # optional screen coverage if manifest declares a screen universe
    universe = m.get("screens") or []
    if universe:
        owned = set()
        for e in m["epics"]:
            for s in e["stories"]:
                owned.update(s.get("screens", []))
        miss = [x for x in universe if x not in owned]
        if miss:
            errors.append(f"screens not owned by any story: {miss}")
    if errors:
        print("ASSERTIONS FAILED:\n  " + "\n  ".join(errors), file=sys.stderr)
        sys.exit(1)
    print(f"Assertions OK: {len(ids)} unique ids"
          + (f"; all {len(universe)} screens owned" if universe else "") + ".")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default="manifest.json")
    ap.add_argument("--out", required=True, help="backlog markdown output path")
    ap.add_argument("--prd", help="PRD file to inject the summary section into")
    ap.add_argument("--prd-section", help="section number for the injected heading")
    ap.add_argument("--wiki", help="wiki clone dir (mirrors backlog + PRD)")
    ap.add_argument("--wiki-backlog", default="Engineering-Backlog.md")
    ap.add_argument("--wiki-prd", help="PRD filename inside the wiki dir")
    args = ap.parse_args()

    m = load(args.manifest)
    if args.prd_section:
        m["prd_section"] = args.prd_section
    assertions(m)

    full = render_full(m)
    write(args.out, full)
    if args.wiki and os.path.isdir(args.wiki):
        write(os.path.join(args.wiki, args.wiki_backlog), full)

    if args.prd and os.path.isfile(args.prd):
        rel = "./" + os.path.basename(args.out)
        inject_prd(args.prd, render_summary(m, f"[`{os.path.basename(args.out)}`]({rel})"))
        print(f"injected summary into {args.prd}")
    if args.wiki and args.wiki_prd:
        wp = os.path.join(args.wiki, args.wiki_prd)
        if os.path.isfile(wp):
            inject_prd(wp, render_summary(m, f"[[{args.wiki_backlog[:-3]}]]"))
            print(f"injected summary into {wp}")


if __name__ == "__main__":
    main()
