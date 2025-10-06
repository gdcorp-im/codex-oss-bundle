#!/bin/bash
set -e

echo "Rebasing oss-bundle on top of upstream/main..."

# Save current branch
CURRENT_BRANCH=$(git branch --show-current)

# Ensure we're on oss-bundle
if [[ "$CURRENT_BRANCH" != "oss-bundle" ]]; then
    echo "Switching to oss-bundle branch..."
    git checkout oss-bundle
fi

# Fetch latest from upstream
echo "Fetching upstream changes..."
git fetch upstream

# Rebase on upstream/main
echo "Rebasing..."
git rebase upstream/main

echo ""
echo "Rebase complete!"
echo ""
echo "If there are conflicts:"
echo "  1. For README.md conflicts, run: git checkout --ours README.md"
echo "  2. Fix other conflicts manually"
echo "  3. git add <resolved-files>"
echo "  4. git rebase --continue"
echo ""
echo "Once done, force push:"
echo "  git push origin oss-bundle --force-with-lease"
