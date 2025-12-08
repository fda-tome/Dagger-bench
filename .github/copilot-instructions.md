<!-- Copilot / AI assistant guidance for Dagger-bench -->
# Quick instructions for AI coding agents

This repository contains benchmarks and demonstration scripts for Dagger.jl (Julia). The goal of an AI coding agent here is to make small, safe, and repository-consistent edits: add or fix benchmarks, improve demos, update docs, or help reproduce results.

Key principles
- Language & tools: this is a Julia-focused repo. Respect `Project.toml` and `Manifest.toml` files in each folder (e.g. `seam/`, `barnes/`, `seam/Dagger.jl/`). Use `julia --project=.` and the Pkg API for installs and tests.
- Keep edits local and minimal: change single files unless a feature requires multiple coordinated edits. When changing API in `seam/Dagger.jl/src` prefer adding tests under `seam/Dagger.jl/test/`.

Where to look first
- High-level overview: `README.md` at repo root describes the purpose and layout.
- Dagger package / core: `seam/Dagger.jl/README.md` and `seam/Dagger.jl/src/` show package internals and examples.
- Demos: `seam/par_seam.jl` (image seam-carving demo) and `barnes/barnes-hut.jl` (Barnes-Hut demo) are runnable examples that show common patterns.
- Tests and CI: `seam/Dagger.jl/test/` contains unit tests for package behavior.

Project-specific patterns and conventions (be explicit)
- Multiple Julia projects: many folders are independent Julia projects (they contain `Project.toml` and `Manifest.toml`). Use `julia --project=PATH` or `cd PATH; julia --project=.` when running scripts or tests.
- Dagger usage patterns seen in demos:
  - Chunked data / subdomains: code uses container fields like `.chunks` and `.subdomains` (see `par_seam.jl` usage of `cost.chunks`, `cost.subdomains`, and `Dagger.indexes`).
  - Dependency spawning: tasks use `Dagger.@spawn` and the data dependency helpers `In`, `Out`, `InOut`. Look for `Dagger.spawn_datadeps()` in `seam/par_seam.jl` as an example control pattern.
  - Processor discovery: call `Dagger.compatible_processors()` to size parallel work (see `barnes/barnes-hut.jl`).
  - Fetching results: spawned tasks are `fetch`ed or `collect`ed at the end to materialize results.

Common commands (explicit examples)
- Install dependencies for the whole repo (run from repo root):
  julia --project=. -e 'using Pkg; Pkg.instantiate()'
- Run the seam demo (from repo root):
  cd seam
  julia --project=. par_seam.jl
- Run the Barnes-Hut demo (from repo root):
  cd barnes
  julia --project=. barnes-hut.jl
- Run package tests for the bundled Dagger.jl copy:
  cd seam/Dagger.jl
  julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'

Editing rules for AI
- Small, focused changes only: prefer adding tiny helper functions, bug fixes, clarifying comments, or small tests. Large refactors should be suggested and discussed.
- Preserve Julia package boundaries: if you change `seam/Dagger.jl/src/*`, update `seam/Dagger.jl/test/*` with a minimal test that covers the behavior.
- When modifying demos, keep them runnable with the same `Project.toml` (avoid adding heavy new deps without updating the manifest).
- Use the repository's coding style: idiomatic Julia, descriptive names, and simple comments to explain non-obvious math/parallel logic.

What to include in pull requests / changes
- Short description of the change, why it's safe, and what tests/demos were run locally (include command lines used).
- If you change APIs, include a migration note in the relevant README.

Quick examples to reference
- `seam/par_seam.jl`: shows `Dagger.spawn_datadeps()` blocks, `Dagger.@spawn calc_tri_down(...)`, and usage of `In`, `Out`, `InOut`, and `collect`.
- `barnes/barnes-hut.jl`: shows `Dagger.@spawn` for subtree work, `Dagger.compatible_processors()` to adapt parallelism, and `fetch.(subtrees)` to gather results.

When you are unsure
- If a requested change touches multiple packages or alters tests/CI, stop and request clarification.
- For high-risk changes (API changes, adding new heavy dependencies, altering benchmark results), provide a short plan and ask for a human reviewer.

Contact / follow-up
- After making changes, always run the local demo or test command you modified and report the exact command used and outcome.

If anything above is unclear, ask the maintainer which demo or package to exercise; mention the file(s) you intend to edit and the minimal test you will add.
