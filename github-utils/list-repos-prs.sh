#!/bin/bash
set -euo pipefail  # Exit on any error, undefined variable or failed pipeline

REPOS_FILE="ansible-utils/playbooks/vars/repos.yaml"

# CSV header
echo "repo,pr_id,title,date_created,url,author,ci_status"

# Filter by only the GitHub repos
yq -o=json '.repos | to_entries | map(select(.value.source == "github"))' "$REPOS_FILE" \
  | jq -c '.[]' | while read -r line; do
    repo_key=$(echo "$line" | jq -r '.key')
    full_url=$(echo "$line" | jq -r '.value.url')

    # Remove "https://github.com/" and ".git" if present
    repo_path=$(echo "$full_url" | sed -E 's|https://github.com/||' | sed 's|.git$||')

    gh pr list \
      --repo "$repo_path" \
      --state open \
      --limit 100 \
      --json number,title,createdAt,url,author,statusCheckRollup \
      | jq -r --arg r "$repo_key" '
          .[] |
          .ci_status = (
              ([.statusCheckRollup[]? | select(.conclusion == "FAILURE" or .state == "FAILURE")])
              | length
              | if . > 0 then "failed" else "ok" end
          ) |
          [$r, .number, .title, .createdAt, .url, .author.login, .ci_status] | @csv
      '
done | sort -t',' -k4 -r
