#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# Bite Deploy Pipeline
# Runs QA → commits → deploys worker + frontend → runs QA again → pushes to GitHub
#
# Usage:
#   ./deploy.sh "commit message here"
#   ./deploy.sh   # auto-generates commit message from timestamp
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

WORKER_URL="https://bite-worker.schuette-markus.workers.dev"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
MSG="${1:-Release $(date '+%Y-%m-%d %H:%M')}"

cd "$PROJECT_DIR"

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Bite Deploy Pipeline"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════════════════════"

# ─── 1. Pre-deploy QA ────────────────────────────────
echo ""
echo "▶ Step 1: Pre-deploy QA (current production)"
echo "────────────────────────────────────��──────────"
if ./qa.sh "$WORKER_URL"; then
  echo "  Pre-deploy QA passed"
else
  echo "  ⚠ Pre-deploy QA had failures (deploying anyway — this tests current prod)"
fi

# ─── 2. Git commit ───────────────────────────────────
echo ""
echo "▶ Step 2: Git commit"
echo "───────────────────────────────────────────────"
git add -A
if git diff --cached --quiet 2>/dev/null; then
  echo "  No changes to commit"
else
  git commit -m "$MSG"
  echo "  Committed: $MSG"
fi

# ─── 3. Deploy Worker ────────────────────────────────
echo ""
echo "▶ Step 3: Deploy Worker"
echo "───────────────────────────────────────────────"
cd "$PROJECT_DIR/worker"
npx wrangler deploy 2>&1
echo "  Worker deployed"

# ─── 4. Deploy Frontend ─────────────────────────────
echo ""
echo "▶ Step 4: Deploy Frontend (Cloudflare Pages)"
echo "───────────────────────────────────────────────"
cd "$PROJECT_DIR/web"
npx wrangler pages deploy . --project-name=bite 2>&1
echo "  Frontend deployed"

# ─── 5. Post-deploy QA ──────────────────────────────
echo ""
echo "▶ Step 5: Post-deploy QA"
echo "───────────────────────────────────────────────"
cd "$PROJECT_DIR"
sleep 3  # brief pause for edge propagation
if ./qa.sh "$WORKER_URL"; then
  echo "  Post-deploy QA passed"
else
  echo ""
  echo "  ⚠ Post-deploy QA had failures — check the output above"
  echo "  The deployment is live but may have issues."
fi

# ─── 6. Push to GitHub ──────────────────────────────
echo ""
echo "▶ Step 6: Push to GitHub"
echo "───────────────────────────────────────────────"
git push -u origin main 2>&1 || git push -u origin master 2>&1 || echo "  Push failed — you may need to set up the remote branch"
echo "  Pushed to GitHub"

# ─── Done ────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo "  ✓ Deploy complete"
echo "  Worker:   $WORKER_URL"
echo "  Frontend: https://bite.pages.dev"
echo "  GitHub:   https://github.com/schuettemarkus/Bite"
echo "═══════════════════════════════════════════════════"
echo ""
