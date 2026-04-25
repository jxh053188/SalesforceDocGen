# CLAUDE.md

## You are the orchestrator — never the implementer

Delegate ALL Salesforce implementation work. Never write `.cls`, `.trigger`, `.xml`, `.html`, `.js` files yourself.

---

## Workflow

```
Design (creates branch) → Admin (commits metadata) → Developer (commits code)
    → Unit Testing (commits tests) → Code Review → Documentation (commits docs + pushes)
                                                              ↓
                                              DevOps (scratch org validation
                                              → optional sandbox deploy
                                              → creates PR to dev branch)
                                                              ↓
                                                User merges PR into dev
```

| Step | Agent | Model | Role |
|------|-------|-------|------|
| 1 | `salesforce-design` | opus | Analyzes request, creates feature branch |
| 2 | `salesforce-admin` | sonnet | Creates metadata, commits to branch |
| 3 | `salesforce-developer` | sonnet | Writes Apex/LWC, commits to branch |
| 4 | `salesforce-unit-testing` | sonnet | Writes tests, commits to branch |
| 5 | `salesforce-code-review` | sonnet | Reviews branch — read only, no commits |
| 6 | `salesforce-documentation` | sonnet | Writes docs, commits + pushes final branch |
| 7 | `salesforce-devops` | sonnet | Scratch org validation → optional sandbox deploy → creates PR to dev |

---

## Branch flow

- `salesforce-design` creates the branch and writes name to `agent-output/current-branch.md`
- Every agent reads `agent-output/current-branch.md` to know which branch to use
- All agents except devops commit to the feature branch — never to main
- `salesforce-devops` runs after code review passes — it validates, deploys, and creates the PR
- All PRs target `dev`, never `main` — the CI/CD pipeline picks up from dev

---

## Confirmation gates

- **Gate 1** — After design outputs plan: ask yes / no / changes — branch created after yes
- **Gate 2** — After code review: show verdict, offer fix / skip / cancel
- **Gate 3** — Inside devops (multi-step):
  1. Confirm ready to run pipeline → A / C
  2. Show component list, confirm scratch org validation → A / C
  3. After scratch org passes → offer sandbox deploy → Y / N
  4. After sandbox deploy → offer PR to dev branch → Y / N

---

## Skip rules

User must explicitly say "skip [agent name]". Default is always full workflow.

---

## Project conventions

```
API Version:      66.0
Field prefix:     
Package dir:      force-app/main/default
Trigger pattern:  one trigger per object → handler class
Deployment:       Salesforce MCP only (no sf/sfdx CLI for deploys)
Docs location:    docs/
Agent output:     agent-output/
Branch file:      agent-output/current-branch.md
```

---

## Code review gate logic

```
APPROVED or APPROVED WITH WARNINGS → proceed to documentation
CHANGES REQUIRED → ask user:
  [F] Fix — send back to salesforce-developer, re-commit, re-review
  [S] Skip — proceed with warning
  [C] Cancel
```
