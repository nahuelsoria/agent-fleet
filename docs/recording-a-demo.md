# Recording a demo GIF

A short terminal recording of an agent running (and firing a real alert) is the
single highest-impact thing you can add to the README. Here's how, in ~2 minutes.

## 1. Install the tools (once)

```bash
# asciinema records the terminal session; agg turns it into a GIF
sudo apt install asciinema        # or: pipx install asciinema
# agg (asciinema gif generator):
cargo install --git https://github.com/asciinema/agg
# no Rust? grab a prebuilt binary from https://github.com/asciinema/agg/releases
```

## 2. Prepare a clean, real scenario

The best demo shows a **real alert landing in Telegram**. Set up `.env` with your
bot token first (`cp .env.example .env`, fill it in), then stage a failure the
agent will catch — e.g. an obviously stale/broken backup so `backup-verify` fires:

```bash
mkdir -p /tmp/demo-backups
: > /tmp/demo-backups/db_broken.sql.gz          # 0-byte "backup" -> triggers the size + gzip checks
```

## 3. Record

```bash
asciinema rec demo.cast --overwrite -c "bash --norc"
```

Then, inside the recording, type slowly and deliberately:

```bash
# a healthy check — stays silent
./agents/vps-health/run.sh

# a broken backup — fires a red alert to Telegram
BACKUP_DIR=/tmp/demo-backups BACKUP_GLOB='*.sql.gz' ./agents/backup-verify/run.sh

# scaffold a brand-new agent in one command
./bin/new-agent my-agent
```

Press `Ctrl-D` to stop recording.

> Tip: keep it under ~25 seconds. Fewer commands, shown clearly, beats a long reel.

## 4. Convert to GIF and drop it in

```bash
agg demo.cast docs/demo.gif --theme monokai --font-size 20
```

Then reference it near the top of the README (the placeholder is already there —
just uncomment it):

```markdown
![agent-fleet demo](docs/demo.gif)
```

Commit `docs/demo.gif` and the updated README, push, done. Delete `demo.cast`.

## Privacy check before pushing

- The recording must not show your real `TELEGRAM_TOKEN` / `TELEGRAM_CHAT_ID`.
  Don't `cat .env` on camera. The Telegram *message* is fine to show; the
  credentials are not.
- Clean up: `rm -rf /tmp/demo-backups demo.cast`
