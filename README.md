# fjord-bench-github

The GitHub Actions baseline for [`rasterstate/fjord-actions`](https://rasterhub.com/rasterstate/fjord-actions).

The Fjord bundle benchmarks its cache/artifact/setup actions on a self-hosted
Forgejo runner. The reference point is the same workload built through the
GitHub Actions stack with the **upstream** actions (`actions/setup-node`,
`actions/setup-go`, `dtolnay/rust-toolchain`). That has to run on GitHub
Actions, so it lives here.

This runs on a **self-hosted** GitHub runner (same class of hardware as the
Fjord runner), so the number isolates the action ecosystem rather than the
cloud hardware: a same-hardware comparison of GitHub Actions vs Fjord Actions.

## What it does

[`.github/workflows/bench.yml`](.github/workflows/bench.yml) builds three pinned
workloads on a self-hosted Linux runner and records a **cold** and a **warm**
build time each:

| Workload | Repo | Pinned ref |
|----------|------|-----------|
| Rust | [`BurntSushi/ripgrep`](https://github.com/BurntSushi/ripgrep) | `14.1.1` |
| Node | [`axios/axios`](https://github.com/axios/axios) | `v1.7.9` |
| Go | [`cli/cli`](https://github.com/cli/cli) | `v2.62.0` |

"Warm" is a second build with the toolchain's on-disk caches left intact, i.e.
the state `actions/cache` restores at the start of a steady-state run. That is
the fair comparison to the Fjord warm (cache-restored) number.

Results land in [`results/github.csv`](results/github.csv) in the schema the
Fjord harness consumes:

```
workload,scenario,phase,seconds,runner_os,runner_arch,run_id,timestamp
```

`scenario` is always `github` so the Fjord `update-readme.sh` can drop the file
straight into its results dir.

## How the numbers travel

The Fjord bench workflow fetches this CSV over the raw URL each run:

```
https://raw.githubusercontent.com/rasterandstate/fjord-bench-github/main/results/github.csv
```

The workloads and refs are kept in lockstep with `bench-rust.sh` /
`bench-node.sh` / `bench-go.sh` in the Fjord repo. Change a workload in one
place, change it in both.
