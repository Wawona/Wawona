# Discord GitHub push webhook (org-wide)

Every repository under **`github.com/Wawona`** (new, transferred, forked into
the org, public or private) must have the **same** Discord GitHub webhook as
`Wawona/Wawona`. Install it in the same step as `gh repo create`. Do not leave
the repo without the hook.

## Required hook shape

| Field | Value |
|---|---|
| `name` | `web` |
| `active` | `true` |
| `events` | `["push"]` only |
| `config.content_type` | `json` (`application/json`) |
| `config.insecure_ssl` | `"0"` |
| `config.url` | Discord webhook **ending in `/github`** |

Copy the URL from `Wawona/Wawona`. Never paste it into git, rules, docs, or
commits. Scope `admin:repo_hook` (`gh auth refresh --scopes admin:repo_hook`).

```bash
URL=$(gh api repos/Wawona/Wawona/hooks --jq \
  '.[] | select((.config.url // "") | endswith("/github")) | .config.url' | head -1)
# skip if that URL is already on the new repo
jq -n --arg url "$URL" \
  '{name:"web",active:true,events:["push"],config:{url:$url,content_type:"json",insecure_ssl:"0"}}' \
  | gh api "repos/Wawona/NEW_REPO/hooks" --method POST --input -
```

Use JSON `--input`. Unquoted zsh `config[url]=` is a glob and fails.

## Hard rejects

- Extra events (`pull_request`, `workflow_run`, `*`, …)
- `content_type=form` or a payload URL **without** `/github`
- Committing or echoing the Discord URL
- Relying on an org-level hook instead of this per-repo hook
- Skipping forks or private repos

Do not `POST …/pings` unless asked (that notifies Discord). Cursor rule:
`.cursor/rules/wawona-discord-github-webhook.mdc`.
