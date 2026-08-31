# oazon-mm-daily-log Windows Compatibility and Token Reduction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Mattermost fetcher work on Windows without shell-shim or encoding failures and reduce the runtime skill instructions without losing safety or report-quality constraints.

**Architecture:** Add one platform-aware OpenCLI command resolver and one UTF-8 subprocess boundary, then keep `open_site` and `run_eval` platform-neutral. Treat `SKILL.md` as a compact workflow router and retain detailed writing, API, and writeback guidance in existing references.

**Tech Stack:** Python 3 standard library, `unittest`, Markdown, Git/Bash repository checks.

---

### Task 1: Add failing compatibility and skill-contract tests

**Files:**
- Create: `skills/content/reports/oazon-mm-daily-log/tests/test_fetch_mm_day.py`
- Create: `skills/content/reports/oazon-mm-daily-log/tests/test_skill_contract.py`

- [ ] **Step 1: Test Windows command resolution, POSIX fallback, UTF-8 output, and existing date bounds**

Use `importlib.util` to load `scripts/fetch_mm_day.py`. Build a temporary npm-style directory and assert that Windows resolves to `[node.exe, .../main.js]`; patch the resolver to run `sys.executable` for a Unicode output test. Preserve an Asia/Shanghai day-boundary assertion.

- [ ] **Step 2: Test the compact skill contract**

Assert that `SKILL.md` is at most 100 lines and 6144 bytes, retains `只写本人`, `完整读`, `约 8h`, `30 字`, `真实`, `Boost`, `备份`, `diff`, `用户确认`, and `只读`, and names all three reference files with conditional loading language.

- [ ] **Step 3: Run tests and verify RED**

Run:

```powershell
python3 -m unittest discover -s skills/content/reports/oazon-mm-daily-log/tests -v
```

Expected: compatibility tests fail because the resolver/runner do not exist; contract test fails because the current skill is 143 lines and over 6KB.

### Task 2: Implement the cross-platform OpenCLI boundary

**Files:**
- Modify: `skills/content/reports/oazon-mm-daily-log/scripts/fetch_mm_day.py`
- Test: `skills/content/reports/oazon-mm-daily-log/tests/test_fetch_mm_day.py`

- [ ] **Step 1: Add command resolution**

Add `shutil` and `pathlib.Path`, then implement:

```python
def resolve_opencli_command(os_name: str | None = None,
                            which=shutil.which) -> list[str]:
    current_os = os_name or os.name
    if current_os != "nt":
        executable = which("opencli")
        if not executable:
            raise RuntimeError("PATH 中找不到 opencli")
        return [executable]

    node = which("node")
    shim = which("opencli.cmd") or which("opencli")
    if not node or not shim:
        raise RuntimeError("Windows 下找不到 node 或 opencli.cmd")
    entry = (Path(shim).resolve().parent / "node_modules" / "@jackwener" /
             "opencli" / "dist" / "src" / "main.js")
    if not entry.is_file():
        raise RuntimeError(f"找不到 OpenCLI Node 入口：{entry}")
    return [node, str(entry)]
```

- [ ] **Step 2: Add one UTF-8 subprocess runner**

```python
def run_opencli(args: list[str], timeout: int) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [*resolve_opencli_command(), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=timeout,
    )
```

Change `open_site` and `run_eval` to call this helper while preserving their current error messages and JSON parsing.

- [ ] **Step 3: Run compatibility tests and verify GREEN**

Run the unittest discovery command. Expected: fetcher tests pass; only the skill-size contract remains red.

### Task 3: Rewrite SKILL.md as a compact workflow router

**Files:**
- Modify: `skills/content/reports/oazon-mm-daily-log/SKILL.md`
- Test: `skills/content/reports/oazon-mm-daily-log/tests/test_skill_contract.py`

- [ ] **Step 1: Preserve trigger metadata and essential workflow**

Keep the skill name and trigger coverage. Retain defaults, the fetch command and artifacts, full relevant-message reading, personal attribution, output constraints, sanity checks, and the gated `daily.md` writeback flow.

- [ ] **Step 2: Apply progressive disclosure**

Require `report-format.md` only before drafting, `mattermost-api.md` only when identity/date/count checks fail, and `daily-md.md` only when writeback is requested. Remove repeated examples and duplicate checklists from the main body.

- [ ] **Step 3: Run all tests and verify GREEN**

Expected: all compatibility and skill-contract tests pass; `SKILL.md` is no more than 100 lines and 6KB.

### Task 4: Verify, commit, and push

**Files:**
- Verify all files above plus the design and plan documents.

- [ ] **Step 1: Run a real Windows smoke test**

Run `opencli doctor`, import the fetcher, resolve the command prefix, and use `run_opencli` to evaluate a read-only expression returning the current URL and `/api/v4/users/me` status.

- [ ] **Step 2: Run repository checks**

```bash
git diff --check
bash scripts/doctor.sh
git status --short
```

Expected: no whitespace errors, doctor passes, and only intended files are modified or added.

- [ ] **Step 3: Commit and push**

```bash
git add docs/superpowers/specs/2026-08-31-oazon-mm-daily-log-windows-token-design.md \
        docs/superpowers/plans/2026-08-31-oazon-mm-daily-log-windows-token.md \
        skills/content/reports/oazon-mm-daily-log/SKILL.md \
        skills/content/reports/oazon-mm-daily-log/scripts/fetch_mm_day.py \
        skills/content/reports/oazon-mm-daily-log/tests
git commit -m "fix(oazon-mm-daily-log): support Windows and trim instructions"
git push origin main
```

Expected: push succeeds and local `main` is synchronized with `origin/main`.
