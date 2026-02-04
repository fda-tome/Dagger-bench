<!-- Copilot / AI assistant guidance for DaggerApps -->
# Quick instructions for AI coding agents

This repository is a collection of runnable Dagger.jl applications (Julia). Benchmarking scripts exist as an optional add-on.

## Key principles

- This is a Julia-focused repo; respect each app's `Project.toml`/`Manifest.toml`.
- Prefer small, safe, repo-consistent edits (single app at a time).
- If you add dependencies, update the corresponding app's `Project.toml` and (when available) regenerate its `Manifest.toml`.

## Where to look first

- High-level overview: `README.md` at repo root.
- Apps: `apps/` (each subfolder is a standalone Julia project).
- Benchmarks: `benchmarks/` (benchmark scripts; not the primary focus).

## Common commands

- Run an optional benchmark against an app environment (once `apps/<app>` is a Julia project):
  - `julia --project=apps/barnes-hut benchmarks/scripts/barnes-hut.jl`
- Run all app benchmarks:
  - `julia run_benchmarks.jl`

## Editing guidelines

- Keep changes scoped to one app/benchmark at a time.
- Prefer updating or adding `apps/<app>/README.md` when behavior/usage changes.
- For large refactors, propose a plan and request confirmation before making sweeping changes.
