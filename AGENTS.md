# Rules for coding agents in this repository

## Copy and comments

- All prose (README, docs, doc comments, error messages, CLI output, changelog) is Australian
  English, sentence case, no emoji. Never write "get" in prose: name the thing. No vague "what"
  clauses. Identifiers follow Swift's conventions.
- Every public type, function, method, property and constant has a doc comment. No other
  comments: rename, extract or restructure instead. Tool directives are the only exception, each
  with a reason the tool accepts.
- Never log, print or put in an error or `description` any key, token or request or answer body.
- Never name the tools that wrote this repository in any file, commit or branch.

## Before pushing

Run every check in `ci.yml` locally:

```sh
swift format lint --strict --recursive Sources Tests Plugins Package.swift
swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip EntitlerIntegrationTests --enable-code-coverage
swift test --sanitize=thread --skip EntitlerIntegrationTests
ENTITLER_TEST_KEY=… swift test --filter EntitlerIntegrationTests
ENTITLER_DOCS=1 swift package generate-documentation --target Entitler --target EntitlerTesting --target EntitlerGenerator --warnings-as-errors
python3 scripts/extract-snippets.py && (cd examples && swift build --build-tests && swift test --skip-build)
```

The required check is `All checks passed`. Keep its name, and keep every other job in its `needs`.

## Authorship and pull requests

- Every commit is authored and committed by Romain Francez
  `<1330814+romainfrancez@users.noreply.github.com>`. Run
  `git config user.name "Romain Francez"` and
  `git config user.email "1330814+romainfrancez@users.noreply.github.com"` first.
- Commit messages carry no attribution trailers, no generated-by lines, no session links and no
  model names. Check `git log --format='%an <%ae>%n%b'` before every push.
- Agents never write to GitHub except by `git push`: no pull requests, comments, reviews or
  issues. The owner opens pull requests.
