#!/bin/bash

echo "================================="
echo " Cloudflare DDNS + Telegram Pro"
echo " systemd守护模式"
echo " 自动DNS校验"
echo " IP变化TG通知"
echo " 时间 UTC+8"
echo "================================="


apt update
apt install -y curl jq


read -p "Cloudflare API Token: " API_TOKEN

read -p "主域名(example.com): " DOMAIN

read -p "完整解析记录(test.example.com): " RECORD

read -p "Telegram Bot Token: " TG_TOKEN

read -p "Telegram Chat ID: " TG_CHAT_ID



cat > /root/cloudflare-ddns-tg.sh <<EOF
#!/bin/bash


API_TOKEN="$API_TOKEN"
DOMAIN="$DOMAIN"
RECORD="$RECORD"

TG_TOKEN="$TG_TOKEN"
TG_CHAT_ID="$TG_CHAT_ID"


IP_FILE="/root/.cloudflare_last_ip"



while true
do


CURRENT_IP=\$(curl -4 -s https://api.ipify.org)



if [ -z "\$CURRENT_IP" ]; then

    sleep 60
    continue

fi



OLD_IP=""

if [ -f "\$IP_FILE" ]; then

OLD_IP=\$(cat \$IP_FILE)

fi





# 获取 Zone ID

ZONE_ID=\$(curl -s \
"https://api.cloudflare.com/client/v4/zones?name=\$DOMAIN" \
-H "Authorization: Bearer \$API_TOKEN" \
-H "Content-Type: application/json" \
| jq -r '.result[0].id')



if [ "\$ZONE_ID" = "null" ] || [ -z "\$ZONE_ID" ]; then

echo "Zone ID 获取失败"

sleep 60

continue

fi





# 获取 DNS Record ID


RECORD_ID=\$(curl -s \
"https://api.cloudflare.com/client/v4/zones/\$ZONE_ID/dns_records?name=\$RECORD" \
-H "Authorization: Bearer \$API_TOKEN" \
-H "Content-Type: application/json" \
| jq -r '.result[0].id')



if [ "\$RECORD_ID" = "null" ] || [ -z "\$RECORD_ID" ]; then

echo "DNS记录获取失败"

sleep 60

continue

fi





# 获取Cloudflare当前解析IP


DNS_IP=\$(curl -s \
"https://api.cloudflare.com/client/v4/zones/\$ZONE_ID/dns_records/\$RECORD_ID" \
-H "Authorization: Bearer \$API_TOKEN" \
-H "Content-Type: application/json" \
| jq -r '.result.content')





echo "============================"

echo "\$(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S')"

echo "公网IP:"
echo "\$CURRENT_IP"

echo "Cloudflare DNS:"
echo "\$DNS_IP"

echo "============================"





# DNS校验

if [ "\$CURRENT_IP" != "\$DNS_IP" ] || [ "\$CURRENT_IP" != "\$OLD_IP" ]; then



echo "检测到IP变化，更新DNS..."



RESULT=\$(curl -s -X PUT \
"https://api.cloudflare.com/client/v4/zones/\$ZONE_ID/dns_records/\$RECORD_ID" \
-H "Authorization: Bearer \$API_TOKEN" \
-H "Content-Type: application/json" \
--data "{
\"type\":\"A\",
\"name\":\"\$RECORD\",
\"content\":\"\$CURRENT_IP\",
\"ttl\":60,
\"proxied\":false
}")





SUCCESS=\$(echo "\$RESULT" | jq -r '.success')





if [ "\$SUCCESS" = "true" ]; then



echo "\$CURRENT_IP" > \$IP_FILE





MESSAGE="🚨 Cloudflare DDNS更新成功

域名:
\$RECORD

旧IP:
\$OLD_IP

新IP:
\$CURRENT_IP

时间:
\$(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S') UTC+8"





curl -s -X POST \
"https://api.telegram.org/bot\${TG_TOKEN}/sendMessage" \
-d chat_id="\${TG_CHAT_ID}" \
-d text="\$MESSAGE" \
> /dev/null





echo "更新成功"



else



echo "Cloudflare更新失败"

echo "\$RESULT"



fi




else



echo "DNS正常，无需更新"



fi




sleep 60



done

EOF





chmod 700 /root/cloudflare-ddns-tg.sh






cat > /etc/systemd/system/cloudflare-ddns-tg.service <<EOF

[Unit]

Description=Cloudflare DDNS Telegram Pro

After=network-online.target

Wants=network-online.target



[Service]

Type=simple

ExecStart=/root/cloudflare-ddns-tg.sh

Restart=always

RestartSec=5



[Install]

WantedBy=multi-user.target

EOF





systemctl daemon-reload

systemctl enable cloudflare-ddns-tg

systemctl restart cloudflare-ddns-tg




echo ""

echo "================================="

echo "安装完成"

echo ""

echo "状态查看:"
echo "systemctl status cloudflare-ddns-tg"

echo ""

echo "实时日志:"
echo "journalctl -u cloudflare-ddns-tg -f"

echo "================================="
