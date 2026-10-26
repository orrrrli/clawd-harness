#!/usr/bin/env python3
"""Create a GitHub backlog from manifest.json: Epics -> Story sub-issues ->
Task sub-issues, each assigned + labeled + added to a Project V2 with
Status/Sprint/Size/Estimate fields.

Generic + config-driven: all repo/owner/project settings come from the manifest
top-level. Idempotent + resumable via .state.json (re-running skips done work).
Throttled + retries on rate-limit and transient network errors.

Usage:
  python3 create_issues.py --manifest path/to/manifest.json --dry-run
  python3 create_issues.py --manifest path/to/manifest.json
  python3 create_issues.py --manifest path/to/manifest.json --limit 20

Manifest top-level keys used:
  repo (owner/name), owner (login), owner_type ("user"|"organization"),
  project_number (int), assignee (login). See references/manifest-schema.md.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

CREATE_SLEEP = 1.3   # seconds after each issue create (abuse-limit safety)
LINK_SLEEP = 0.5     # after sub-issue link / project add / field set
MAX_RETRIES = 6

LABEL_COLORS = {
    "type": "5319e7", "area:fullstack": "006b75", "area:backend": "1d76db", "area:frontend": "0e8a16",
    "area:design": "cc88dd", "area:qa": "00b8a9", "area:security": "b60205",
    "area:devops": "0052cc", "area:data": "5319e7", "area:mobile": "0e8a16",
    "fr": "fbca04", "phase": "d4c5f9", "epic": "c2e0c6",
}
POINTS = {"XS": 1, "S": 2, "M": 3, "L": 5, "XL": 8}


# ---------- shell helpers ----------

def run(args, stdin=None):
    p = subprocess.run(args, input=stdin, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def gh_retry(args, stdin=None):
    """Run gh with retry/backoff on rate-limit + transient network failures."""
    for attempt in range(1, MAX_RETRIES + 1):
        rc, out, err = run(args, stdin)
        if rc == 0:
            return out
        low = (err or "").lower()
        if any(s in low for s in ("rate limit", "secondary rate", "abuse",
                                  "too quickly", "exceeded a secondary")):
            wait = min(120, 20 * attempt)
            print(f"  rate-limited (attempt {attempt}); sleeping {wait}s...", flush=True)
            time.sleep(wait)
            continue
        if any(s in low for s in ("502", "503", "timeout", "temporarily",
                                  "connection reset", "read tcp", "broken pipe",
                                  "eof", "connection refused", "no such host",
                                  "i/o timeout")):
            time.sleep(5 * attempt)
            continue
        raise RuntimeError(f"gh failed: {' '.join(args)}\n{err}")
    raise RuntimeError(f"gh failed after {MAX_RETRIES} retries: {' '.join(args)}")


def load_json(path, default=None):
    if os.path.isfile(path):
        with open(path) as f:
            return json.load(f)
    return default


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


# ---------- label / id derivation ----------

def frs_of(epic):
    return re.findall(r"FR-?(\d+)", epic.get("fr", ""))


def epic_slug(epic_id):
    base = epic_id[len("EPIC-"):] if epic_id.startswith("EPIC-") else epic_id
    return "epic:" + base.lower()


def labels_for(kind, epic, area=None):
    out = [f"type:{kind}", epic_slug(epic["id"])]
    if epic.get("phase") is not None:
        out.append(f"phase:{epic['phase']}")
    out += [f"fr:{n}" for n in frs_of(epic)]
    if area:
        out.append(f"area:{area}")
    return out


def all_labels(m):
    labels = {"type:epic", "type:story", "type:task"}
    for e in m["epics"]:
        labels.add(epic_slug(e["id"]))
        if e.get("phase") is not None:
            labels.add(f"phase:{e['phase']}")
        for n in frs_of(e):
            labels.add(f"fr:{n}")
        for s in e["stories"]:
            labels.add(f"area:{s['area']}")
            for t in s["tasks"]:
                labels.add(f"area:{t['area']}")
    return sorted(labels)


def label_color(label):
    if label.startswith("type:"):
        return LABEL_COLORS["type"]
    if label.startswith("area:"):
        return LABEL_COLORS.get(label, "ededed")
    if label.startswith("fr:"):
        return LABEL_COLORS["fr"]
    if label.startswith("phase:"):
        return LABEL_COLORS["phase"]
    return LABEL_COLORS["epic"]


# ---------- bodies ----------

def epic_body(e, backlog_url):
    stories = "\n".join(f"- `{s['id']}` — {s['title']}" for s in e["stories"])
    meta = " · ".join(filter(None, [
        f"**Epic**", e.get("fr"),
        f"phase {e['phase']}" if e.get("phase") is not None else None,
        f"size {e['size']}" if e.get("size") else None,
        f"Sprint {e['sprint']}" if e.get("sprint") else None]))
    tail = f"\n\nBacklog: {backlog_url}" if backlog_url else ""
    return (f"{meta}\n\n{e.get('summary', '')}\n\n"
            f"**Stories ({len(e['stories'])}):**\n{stories}{tail}")


def story_body(e, s):
    ac = "\n".join(f"- {a}" for a in s.get("acceptance_criteria", []))
    tasks = "\n".join(f"- `{t['id']}` {t['title']}" for t in s["tasks"])
    screens = ("\n**Screens:** " + ", ".join(s["screens"])) if s.get("screens") else ""
    deps = ("\n**Depends on:** " + ", ".join(s["depends_on"])) if s.get("depends_on") else ""
    est = s.get("estimate", "?")
    pts = s.get("points", POINTS.get(est, "?"))
    meta = " · ".join(filter(None, [
        f"**Epic:** {e['id']}", f"**Area:** {s['area']}",
        f"**Estimate:** {est} ({pts} pts)",
        f"Sprint {s['sprint']}" if s.get("sprint") else None,
        e.get("fr"),
        f"phase {e['phase']}" if e.get("phase") is not None else None]))
    return (f"{s['title']}\n\n{meta}{screens}{deps}\n\n"
            f"**Acceptance criteria:**\n{ac}\n\n"
            f"**Tasks ({len(s['tasks'])})** (tracked as sub-issues):\n{tasks}")


def task_body(e, s, t):
    ph = f" · phase {e['phase']}" if e.get("phase") is not None else ""
    return (f"Task of **{s['id']}** (epic **{e['id']}**) · `area:{t['area']}`{ph}.\n\n"
            f"{t['title']}")


# ---------- GitHub: labels + issues + sub-issues ----------

def ensure_labels(repo, m, dry):
    for label in all_labels(m):
        if dry:
            print(f"  label: {label}")
            continue
        gh_retry(["gh", "label", "create", label, "--repo", repo,
                  "--color", label_color(label), "--force"])


def create_issue(repo, owner, title, body, labels):
    payload = json.dumps({"title": title, "body": body, "labels": labels,
                          "assignees": [owner] if owner else []})
    out = gh_retry(["gh", "api", "--method", "POST", f"repos/{repo}/issues",
                    "--input", "-"], stdin=payload)
    d = json.loads(out)
    time.sleep(CREATE_SLEEP)
    return {"number": d["number"], "id": d["id"], "node_id": d["node_id"]}


def link_sub_issue(repo, parent_number, child_id):
    gh_retry(["gh", "api", "--method", "POST",
              f"repos/{repo}/issues/{parent_number}/sub_issues",
              "-F", f"sub_issue_id={child_id}"])
    time.sleep(LINK_SLEEP)


# ---------- GitHub: Project V2 fields ----------

def add_to_project(project_id, node_id):
    q = ("mutation($p:ID!,$c:ID!){addProjectV2ItemById(input:{projectId:$p,"
         "contentId:$c}){item{id}}}")
    try:
        out = gh_retry(["gh", "api", "graphql", "-f", f"query={q}",
                        "-F", f"p={project_id}", "-F", f"c={node_id}"])
        time.sleep(LINK_SLEEP)
        return json.loads(out)["data"]["addProjectV2ItemById"]["item"]["id"]
    except RuntimeError as e:
        if "Content already exists" not in str(e):
            raise
        lookup = ("query($c:ID!){node(id:$c){...on Issue{projectItems(first:50)"
                  "{nodes{id project{id}}}}}}")
        out = gh_retry(["gh", "api", "graphql", "-f", f"query={lookup}",
                        "-F", f"c={node_id}"])
        time.sleep(LINK_SLEEP)
        items = json.loads(out)["data"]["node"]["projectItems"]["nodes"]
        for it in items:
            if it["project"]["id"] == project_id:
                return it["id"]
        raise RuntimeError(f"add_to_project: 'already exists' but no matching project item found for {node_id}")


def set_single_select(project_id, item_id, field_id, option_id):
    # -f forces strings: all-digit option ids would be coerced to int by -F.
    q = ("mutation($p:ID!,$i:ID!,$f:ID!,$o:String!){updateProjectV2ItemFieldValue("
         "input:{projectId:$p,itemId:$i,fieldId:$f,value:{singleSelectOptionId:$o}})"
         "{projectV2Item{id}}}")
    gh_retry(["gh", "api", "graphql", "-f", f"query={q}", "-f", f"p={project_id}",
              "-f", f"i={item_id}", "-f", f"f={field_id}", "-f", f"o={option_id}"])
    time.sleep(LINK_SLEEP)


def set_number(project_id, item_id, field_id, number):
    q = ("mutation($p:ID!,$i:ID!,$f:ID!){updateProjectV2ItemFieldValue("
         "input:{projectId:$p,itemId:$i,fieldId:$f,value:{number:%s}})"
         "{projectV2Item{id}}}" % float(number))
    gh_retry(["gh", "api", "graphql", "-f", f"query={q}", "-F", f"p={project_id}",
              "-F", f"i={item_id}", "-F", f"f={field_id}"])
    time.sleep(LINK_SLEEP)


def gql_options(opts):
    """opts: list of (name, color_enum, description) -> GraphQL literal array."""
    parts = [f"{{name:{json.dumps(n)},color:{c},description:{json.dumps(d or '')}}}"
             for n, c, d in opts]
    return "[" + ",".join(parts) + "]"


def fetch_fields(owner, owner_type, number):
    q = ('query{%s(login:"%s"){projectV2(number:%d){id '
         'fields(first:50){nodes{__typename '
         '... on ProjectV2FieldCommon{id name dataType} '
         '... on ProjectV2SingleSelectField{id name '
         'options{id name color description}}}}}}}'
         % (owner_type, owner, number))
    out = gh_retry(["gh", "api", "graphql", "-f", f"query={q}"])
    d = json.loads(out)["data"][owner_type]["projectV2"]
    return d["id"], {f["name"]: f for f in d["fields"]["nodes"] if f.get("name")}


def create_single_select(project_id, name, opts):
    q = ('mutation{createProjectV2Field(input:{projectId:"%s",dataType:SINGLE_SELECT,'
         'name:%s,singleSelectOptions:%s}){projectV2Field{'
         '... on ProjectV2SingleSelectField{id options{id name}}}}}'
         % (project_id, json.dumps(name), gql_options(opts)))
    out = gh_retry(["gh", "api", "graphql", "-f", f"query={q}"])
    f = json.loads(out)["data"]["createProjectV2Field"]["projectV2Field"]
    return f["id"], {o["name"]: o["id"] for o in f["options"]}


def create_number_field(project_id, name):
    q = ('mutation{createProjectV2Field(input:{projectId:"%s",dataType:NUMBER,'
         'name:%s}){projectV2Field{... on ProjectV2FieldCommon{id}}}}'
         % (project_id, json.dumps(name)))
    out = gh_retry(["gh", "api", "graphql", "-f", f"query={q}"])
    return json.loads(out)["data"]["createProjectV2Field"]["projectV2Field"]["id"]


def ensure_status_backlog(project_id, fields):
    status = fields.get("Status")
    if not status:
        return create_single_select(project_id, "Status", [
            ("Backlog", "GRAY", "Triaged, not yet started"),
            ("Ready", "BLUE", ""), ("In progress", "YELLOW", ""),
            ("In review", "ORANGE", ""), ("Done", "GREEN", "")])[0:2]
    opts = status["options"]
    backlog = next((o["id"] for o in opts if o["name"].lower() == "backlog"), None)
    if backlog:
        return status["id"], backlog
    new = [("Backlog", "GRAY", "Triaged, not yet started")] + \
          [(o["name"], o.get("color") or "GRAY", o.get("description") or "") for o in opts]
    q = ('mutation{updateProjectV2Field(input:{fieldId:"%s",singleSelectOptions:%s})'
         '{projectV2Field{... on ProjectV2SingleSelectField{options{id name}}}}}'
         % (status["id"], gql_options(new)))
    out = gh_retry(["gh", "api", "graphql", "-f", f"query={q}"])
    o = json.loads(out)["data"]["updateProjectV2Field"]["projectV2Field"]["options"]
    return status["id"], next(x["id"] for x in o if x["name"].lower() == "backlog")


def ensure_sprint(project_id, fields, max_sprint):
    fld = fields.get("Sprint")
    if fld and fld.get("options"):
        return fld["id"], {o["name"]: o["id"] for o in fld["options"]}
    opts = [(f"Sprint {i}", "BLUE", "") for i in range(1, max_sprint + 1)]
    return create_single_select(project_id, "Sprint", opts)


def ensure_size(project_id, fields):
    fld = fields.get("Size")
    if fld and fld.get("options"):
        return fld["id"], {o["name"]: o["id"] for o in fld["options"]}
    opts = [("XS", "GRAY", ""), ("S", "BLUE", ""), ("M", "GREEN", ""),
            ("L", "YELLOW", ""), ("XL", "RED", "")]
    return create_single_select(project_id, "Size", opts)


def ensure_estimate(project_id, fields):
    fld = fields.get("Estimate")
    return fld["id"] if fld else create_number_field(project_id, "Estimate")


def fetch_project_meta(owner, owner_type, number, max_sprint):
    pid, fields = fetch_fields(owner, owner_type, number)
    status_id, backlog_id = ensure_status_backlog(pid, fields)
    sprint_id, sprint_opts = ensure_sprint(pid, fields, max_sprint)
    size_id, size_opts = ensure_size(pid, fields)
    return {"project_id": pid, "status_field_id": status_id, "backlog_id": backlog_id,
            "sprint_field_id": sprint_id, "sprint_options": sprint_opts,
            "size_field_id": size_id, "size_options": size_opts,
            "estimate_field_id": ensure_estimate(pid, fields)}


# ---------- orchestration ----------

class LimitReached(Exception):
    pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default="manifest.json")
    ap.add_argument("--state", default=None, help="resume ledger (default: <manifest dir>/.state.json)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=None, help="max NEW issues this run")
    args = ap.parse_args()

    m = load_json(args.manifest)
    if m is None:
        sys.exit(f"manifest not found: {args.manifest}")
    normalize(m)
    state_path = args.state or os.path.join(os.path.dirname(os.path.abspath(args.manifest)), ".state.json")

    repo = m["repo"]
    owner = m.get("assignee") or m.get("owner")
    proj_owner = m.get("project_owner") or m.get("owner")
    owner_type = m.get("owner_type", "user")
    number = m["project_number"]
    backlog_url = m.get("backlog_url", "")
    max_sprint = max([e.get("sprint", 1) for e in m["epics"]] + [1])

    counts = {"epics": len(m["epics"]),
              "stories": sum(len(e["stories"]) for e in m["epics"]),
              "tasks": sum(len(s["tasks"]) for e in m["epics"] for s in e["stories"])}
    total = sum(counts.values())
    print(f"{'DRY RUN: ' if args.dry_run else ''}creating {counts['epics']} epics + "
          f"{counts['stories']} stories + {counts['tasks']} tasks = {total} issues "
          f"in {repo}, project #{number} ({proj_owner}), assignee {owner or '(none)'}.")

    state = load_json(state_path, {})
    meta = None
    if not args.dry_run:
        meta = fetch_project_meta(proj_owner, owner_type, number, max_sprint)
        print(f"project={meta['project_id']} backlog={meta['backlog_id']}")

    # Collect all repos used (global + per-story overrides)
    all_repos = {repo}
    for e in m["epics"]:
        for s in e["stories"]:
            if s.get("repo"):
                all_repos.add(s["repo"])
    print(f"Ensuring labels on {len(all_repos)} repo(s): {', '.join(sorted(all_repos))}")
    for r in sorted(all_repos):
        ensure_labels(r, m, args.dry_run)
    created_this_run = [0]

    def save():
        with open(state_path, "w") as f:
            json.dump(state, f, indent=2)

    def ensure_issue(key, title, body, labels, issue_repo=None):
        r = issue_repo or repo
        rec = state.get(key)
        if rec and rec.get("number"):
            if not args.dry_run and rec.get("title") != title:
                print(f"  ~ {key}: title -> {title[:70]}", flush=True)
                gh_retry(["gh", "api", "--method", "PATCH",
                          f"repos/{r}/issues/{rec['number']}", "--input", "-"],
                         stdin=json.dumps({"title": title}))
                time.sleep(LINK_SLEEP)
                rec["title"] = title
                state[key] = rec; save()
            return rec
        if args.dry_run:
            print(f"  + {key}: {title[:70]}")
            rec = {"number": 0, "id": 0, "node_id": "DRY", "title": title}
        else:
            print(f"  + {key}", flush=True)
            rec = create_issue(r, owner, title, body, labels)
            rec["title"] = title
            created_this_run[0] += 1
        rec["repo"] = r
        for k in ("linked", "status_set", "sprint_set", "size_set", "estimate_set"):
            rec.setdefault(k, False)
        rec.setdefault("item_id", None)
        state[key] = rec
        if not args.dry_run:
            save()
        if args.limit is not None and created_this_run[0] >= args.limit:
            raise LimitReached()
        return rec

    def ensure_link(key, parent_number, child, parent_key=None):
        if args.dry_run or state[key].get("linked"):
            return
        child_repo = state[key].get("repo", repo)
        parent_repo = state[parent_key].get("repo", repo) if parent_key else repo
        if child_repo != parent_repo:
            print(f"  ~ skip cross-repo link: {key} (repo={child_repo} != {parent_repo})",
                  flush=True)
            state[key]["linked"] = True
            save()
            return
        link_sub_issue(child_repo, parent_number, child["id"])
        state[key]["linked"] = True
        save()

    def ensure_fields(key, rec, sprint=None, size=None, points=None):
        if args.dry_run or meta is None:
            return
        pid = meta["project_id"]
        if not rec.get("item_id"):
            rec["item_id"] = add_to_project(pid, rec["node_id"])
            state[key] = rec; save()
        if not rec.get("status_set"):
            set_single_select(pid, rec["item_id"], meta["status_field_id"], meta["backlog_id"])
            rec["status_set"] = True; state[key] = rec; save()
        if sprint and not rec.get("sprint_set"):
            opt = meta["sprint_options"].get(f"Sprint {sprint}")
            if opt:
                set_single_select(pid, rec["item_id"], meta["sprint_field_id"], opt)
            rec["sprint_set"] = True; state[key] = rec; save()
        if size and not rec.get("size_set"):
            opt = meta["size_options"].get(size)
            if opt:
                set_single_select(pid, rec["item_id"], meta["size_field_id"], opt)
            rec["size_set"] = True; state[key] = rec; save()
        if points is not None and not rec.get("estimate_set"):
            set_number(pid, rec["item_id"], meta["estimate_field_id"], points)
            rec["estimate_set"] = True; state[key] = rec; save()

    try:
        for e in m["epics"]:
            erec = ensure_issue(e["id"], f"{e['id']}: {e['title']}",
                                epic_body(e, backlog_url), labels_for("epic", e))
            epic_pts = sum(s.get("points", POINTS.get(s.get("estimate", ""), 0))
                           for s in e["stories"])
            ensure_fields(e["id"], erec, e.get("sprint"), e.get("size"), epic_pts or None)
            for s in e["stories"]:
                s_repo = s.get("repo") or repo
                srec = ensure_issue(s["id"], f"{s['id']}: {s['title']}",
                                    story_body(e, s), labels_for("story", e, s["area"]), s_repo)
                ensure_link(s["id"], erec["number"], srec, e["id"])
                pts = s.get("points", POINTS.get(s.get("estimate", "")))
                ensure_fields(s["id"], srec, s.get("sprint") or e.get("sprint"),
                              s.get("estimate"), pts)
                for t in s["tasks"]:
                    t_repo = t.get("repo") or s_repo
                    trec = ensure_issue(t["id"], f"{t['id']}: {t['title']}",
                                        task_body(e, s, t), labels_for("task", e, t["area"]), t_repo)
                    ensure_link(t["id"], srec["number"], trec, s["id"])
                    ensure_fields(t["id"], trec, t.get("sprint") or e.get("sprint"))
    except LimitReached:
        print(f"--limit reached ({args.limit} new this run); stopping (resumable).")

    done = sum(1 for v in state.values() if isinstance(v, dict) and v.get("number"))
    print(f"Done. {'(dry run) ' if args.dry_run else ''}issues in state: {done}")


if __name__ == "__main__":
    main()
