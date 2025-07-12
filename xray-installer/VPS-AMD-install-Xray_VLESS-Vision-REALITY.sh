#!/bin/bash

set -e

# 🏷️ 设置备注名（默认：Reality_Auto）
REMARK="${1:-Reality_Auto}"

# 📦 设置端口（默认：51888）
PORT="${2:-51888}"

# 🎯 设置伪装域名（默认：www.microsoft.com）
SNI="${3:-www.microsoft.com}"

# 🌐 获取公网 IP
PUBLIC_IP=$(curl -s ipv4.ip.sb)

echo "🟢 开始安装基础工具..."
apt update -y && apt upgrade -y
apt install sudo -y
sudo apt install -y curl git nano vim openssl

echo "🟢 安装 Golang 1.24.5..."
cd /opt/
curl -LO https://go.dev/dl/go1.24.5.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.24.5.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

echo "✅ Go 版本: $(go version)"

echo "🛠 拉取 Xray-core 并编译..."
git clone https://github.com/XTLS/Xray-core.git
cd Xray-core
go mod download
CGO_ENABLED=0 go build -o xray -trimpath -ldflags "-s -w -buildid=" ./main
sudo mv xray /usr/local/bin
xray version

echo "🔐 生成节点参数..."
UUID=$(xray uuid)
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 8)

echo "📄 写入配置文件..."
sudo mkdir -p /etc/xray
cat <<EOF | sudo tee /etc/xray/config.json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "$SNI:443",
          "serverNames": ["$SNI"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

echo "⚙️ 写入 systemd 服务..."
cat <<EOF | sudo tee /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS
After=network.target nss-lookup.target

[Service]
User=root
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

echo "🚀 启动 Xray 服务..."
sudo systemctl daemon-reexec
sudo systemctl enable --now xray

echo "✅ Xray 已启动"

echo ""
echo "🔗 节点链接如下（自动嵌入公网 IP、备注、端口、SNI）："
VLESS_URL="vless://$UUID@$PUBLIC_IP:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&headerType=none#$REMARK"
echo "$VLESS_URL" > ~/xray_node_link.txt
echo "$VLESS_URL"
