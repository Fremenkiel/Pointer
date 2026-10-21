# M6 agent prompt

Give this prompt to the agent that builds M6. It works with [m6-plan.md](m6-plan.md). Paste the text under "Prompt" as the first message of a new session in the repository root.

## Prompt

You are the engineer of milestone M6 of Pointer: cards and navigation. You work alone in this repository. The product owner answers questions and runs the manual tests.

### Goal

Meet the three acceptance criteria of M6 in docs/plan.md. Keep every budget of docs/architecture.md section 12. Follow docs/m6-plan.md task by task.

### Before you write code

1. Read `AGENTS.md`, `docs/code-of-code.md`, `docs/product-spec.md` section 3.5, and `docs/m6-plan.md`.
2. Read `docs/architecture.md` sections 4.7, 5.2, 5.5, 5.6, 6, 8, 10, 11, and 12.
3. Read `docs/data-model.md` sections 7.2, 8, 9, and 10, and `docs/storage.md` sections 2, 5, and 10.
4. Read D-92 to D-113 in `docs/decisions.md`.
5. Make sure that D-107 to D-113 are decided. If one is still open, stop and ask the product owner. Do not start phase 1 before that.
6. If branch `m6` exists, continue on it. Else make it from `main` at commit 7284f4e.

### How to do a task

1. Take the first task of `docs/m6-plan.md` section 5 that has no status line.
2. Read the files that the task names. Make sure that the facts of section 1 still hold. If a fact changed, write the new fact in the plan before you change code.
3. Write the test first. For a bug fix, the test must fail before the fix (TEST-03).
4. Write the smallest code that passes the test (AGENT-02).
5. Run the checks of the package: `swift test` on the Mac for Tier A. Run `PointerDeviceTests` on the iPad for the other packages.
6. Run `make format`, `make lint`, `make layers`, and `make density`.
7. Commit with Conventional Commits (GIT-01). Name the requirement IDs and the rule IDs in the body (GIT-03).
8. Add a status line to the task in the plan. State what you did and each number that you measured.
9. Go on to the next task at once. Stop only for a reason in "When to stop".

### Performance and allocation rules

Section 4 of the plan holds the rules for M6. These are the most important:

1. The frame path makes no allocation. Reserve each buffer once and reuse it. Make no closure and no `Task` per frame.
2. Use one preview atlas texture with slots. Never make one `MTLTexture` per preview.
3. The main actor never waits for a load, a decode, a PNG encode, or a file write.
4. Card quads count against `instanceBudgetPerFrame` and `buildTimeBudget`, as glyph quads do.
5. A green clear draws the cards and the text again. Never one of them alone.
6. Each new hot path gets an `OSSignposter` interval and a device test with a target.
7. Compare a speed change with alternating runs of the old and the new build. Keep a slower change only with a written reason.
8. A test that loads a canvas waits for its background work to end before the test ends.

### Device rules

1. Run device tests on the connected iPad Pro 11-inch (M4) only, in Release. Never use a simulator, and never make one.
2. Before each device run, run `xcrun devicectl device info lockState --device 00008132-000018993E8B801C`. It must print `passcodeRequired: false`.
3. If the iPad is locked, stop and ask the product owner to unlock it.

### When to stop and ask

Stop, and ask the product owner, in these cases:

1. A document is unclear, or it conflicts with the code or with another document (AGENT-04). Write the question in `docs/decisions.md` as a new open entry, with options and a recommendation.
2. A target of the plan fails after one honest attempt at a fix. Give the measured numbers and the options.
3. A task needs a new framework, a new dependency, or a change to a rule of the coding standard (AGENT-03).
4. A manual test with the pencil or the fingers is due: tasks 4.7, 5.1, and 5.3, and the list of section 6.6.

Do not decide an open question yourself. Do not build a feature that the product specification does not list. Card resize and the move of a card to another parent are not in version 1.

### Report

At the end of each phase, give a short report:

1. The tasks that are done, with their commits.
2. Each measured number against its target, from the tables of section 6 of the plan.
3. Each failure with its output (AGENT-05).
4. The questions that wait for the product owner.

At the close of M6, run phase 6 of the plan in full, `make check` included. Report done only after each step passes, or after the product owner accepts the failure.
