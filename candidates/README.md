# Candidate upstreams

A candidate is an upstream iTerm2 version being ported while the shipping build stays on its own pin. It is
tracked here, on `main`, so its progress is reviewed and tested like everything else. Nothing here ships:
the shipping pins are `components/`, `patches/` and `UPSTREAM_VERSION` at the top of the checkout, and they
move to a candidate only when that candidate is accepted (see `.superpowers/specs/2026-10-31-iterm2-design.md`,
Milestone C).

`candidates/<version>/` holds:

- `UPSTREAM_VERSION`, `components/iterm2/version`, `components/iterm2-resources/version`: pins of the
  same form as the shipping ones, naming `<version>`.
- `patches/`: the patches this candidate ships, under the same rules as `patches/` (a header saying
  what and why, applied with no fuzz). Shipping patches that apply unchanged are copied here; a patch is
  never shared by path, so the two lines can diverge. A research-only patch never lives here.
- `census-settings`: one block per target for `build/census.sh` (see `BUILD.md` "Census").

Prepare a candidate's inputs with its pins and its patches together:

    sh build/candidate.sh 3.2.9 "$TMPDIR/cand-3.2.9-inputs"

then measure what it still needs from Mavericks:

    sh build/census.sh "$TMPDIR/cand-3.2.9-inputs" "$PWD/candidates/3.2.9/census-settings" "$TMPDIR/cand-3.2.9-census"

`tests/candidate-test.sh` checks every candidate's shape.

## 3.2.9

Chosen by the maintainer on 2026-11-22; the research is in `recommendation.md` under
`.superpowers/research/2026-11-22-upstream-boundary/` (not tracked). Shipping patches 0001, 0007, 0010
and 0011 apply unchanged; 0002, 0005 and 0009 are upstream's own code by 3.2.9; 0003, 0004, 0006, 0008 and
0012 must be ported again. shipyard's exporter (v1.0.810 and later) lists the Metal shaders as not
compiled; the build leaves them out, since 10.9 has no Metal. The census compiles 515 files.
