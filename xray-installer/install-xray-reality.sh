#!/bin/bash

set -e

# 🏷️ 备注、端口、SNI（默认值支持）
REMARK="${1:-Reality_Auto}"
PORT="${2:-51888}"
SNI="${3:-www.microsoft.com}"

# 🌐 获取公网 IP
PUBLIC_IP=$(curl -s ipv4.ip.sb)

# 🔍 检测平台架构
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  GOARCH="amd64"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
  GOARCH="arm64"
else
  echo "❌ 不支持的架构：$ARCH"
  exit 1
fi

# 🎯 获取最新版 Go 版本号
LATEST_VERSION=$(curl -s https://go.dev/dl/?mode=json | grep -oP '"version": ?"go[0-9.]+"' | head -n1 | cut -d'"' -f4)
GOFILE="${LATEST_VERSION}.linux-${GOARCH}.tar.gz"

echo "🟢 安装基础工具..."
apt update -y && apt upgrade -y
apt install sudo -y
sudo apt install -y curl git nano vim openssl

echo "⬇️ 下载并安装 Go: $LATEST_VERSION ($GOARCH)"
cd /opt/
curl -LO "https://go.dev/dl/${GOFILE}"
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf "${GOFILE}"
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

echo "✅ Go 版本: $(go version)"

echo "🛠️ 克隆并编译 Xray-core..."
git clone https://github.com/XTLS/Xray-core.git
cd Xray-core
go mod download
CGO_ENABLED=0 go build -o xray -trimpath -ldflags "-s -w -buildid=" ./main
sudo mv xray /usr/local/bin
xray version

echo "🔐 生成 Reality 节点参数..."
UUID=$(xray uuid)
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 8)

echo "📄 写入 Xray 配置文件..."
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

# 生成 VLESS URL
VLESS_URL="vless://$UUID@$PUBLIC_IP:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&headerType=none#$REMARK"

# 输出结果
echo ""
echo "✅ Xray Reality 节点已部署完成！"
echo "📌 节点链接如下："
echo "$VLESS_URL"
echo "$VLESS_URL" > ~/xray_node_link.txt
