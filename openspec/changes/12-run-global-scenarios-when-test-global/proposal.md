# Proposal

## Why

The pull request workflow `.github/workflows/test-pr.yaml` runs no test when a pull request changes only `test/_global`: the ids step keeps only ids that have `src/<id>/devcontainer-feature.json`, so the global scenario of #7 gets an empty Feature list and its breakage shows only on the push to `main` or in the weekly `test-all.yaml` run, which is why the proof of PR #11 needed a run started by hand. #12 adds a `test-global` job to `.github/workflows/test-pr.yaml` that runs `npm run test:global` when a file under `test/_global` changes, and skips it for a Feature-only pull request.

## What Changes

- Add a `global` filter for the global scenarios folder to the pinned `dorny/paths-filter` step of `.github/workflows/test-pr.yaml`, and publish it as the `global` output of the `detect-changes` job.
- Add a `test-global` job to `.github/workflows/test-pr.yaml` that runs when `needs.detect-changes.outputs.global == 'true'`, with `timeout-minutes: 30` on the job and `timeout-minutes: 25` on its run step.
- Run `npm run test:global` in the new job with the full-SHA `actions/checkout` pin, `persist-credentials: false` and `npm ci`, the same steps as the weekly global job.
- Keep the `features` filter over `test/**`, the ids step and the gates of the `test`, `test-scenarios` and `podman-host` jobs, so a Feature-only pull request runs them and skips the new job.
- Rewrite the comment above the ids step so it says that a change to the global scenarios gives no Feature id and that the `test-global` job runs the global scenarios.
- Record the live proof of the Expected section as a `Pending a person:` bullet: a pull request that changes only the global scenario file shows the `test-global` job as passed and the three Feature jobs as skipped.
- Complete the `test-pr.yaml` row of the Workflows table and the paragraph above it in `CONTRIBUTING.md`, so both name the global job of the pull request workflow.
- Give the plan no spec delta: the change edits one CI workflow and one document and adds no `devops` command, option or message, so no consumer-observable behavior changes.
- The change fits one pull request.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None.

## Impact

- Code: `.github/workflows/test-pr.yaml`
- Documents: `CONTRIBUTING.md`

## Feasibility

- Probe line, word for word: The path `.github/workflows/test-pr.yaml` is a file of the staging commit.
- Probe line, word for word: The path `test/_global/sid_usable/test.sh` is no file at the root of the staging commit. These files of the commit are candidates: `test/podman-in-podman/test.sh`, `test/podman-outside-podman/test.sh`. No commit in the history deleted or renamed it.
- `list_files` on `test/_global` returned `test/_global/scenarios.json` and `test/_global/sid_usable.sh`, so the global scenario that the new job runs exists at the staged commit.
- `read_file` `.github/workflows/test-pr.yaml` lines 20-45 confirmed the premise: the job `detect-changes` publishes one output at `.github/workflows/test-pr.yaml:26:features: ${{ steps.ids.outputs.features || '[]' }}`, and `.github/workflows/test-pr.yaml:53:if [ -n "$id" ] && [ -f "src/$id/devcontainer-feature.json" ]; then` keeps only Feature ids, so a change under the global scenarios gives `features=[]`.
- `read_file` `.github/workflows/test-pr.yaml` lines 20-45 showed the comment that the change rewrites, `.github/workflows/test-pr.yaml:43:# (a removed Feature, test/_global) gives no test.`, and the gate that the change extends, `.github/workflows/test-pr.yaml:32:- uses: dorny/paths-filter@ceb8a2b8f2d89434be7ff52d3de7ec3738c5cc9d # v4.0.3` with `.github/workflows/test-pr.yaml:39:- "test/**"` in the `features` filter, so a global scenario change already sets that filter true and the ids step then writes `[]`.
- `read_file` `.github/workflows/test-pr.yaml` lines 20-45 showed the workflow permission that the new job inherits, `.github/workflows/test-pr.yaml:24:pull-requests: read # dorny/paths-filter lists the changed files through the API`, and the checkout pin `.github/workflows/test-pr.yaml:28:- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7`; the context of the same file showed the trigger that stays, `.github/workflows/test-pr.yaml:3:pull_request:`, and `.github/workflows/test-pr.yaml:6:contents: read # read the files of the pull request`.
- The context of `.github/workflows/test-all.yaml` showed the job to copy: `.github/workflows/test-all.yaml:98:test-global:`, `.github/workflows/test-all.yaml:100:timeout-minutes: 30`, `.github/workflows/test-all.yaml:102:- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7`, `.github/workflows/test-all.yaml:110:if: hashFiles('test/_global/scenarios.json') != ''`, `.github/workflows/test-all.yaml:111:timeout-minutes: 25` and `.github/workflows/test-all.yaml:112:run: npm run test:global`.
- `read_file` `package.json` lines 8-16 showed the script that the new job calls, `package.json:12:"test:global": "devcontainer features test --global-scenarios-only",`, so the workflow holds no CLI argument of its own.
- `read_file` `CONTRIBUTING.md` lines 50-85 showed the row to complete, `CONTRIBUTING.md:77:tests each Feature with a changed file in`, and the paragraph above the table, `CONTRIBUTING.md:65:on linux/amd64 only.`, which names no global job.
- `read_file` `openspec/config.yaml` lines 28-36 and 60-68 showed the two rules that the change follows: `openspec/config.yaml:32:A change that alters no behavior a consumer observes (tests, CI workflows, documentation, a refactor that` and `openspec/config.yaml:64:A check only a person can run is a plain bullet starting "Pending a person:".`.
- `read_file` `README.md` lines 38-43 showed the sentence that stays true, `README.md:41:runs the scenario, so the run fails when a change in`, because the weekly run still runs the scenario every Monday.
- The example path of the Problem section, `test/_global/sid_usable/test.sh`, is no file of the commit, and the Expected section names the folder, so the plan gates on the folder and covers `test/_global/sid_usable.sh`; the issue stands as written.
- First check of the implementation: `uv run devops ci --check --only actionlint,zizmor` parses `.github/workflows/test-pr.yaml` and fails on a YAML fault, an unknown key, an unpinned action or an `unpinned-uses` finding; the failure classes are `lint` for a finding and `ci_infra` for a tool the image lacks.
- Programs of that check: `devops`, `actionlint` and `zizmor` are tools of the runner image and none is in the `NOT_IN_RUNNER` list; the command needs a checkout of the repository, no client and no network, and the pod has a read-only root, so it writes only under its temporary directory.
- The second group has no command check: this repository has no documentation check, so a person compares `CONTRIBUTING.md` with the jobs of `.github/workflows/test-pr.yaml` by hand.
- The live proof of the Expected section needs a client of GitHub and a network: a person opens a pull request that changes only `test/_global/sid_usable.sh` and reads the `test-global` check of its run; the failure classes are `provider` for an unreadable GitHub and `ci_infra` for a runner fault. That run is not checked by this plan run.
- Not checked: that the pattern `test/_global/**` of the pinned `dorny/paths-filter` sets its output for a file under that folder; the first pull request that changes a global scenario confirms it.
- The plan calls no function of the repository; `npm run test:global` runs only on the hosted runner of the new job, where it needs a network and a container engine, and it never runs in the plan check.

## Existing Tool Considered

`dorny/paths-filter` v4.0.3, already pinned at `.github/workflows/test-pr.yaml:32`, covers the per-job path gate, and the `test:global` script at `package.json:12` covers the run, so the change adds no dependency and writes no tool code.

## Dependencies

None.
