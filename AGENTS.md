# Contributing as a coding agent

## Code and docs

- Write prose in Australian English, sentence case, no emoji.
- Document every public declaration. Write no other comments: rename or restructure instead.
- Never log, print or put in an error any key, token, or request or response body.
- Never commit secrets.
- `Tests/EntitlerTests/Fixtures/snapshot-vectors.json` is shared by every Entitler SDK. Copy it
  unchanged from `entitlerhq/entitler-typescript`; never edit it here.

## Pull requests

- Run the checks in `.github/workflows/ci.yml` locally before pushing. `All checks passed` is
  the required check: keep its name and list every other job in its `needs`.
- One change per pull request, based on `main`. Open it ready for review, not as a draft.
- Keep history linear: rebase, never merge. Never amend; put each fix in a new commit.
- Ask for a review with `@coderabbitai review`, and again after each push of fixes. Fix every
  valid finding in one commit, answer the rest in one line, and resolve the threads you settle.
- Once the latest review approves, queue the pull request with `gh pr merge <number> --auto`.
