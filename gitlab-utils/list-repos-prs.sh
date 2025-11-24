#!/bin/bash
set -euo pipefail

REPOS_FILE="ansible-utils/playbooks/vars/repos.yaml"

# CSV header
echo "repo,pr_id,title,date_created,url,author,ci_status"

yq -o=json '.repos | to_entries | map(select(.value.source == "gitlab"))' "$REPOS_FILE" \
  | jq -c '.[]' | while read -r line; do
    repo_key=$(echo "$line" | jq -r '.key')
    full_url=$(echo "$line" | jq -r '.value.url')

    if [[ "$full_url" =~ ^git@ ]]; then
      repo_path=$(echo "$full_url" | sed -E 's|git@gitlab[^:]*:||' | sed 's|.git$||')
    else
      repo_path=$(echo "$full_url" | sed -E 's|https://gitlab[^/]+/||' | sed 's|.git$||')
    fi

    glab mr list \
      --repo "$full_url" \
      -F json \
      --per-page 100 \
      | jq -c '.[] | select(.state == "opened")' | while read -r mr; do
        pr_id=$(echo "$mr" | jq -r '.iid')
        title=$(echo "$mr" | jq -r '.title')
        created_at=$(echo "$mr" | jq -r '.created_at')
        url=$(echo "$mr" | jq -r '.web_url')
        author=$(echo "$mr" | jq -r '.author.username')
        sha=$(echo "$mr" | jq -r '.sha')

        ci_status="unknown"
        statuses=$(glab ci list --repo "$full_url" --sha "$sha" -F json | jq -r '.[].status' || true)

        if [[ -n "$statuses" ]]; then
          if echo "$statuses" | grep -q "failed"; then
            ci_status="fail"
          else
            ci_status="ok"
          fi
        fi

        # Escape double quotes in title
        safe_title=$(echo "$title" | sed 's/"/""/g')

        printf '"%s","%s","%s","%s","%s","%s","%s"\n' \
          "$repo_key" "$pr_id" "$safe_title" "$created_at" "$url" "$author" "$ci_status"
      done
done | sort -t',' -k4 -r
