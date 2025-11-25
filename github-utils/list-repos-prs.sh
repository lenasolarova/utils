#!/bin/bash
set -euo pipefail  # Exit on any error, undefined variable or failed pipeline

REPOS_FILE="ansible-utils/playbooks/vars/repos.yaml"
KONFLUX_AUTHOR="app/red-hat-konflux"
TEMP_CSV=$(mktemp)
KONFLUX_CSV=$(mktemp)
OTHER_CSV=$(mktemp)

# Cleanup temp files on exit
trap 'rm -f "$TEMP_CSV" "$KONFLUX_CSV" "$OTHER_CSV"' EXIT

# Collect all PRs into temporary CSV
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
done > "$TEMP_CSV"

# Sort all PRs by date (newest first) and split into two files
{
  echo "repo,pr_id,title,date_created,url,author,ci_status"
  sort -t',' -k4 -r "$TEMP_CSV" | grep "\"$KONFLUX_AUTHOR\""
} > "$KONFLUX_CSV"

{
  echo "repo,pr_id,title,date_created,url,author,ci_status"
  sort -t',' -k4 -r "$TEMP_CSV" | grep -v "\"$KONFLUX_AUTHOR\""
} > "$OTHER_CSV"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Generate markdown files
TIMESTAMP=$(date '+%Y/%m/%d %H:%M:%S')

echo "# Open Pull Requests (app/red-hat-konflux) - $TIMESTAMP" > "$SCRIPT_DIR/open-prs-konflux.md"
csv2md "$KONFLUX_CSV" >> "$SCRIPT_DIR/open-prs-konflux.md"

echo "# Open Pull Requests (Others) - $TIMESTAMP" > "$SCRIPT_DIR/open-prs-others.md"
csv2md "$OTHER_CSV" >> "$SCRIPT_DIR/open-prs-others.md"

echo "Generated:"
echo "  - $SCRIPT_DIR/open-prs-konflux.md ($(wc -l < "$KONFLUX_CSV" | xargs) PRs)"
echo "  - $SCRIPT_DIR/open-prs-others.md ($(wc -l < "$OTHER_CSV" | xargs) PRs)"
