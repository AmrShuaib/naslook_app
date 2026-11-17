#!/usr/bin/env bash
# Grant (or revoke) admin rights to an account. Run as root on the VPS:
#   bash /opt/naslife/ops/grant-admin.sh SA1234567          # grant
#   bash /opt/naslife/ops/grant-admin.sh SA1234567 revoke   # revoke
set -euo pipefail
id="${1:?user id (SAxxxxxxx)}"; mode="${2:-grant}"
[[ "$id" =~ ^[A-Z]{2}[0-9]{7}$ ]] || { echo "bad id"; exit 1; }
flag=$([ "$mode" = revoke ] && echo false || echo true)
sudo -u postgres psql -d naslife -v ON_ERROR_STOP=1 -tAc "UPDATE users SET is_admin=$flag WHERE id='$id' RETURNING nickname||' is_admin='||is_admin"
sudo -u postgres psql -d naslife -tAc "INSERT INTO audit_log(actor,action,target_type,target_id,after) VALUES('ops-shell','admin.$mode','user','$id','{\"is_admin\":$flag}')"
