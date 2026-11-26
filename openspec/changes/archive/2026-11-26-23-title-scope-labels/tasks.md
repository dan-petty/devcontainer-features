# Tasks

## 1. Declare the scope labels

Kind: data. Changes: `.github/labels.yml`.

- [x] 1.1 Add a `scope/*` label for each scope of the proposal
  - Verification: `$ pre-commit run check-yaml --files .github/labels.yml`
- [x] 1.2 Check that the script of the title check reads each scope
  - Verification: run `scripts/pr-title-scopes.sh .github/labels.yml` of dan-petty/infra with yq: the output holds each declared scope and `main`

## 2. Documents

Kind: other. Changes: `CONTRIBUTING.md`.

- [x] 2.1 Say that a new Feature adds its `scope/*` label
  - Verification: `$ pre-commit run --files CONTRIBUTING.md`

## Workflow follow-up

- Pending a person: after the merge, a Renovate pull request with `chore(deps)` and a summary of at most 60 characters passes the check `Semantic PR title`.
