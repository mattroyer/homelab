#!/usr/bin/env bash
#set -euo pipefail

# Simple backup script for named Docker volumes.
# It will create tar.gz archives under ./backups/<volume>-YYYYMMDD-HHMM.tar.gz
# Usage: ./scripts/backup-volumes.sh [volume1 volume2 ...]
# If no volumes provided, it will attempt to back up volumes listed in an env var BACKUP_VOLUMES

BACKUP_DIR="$(pwd)/backups"
mkdir -p "$BACKUP_DIR"

if [ "$#" -gt 0 ]; then
  VOLUMES=("$@")
elif [ -n "${BACKUP_VOLUMES-}" ]; then
  IFS=',' read -r -a VOLUMES <<< "$BACKUP_VOLUMES"
else
  echo "No volumes specified. Set BACKUP_VOLUMES env var or pass volumes as args."
  exit 1
fi

for vol in "${VOLUMES[@]}"; do
  stamp=$(date +%Y%m%d-%H%M)
  out="$BACKUP_DIR/${vol}-$stamp.tar.gz"
  echo "Backing up volume: $vol -> $out"
  docker run --rm -v "$vol":/data -v "$BACKUP_DIR":/backup alpine \
    sh -c "cd /data && tar czf /backup/$(basename "$out") ."
  if [ $? -eq 0 ]; then
    echo "  backed up $vol"
  else
    echo "  failed to back up $vol"
  fi
done

echo "Backups complete."
