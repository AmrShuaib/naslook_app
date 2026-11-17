# Copies the newest server backups to this PC (off-site copy). Requires the "naslife" SSH alias.
# Files are AES-256 encrypted (gpg); the passphrase is fetched once into $HOME\naslife-backups\PASSPHRASE.txt —
# keep that file, without it no backup can be restored. Restore steps: server/ops/restore.md
$dest = Join-Path $HOME "naslife-backups"
New-Item -ItemType Directory -Force $dest | Out-Null
$pass = Join-Path $dest "PASSPHRASE.txt"
if (-not (Test-Path $pass)) { scp -q "naslife:/root/.naslife-backup-pass" $pass; Write-Host "Backup passphrase saved to $pass — back it up separately" }
scp -q "naslife:/opt/naslife/backups/*" $dest
Get-ChildItem $dest | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item -Force
Write-Host "Backups copied to $dest"
Get-ChildItem $dest | Sort-Object LastWriteTime -Descending | Select-Object -First 3 Name, Length, LastWriteTime
