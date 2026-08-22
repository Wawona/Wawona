# GitHub Sponsors FUNDING.yml (org-wide)

Every repository under **`github.com/Wawona`** (new, transferred, forked into
the org, public or private) must ship the **same** Sponsor button as
`Wawona/Wawona`: `.github/FUNDING.yml` pointing at GitHub Sponsors and Ko-fi
for `aspauldingcode`.

Copy the file in the same step as `gh repo create`. Do not leave a repo
without it. Do not invent a different sponsor account per repo.

## Required file (`.github/FUNDING.yml`)

```yaml
# Funding links for Wawona
# These links will appear in the "Sponsor" button on the repository

# GitHub Sponsors username
github: aspauldingcode

# Ko-fi username
ko_fi: aspauldingcode
```

Copy from `Wawona/Wawona`. Commit on `development` when that branch exists,
otherwise the repo's default branch.

```bash
# after gh repo create Wawona/NEW_REPO
gh api repos/Wawona/Wawona/contents/.github/FUNDING.yml --jq .content \
  | tr -d '\n' | base64 -d > /tmp/Wawona-FUNDING.yml
# skip if the new repo already has an identical file
gh api --method PUT repos/Wawona/NEW_REPO/contents/.github/FUNDING.yml \
  --input <(jq -n --arg msg "Add Wawona GitHub Sponsors FUNDING.yml" \
    --arg content "$(base64 < /tmp/Wawona-FUNDING.yml | tr -d '\n')" \
    --arg branch development \
    '{message:$msg,content:$content,branch:$branch}')
```

If `development` does not exist yet, omit `branch` or pass the default branch.

Also install the Discord push webhook in the same create step
(`wawona-discord-github-webhook`).

## Hard rejects

- Empty or missing `.github/FUNDING.yml` on a `github.com/Wawona/*` repo
- A different `github:` or `ko_fi:` username
- Relying only on an org `.github` default instead of a per-repo file
- Skipping forks or private repos
- Putting other funding platforms in this file unless `Wawona/Wawona` adds them
  first

Cursor rule: `.cursor/rules/wawona-github-funding.mdc`.
