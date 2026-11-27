# Tasks

## 1. Add the global path gate and the test-global job to test-pr.yaml

Kind: other. Reads: `.github/workflows/test-pr.yaml`, `.github/workflows/test-all.yaml`, `package.json`, `test/_global/scenarios.json`. Changes: `.github/workflows/test-pr.yaml`.

- [ ] 1.1 In `.github/workflows/test-pr.yaml`, add the filter `global: test/_global/**` to the `filters` block of the pinned `dorny/paths-filter` step, publish it as `global: ${{ steps.filter.outputs.global }}` in the outputs of `detect-changes`, and add a job `test-global` after the `podman-host` job, with `needs: [detect-changes]`, `if: needs.detect-changes.outputs.global == 'true'`, `runs-on: ubuntu-latest` and `timeout-minutes: 30`. Copy the three steps of the `test-global` job of `.github/workflows/test-all.yaml` into it: the `actions/checkout` step pinned to `3d3c42e5aac5ba805825da76410c181273ba90b1` with `persist-credentials: false`, `npm ci`, and the step `Test the global scenarios` that runs `npm run test:global` under `timeout-minutes: 25` with the guard `if: hashFiles('test/_global/scenarios.json') != ''`. Rewrite the comment above the ids step so it says that a change to the global scenarios gives no Feature id and that the `test-global` job runs the global scenarios.
  - Verification: `$ uv run devops ci --check --only actionlint,zizmor` passes

## 2. Name the global job in the Workflows table of CONTRIBUTING.md

Kind: other. Reads: `CONTRIBUTING.md`, `.github/workflows/test-pr.yaml`. Changes: `CONTRIBUTING.md`.

- [ ] 2.1 In `CONTRIBUTING.md`, change the `test-pr.yaml` row of the Workflows table so it says the workflow also runs the scenarios in the global folder, and add to the paragraph above the table that the `test-global` job of `.github/workflows/test-pr.yaml` runs `npm run test:global` on `ubuntu-latest` when a file under the global folder changes. Leave the other rows and the rest of the paragraph as they are, and run this check by hand: 1. Read the Workflows table and the paragraph above it in `CONTRIBUTING.md`. 2. Compare them with the jobs of `.github/workflows/test-pr.yaml`: the `test-pr.yaml` row names the global scenarios, and the paragraph names the `test-global` job, `npm run test:global` and the global folder.

## Workflow follow-up

- Pending a person: open a pull request that changes only `test/_global/sid_usable.sh` and read its run of `.github/workflows/test-pr.yaml`; the `test-global` job shows as passed, and the `test`, `test-scenarios` and `podman-host` jobs show as skipped.
