# استعادة نسخة احتياطية

النسخ في `/opt/naslife/backups` على الخادم (تُحفظ 14 يوماً):

- `naslife-YYYY-MM-DD-HHMM.sql.gz` قاعدة البيانات
- `uploads-YYYY-MM-DD-HHMM.tar.gz` الملفات المرفوعة
- `server-YYYY-MM-DD-HHMM.tar.gz` كود الخادم و `.env` وملف systemd

## استعادة قاعدة البيانات
```bash
systemctl stop naslife
sudo -u postgres psql -c "DROP DATABASE naslife" -c "CREATE DATABASE naslife OWNER naslife"
gunzip -c /opt/naslife/backups/naslife-XXXX.sql.gz | sudo -u postgres psql naslife
systemctl start naslife
```

## استعادة الملفات المرفوعة
```bash
tar -xzf /opt/naslife/backups/uploads-XXXX.tar.gz -C /opt/naslife
```

## سحب نسخة إلى جهازك (خارج الخادم)
من PowerShell على جهازك: `.\server\ops\pull-backups.ps1`
