# Vorssaint Utils — Agent Notes

## Design system (DS)

- Tokens: `DS.Font`, `DS.Space`, `DS.Radius` in
  `Sources/Vorssaint/UI/Theme.swift`. Smallest body text allowed is 11pt.
- Rule: new and touched views use `DS`; untouched views keep their
  literals until their panel is adopted.
- Migration log: `DS.md` at repo root. After every DS slice, append one
  timestamped entry under `## Log` and move the migrated files from
  Remaining to Done. Read it before starting DS work.

## Commits

- Commit and push every change. Never leave work uncommitted.
- No author trailers in commit messages.
