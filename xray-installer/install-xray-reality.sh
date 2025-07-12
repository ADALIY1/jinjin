#!/bin/bash

# 📜 本脚本构思参考自：
#   原文：https://vpsdeck.com/posts/xray-source-install-vless-reality/
#   作者：Linux Server 频道（t.me/LinuxServer_Channel）
#   适用于 Debian 12 手动部署 Xray-core + VLESS + REALITY 节点


# 📜 本脚本构思参考自：
#   https://vpsdeck.com/posts/xray-source-install-vless-reality/
#   手动部署 Xray + VLESS + REALITY 教程优化版本
#   原始环境基于 Debian 12 + 搬瓦工 The DC9 Plan


# 📜 本脚本构思参考自：
#   https://github.com/XTLS/Xray-core
#   手动部署 Xray + VLESS + REALITY 教程优化版本
#   原始环境基于 Debian 12 + 搬瓦工 The DC9 Plan
#   由 ChatGPT 协助用户优化生成，适合追求极致简洁、安全、可控的科学上网方案


set -e

# 🏷️ 备注、端口、SNI（默认值支持）
# 🏷️ 第1个参数：备注名，如果不输入就默认为 Reality_Auto（用于节点链接显示）
REMARK="${1:-Reality_Auto}"
# 📦 第2个参数：端口号，默认是 51888（VLESS 监听端口）
PORT="${2:-51888}"
# 🎯 第3个参数：伪装域名 SNI（用于 Reality 的 TLS 目标域名），默认 www.microsoft.com
SNI="${3:-www.microsoft.com}"

# 🌐 获取公网 IP
# 🌐 自动获取 VPS 公网 IP，作为节点地址的一部分
PUBLIC_IP=$(curl -s ipv4.ip.sb)

# 🔍 检测平台架构
# 🔍 检测当前 VPS 的处理器架构（x86_64 或 arm64）
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
# 🎯 使用 Go 官方 API 拉取最新稳定版本号，如 go1.24.5
LATEST_VERSION=$(curl -s https://go.dev/dl/?mode=json | grep -oP '"version": ?"go[0-9.]+"' | head -n1 | cut -d'"' -f4)
GOFILE="${LATEST_VERSION}.linux-${GOARCH}.tar.gz"

echo "🟢 安装基础工具..."
apt update -y && apt upgrade -y
apt install sudo -y
sudo apt install -y curl git nano vim openssl

echo "⬇️ 下载并安装 Go: $LATEST_VERSION ($GOARCH)"
cd /opt/
# ⬇️ 下载对应架构的 Go 安装包
curl -LO "https://go.dev/dl/${GOFILE}"
# ⚠️ 删除已有的 Go 安装，防止冲突，然后解压新版本
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf "${GOFILE}"
# ✅ 将 Go 的 bin 目录加入系统 PATH，让终端能识别 go 命令
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

echo "✅ Go 版本: $(go version)"

echo "🛠️ 克隆并编译 Xray-core..."
# 🔽 克隆 Xray-core 官方源码仓库
git clone https://github.com/XTLS/Xray-core.git
cd Xray-core
go mod download
# 🛠 编译 Xray，关闭 CGO，生成更小更安全的静态可执行文件
CGO_ENABLED=0 go build -o xray -trimpath -ldflags "-s -w -buildid=" ./main
sudo mv xray /usr/local/bin
xray version

echo "🔐 生成 Reality 节点参数..."
# 🆔 自动生成唯一 UUID 作为 VLESS 用户标识
UUID=$(xray uuid)
# 🔐 使用 Xray 自带命令生成 Reality 所需的私钥/公钥
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key" | awk '{print $3}')
# 🔢 使用 openssl 生成 16 位的 ShortID（HEX），增强 Reality 抗探测性
SHORT_ID=$(openssl rand -hex 8)

echo "📄 写入 Xray 配置文件..."
sudo mkdir -p /etc/xray
# 📄 生成 Xray 的配置文件 config.json，并写入 Reality 节点的完整配置
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
# ⚙️ 创建 Xray 的 systemd 服务脚本，确保它可以后台运行并自启
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
# 🚀 启动 Xray 服务，并设置为系统开机自动启动
sudo systemctl enable --now xray

# 生成 VLESS URL
# 🌐 拼接最终 VLESS Reality 节点链接，包含 IP、UUID、公钥、SNI 等信息
VLESS_URL="vless://$UUID@$PUBLIC_IP:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&headerType=none#$REMARK"

# 输出结果
echo ""
echo "✅ Xray Reality 节点已部署完成！"
echo "📌 节点链接如下："
echo "$VLESS_URL"
# 💾 将节点链接写入 ~/xray_node_link.txt 文件，方便以后查阅
echo "$VLESS_URL" > ~/xray_node_link.txt
