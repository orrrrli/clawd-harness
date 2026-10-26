# Golden cases and real-data corpus

Read this only when an inventory row has `Golden: yes`, or when the user has database access.
Paths come from `.claude/migration.md` (config keys `Golden cases` and `Real data`).

## Golden cases

For a `same` row backed by a pure legacy function with many branches or time/number arithmetic
(conflicts, hours, quotas), a handful of hand examples leaves gaps. Write one generator per legacy
function while building the capability that owns the row:

- `docs/migration/<module>/golden/<function>.<ext>`: a verbatim copy of the legacy function with
  its `file:line` in a comment, an input generator with a fixed seed (~500 random cases, plus every
  edge case of the row), and a writer for the cases file. Use the legacy language's plain runtime
  (node for JS), no dependencies. Running it twice gives the same file.
- Cases file: `{ "source": "<file:line>", "cases": [ { "input": ..., "expected": ... } ] }`,
  in the config's golden cases path for the test project that tests the new code
  (`<golden path>/<module>/<function>.json`, copied to the test output if the runner needs it).
- Turn it into a data-driven test (xunit `[Theory]` reading the JSON with `System.Text.Json`,
  Vitest `it.each`, or the project's equivalent). One test case per golden case, so a failure
  names its input. The data source also loads the local real cases (next section) when that file
  exists, and never fails because it is missing.
- Never hand-edit a cases file. A wrong expected value means the legacy does that: port it, or
  show the user a new `fixed` row.
- `fixed` rows never get golden cases: the legacy is not the oracle for them.

## Real-data corpus (local only)

Real records never enter git. The config's `Real data` key says why and who must approve any
exception; without one, treat every record as personal data.

- Until the user has database access, rows with logic stay `Real data: pending`. Capabilities
  advance normally.
- With access: export the module's records read-only to `docs/migration/<module>/real/` and pass
  each record through the golden generators to write `real-<function>.json` next to the cases file.
  Both paths are gitignored (`migration/*/real/` and `**/real-*.json` under the golden path);
  create those entries the first time and check with `git status` that nothing real is staged.
- Run the golden tests with the real cases. Every mismatch is a regression or a new row: report
  it with input and both outputs, STOP. Record the run (date, record count, result, no data) in
  the row and set `Real data: done`.
