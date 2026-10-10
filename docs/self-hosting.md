# تحويل جهازك إلى سيرفر ووكيل ذكاء اصطناعي

أوامر مرتبة لتشغيل naslook وغيره على جهازك الشخصي. الافتراض أن الجهاز يعمل بـ Ubuntu
(سيرفر أو سطح مكتب). على ويندوز شغّل أولاً من PowerShell كمسؤول:

```powershell
wsl --install -d Ubuntu
```

ثم نفّذ كل ما يلي داخل طرفية Ubuntu.

## ملاحظات خاصة بـ WSL2 على ويندوز

- اعمل داخل مجلد Linux الخاص بك `~` وليس داخل `/mnt/c`، فالبناء هناك أبطأ بكثير.
- تخطَّ خطوات SSH وufw في المرحلة 1؛ جدار ويندوز يحمي الجهاز وWSL2 معزول خلف NAT.
- يجب تفعيل systemd قبل Docker وCoolify. تحقق:

```bash
grep -q 'systemd=true' /etc/wsl.conf && echo "systemd مفعّل" || echo "غير مفعّل"
```

إن كان غير مفعّل:

```bash
sudo tee /etc/wsl.conf >/dev/null <<'EOF'
[boot]
systemd=true
EOF
```

ثم من PowerShell: `wsl --shutdown` ثم افتح Ubuntu من جديد، وتحقق بـ `systemctl is-system-running`.

- WSL2 يتوقف عند إغلاق آخر نافذة طرفية. أبقِ نافذة مفتوحة أثناء التجربة، أو أنشئ مهمة تعمل عند الدخول من PowerShell كمسؤول:

```powershell
$a = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d Ubuntu -- sleep infinity"
$t = New-ScheduledTaskTrigger -AtLogOn
$s = New-ScheduledTaskSettingsSet -Hidden -ExecutionTimeLimit 0
Register-ScheduledTask -TaskName "KeepWSL" -Action $a -Trigger $t -Settings $s
powercfg /change standby-timeout-ac 0
```

- من ويندوز نفسه تصل إلى الخدمات عبر `http://localhost:PORT`، ومن الهاتف عبر عنوان Tailscale الذي يُثبَّت داخل Ubuntu.

## المرحلة 1: التحديث والأمان الأساسي

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git ufw unattended-upgrades
sudo systemctl enable --now unattended-upgrades

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw enable
```

الدخول بالمفاتيح بدل كلمة المرور. من جهازك الآخر (اللابتوب):

```bash
ssh-keygen -t ed25519
ssh-copy-id USER@SERVER_IP
ssh USER@SERVER_IP
```

بعد أن تتأكد أن الدخول بالمفتاح يعمل، على السيرفر:

```bash
sudo sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf
sudo systemctl restart ssh
```

## المرحلة 2: Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
docker run --rm hello-world
```

## المرحلة 3: Tailscale للوصول الخاص من أي مكان

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip -4
sudo ufw allow in on tailscale0
```

ثبّت تطبيق Tailscale على هاتفك بنفس الحساب، وبذلك يصبح السيرفر متاحاً لك فقط
عبر العنوان الذي طبعه الأمر `tailscale ip -4`.

## المرحلة 4: لوحة الاستضافة Coolify

```bash
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash
```

افتح من الهاتف أو اللابتوب (وأنت متصل بـ Tailscale):

```
http://TAILSCALE_IP:8000
```

أنشئ حساب المسؤول في أول زيارة.

## المرحلة 5: نشر naslook

### الطريقة أ: عبر Coolify (موصى بها)

1. Projects ← New Project ← New Resource ← Public Repository.
2. الرابط: `https://github.com/amrshuaib/naslook_app` والفرع المطلوب.
3. Build Pack: **Dockerfile** (الملف موجود في جذر المستودع).
4. Ports Exposes: `80`.
5. Domain: اتركه الافتراضي الآن، أو ضع دومينك بعد المرحلة 6.
6. Deploy.

### الطريقة ب: مباشرة بدون Coolify

```bash
git clone https://github.com/amrshuaib/naslook_app.git
cd naslook_app
docker build -t naslook-web .
docker run -d --name naslook-web --restart unless-stopped -p 8080:80 naslook-web
```

ثم افتح `http://TAILSCALE_IP:8080`.

### خطوة لازمة في Firebase

Firebase Console ← Authentication ← Settings ← Authorized domains ← أضف الدومين أو
العنوان الذي تفتح منه التطبيق، وإلا يفشل تسجيل الدخول.

## المرحلة 6 (اختياري): دومين عام عبر Cloudflare Tunnel

بدون فتح أي منفذ في الراوتر. من لوحة Cloudflare: Zero Trust ← Networks ← Tunnels ←
Create a tunnel ← Cloudflared. انسخ أمر التثبيت الذي يظهر، وهو بصيغة:

```bash
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb
sudo cloudflared service install TUNNEL_TOKEN
```

في صفحة التونل أضف Public Hostname:

- Subdomain: `app` مع دومينك.
- Service: `http://localhost:8080` للطريقة ب، أو `http://localhost:80` إذا كان الموقع
  خلف وكيل Coolify وضبطت الدومين فيه.

## المرحلة 7: جعل الجهاز وكيل ذكاء اصطناعي عبر Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash
cd ~/naslook_app
claude
```

سجّل الدخول عند أول تشغيل، ثم اخرج وشغّل وضع التحكم عن بعد:

```bash
claude remote-control
```

تظهر الجلسة في تطبيق Claude على هاتفك، وتعطي الأوامر من هناك فيبني الجهاز
التطبيق ويشغّل الاختبارات وينشر على Coolify.

## اختياري: نماذج محلية بدون إنترنت

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3.1:8b
docker run -d --name open-webui --restart unless-stopped \
  -p 3000:8080 --add-host=host.docker.internal:host-gateway \
  -v open-webui:/app/backend/data ghcr.io/open-webui/open-webui:main
```

ثم افتح `http://TAILSCALE_IP:3000`. يحتاج النموذج 8B إلى 16 GB ذاكرة أو كرت شاشة 8 GB.

## أوامر الصيانة اليومية

```bash
docker ps                               # ما يعمل الآن
docker logs -f naslook-web              # سجلات الموقع
docker system prune -f                  # تنظيف الصور القديمة
sudo tailscale status                   # حالة الشبكة الخاصة
sudo ufw status                         # حالة الجدار الناري
```
