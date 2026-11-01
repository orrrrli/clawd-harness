---
name: pr-body
stacks: [all]
description: Write a pull request title and body. Use whenever opening or updating a PR, or when the user asks for a PR description.
---

# PR Body

Write the body so a teammate who didn't follow the ticket understands it in two minutes.
Simple, concise, but every decision says why.
A repo's own PR template or rules add to this; where they clash, the repo wins.

Length: ~30-50 lines. Sections, in this order, each only when it has content:
- `## What`: ticket link, what the user can do now and why it matters. 2-3 sentences.
- `## Order`: another PR must merge first, and what breaks if it doesn't.
- `## How <mechanism> works`: when a reviewer would ask "who calls this?" (event, job, webhook,
  trigger). One small diagram, one line per piece, and its known limit.
- `## How`: numbered, one decision per item: what it does + why, in the same line.
- `## Not changed`: what's left out on purpose, with ticket ids.
- `## Test plan`: new tests by name and what they prove + the manual run + evidence. The PR's
  green checks speak for the full suite. Add the suite total, before → after with the reason,
  only when the PR can make fewer tests run without anything failing: it deletes, moves or
  disables tests, or touches test infrastructure (CI workflow, schemes or targets, shared test
  helpers). Take both numbers from green CI runs (base branch and this PR), never a local guess.
- `## Reviewer notes`: traps for the next person who touches this.

Writing:
- Plain English, short sentences, one idea each. No dense bullets that pack three decisions.
- Leave out what git or the code already says: commit list, file-by-file tours, details already
  in doc comments. Side suggestions go to the issue tracker, not the PR.
- Right before publishing, and again after merging the base branch: check every number
  (migration, test count) against the branch, and make sure related PRs don't contradict each other.
