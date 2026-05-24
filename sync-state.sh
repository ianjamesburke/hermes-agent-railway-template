#!/bin/bash
# Watches critical hermes state files and syncs to greg-teh-robot/hermes-state on change.
# Runs as a background process alongside the gateway. Zero LLM tokens.

REPO_DIR="/data/hermes-state"
HERMES_DIR="/data/.hermes"
WATCH_PATHS="$HERMES_DIR/SOUL.md $HERMES_DIR/config.yaml $HERMES_DIR/auth.json"
WATCH_DIRS="$HERMES_DIR/skills $HERMES_DIR/memories $HERMES_DIR/cron"

clone_if_needed() {
    if [ ! -d "$REPO_DIR/.git" ]; then
        git clone --depth 1 "https://x-access-token:${GITHUB_TOKEN}@github.com/greg-teh-robot/hermes-state.git" "$REPO_DIR" 2>/dev/null || {
            echo "[sync-state] Failed to clone hermes-state repo"
            return 1
        }
    fi
    cd "$REPO_DIR"
    git config user.name "greg-teh-robot"
    git config user.email "greg-teh-robot@users.noreply.github.com"
}

sync_files() {
    cd "$REPO_DIR" || return 1

    cp "$HERMES_DIR/SOUL.md" "$REPO_DIR/" 2>/dev/null
    cp "$HERMES_DIR/config.yaml" "$REPO_DIR/" 2>/dev/null
    cp "$HERMES_DIR/auth.json" "$REPO_DIR/" 2>/dev/null

    rm -rf "$REPO_DIR/skills" "$REPO_DIR/memories" "$REPO_DIR/cron"
    cp -r "$HERMES_DIR/skills" "$REPO_DIR/skills" 2>/dev/null
    cp -r "$HERMES_DIR/memories" "$REPO_DIR/memories" 2>/dev/null
    cp -r "$HERMES_DIR/cron" "$REPO_DIR/cron" 2>/dev/null

    git add -A
    if ! git diff --cached --quiet; then
        git commit -m "state sync $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        git push origin main 2>/dev/null || git push origin master 2>/dev/null || echo "[sync-state] Push failed"
        echo "[sync-state] Synced at $(date -u +%H:%M:%S)"
    fi
}

if [ -z "$GITHUB_TOKEN" ]; then
    echo "[sync-state] No GITHUB_TOKEN, skipping state sync watcher"
    exit 0
fi

clone_if_needed || exit 0

# Initial sync on startup
sync_files

# Watch for changes, debounce 30s
while true; do
    inotifywait -r -q -e modify,create,delete,move \
        $WATCH_PATHS $WATCH_DIRS \
        --timeout 3600 2>/dev/null

    sleep 30
    sync_files
done
