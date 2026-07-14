#!/bin/bash
# Per-file GitHub backup script
# Usage: ./backup.sh <file_path> "<commit message>"
cd /home/user/flutter_app
git add "$1"
git commit -m "$2" --quiet
git push origin main --quiet 2>&1 | tail -1
echo "backed up: $1"
