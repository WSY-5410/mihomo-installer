#!/bin/bash

# 版本：v2.1
# 功能：全自动安装Mihomo + 订阅链接配置 + 系统服务部署
# 支持：x86_64/arm64/armv7 + CentOS/Debian/Ubuntu/Raspberry Pi OS

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：请使用root用户或通过sudo运行此脚本！${RESET}"
    exit 1
fi

# 函数：检测命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 函数：安装依赖
install_dependencies() {
    echo -e "${BLUE}[1/6] 正在安装系统依赖...${RESET}"
    if command_exists apt-get; then
        apt-get update
        apt-get install -y curl gzip jq || {
            echo -e "${YELLOW}依赖安装失败，尝试更换阿里云镜像源...${RESET}"
            cp /etc/apt/sources.list /etc/apt/sources.list.bak
            sed -i 's|http://.*archive.ubuntu.com|http://mirrors.aliyun.com|g' /etc/apt/sources.list
            sed -i 's|http://.*security.ubuntu.com|http://mirrors.aliyun.com|g' /etc/apt/sources.list
            apt-get update && apt-get install -y curl gzip jq
        }
    elif command_exists yum; then
        yum install -y curl gzip jq || {
            echo -e "${YELLOW}依赖安装失败，尝试更换阿里云镜像源...${RESET}"
            if [ -f /etc/yum.repos.d/CentOS-Base.repo ]; then
                mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak
            fi
            curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
            yum clean all && yum makecache
            yum install -y curl gzip jq
        }
    else
        echo -e "${RED}错误：不支持的包管理器！${RESET}"
        exit 1
    fi
}

# 函数：检测架构
detect_arch() {
    case "$(uname -m)" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "armv7" ;;
        *)       echo -e "${RED}错误：不支持的CPU架构！${RESET}" ; exit 1 ;;
    esac
}

# 函数：获取用户订阅链接
get_subscription_url() {
    echo -e "${YELLOW}请输入您的订阅链接（支持Clash格式）：${RESET}"
    read -r SUB_URL
    
    case "$SUB_URL" in
        http://*|https://*)
            return 0
            ;;
        *)
            echo -e "${RED}错误：订阅链接格式不正确！${RESET}"
            exit 1
            ;;
    esac
}

# 函数：下载订阅配置
download_config() {
    echo -e "${BLUE}[3/6] 正在下载订阅配置...${RESET}"
    local config_file="$1"
    
    if ! curl -L "$SUB_URL" -o "$config_file"; then
        echo -e "${RED}错误：订阅链接下载失败！${RESET}"
        exit 1
    fi
    
    # 检查配置文件是否有效
    if ! grep -q "proxies:" "$config_file"; then
        echo -e "${RED}错误：订阅内容不包含有效代理配置！${RESET}"
        exit 1
    fi
    
    echo -e "${GREEN}订阅配置下载成功！${RESET}"
}

# 主安装流程
echo -e "${GREEN}
=======================================
Mihomo 一键安装脚本 (v2.1)
=======================================
${RESET}"

# 步骤1：安装依赖
install_dependencies

# 步骤2：检测架构
ARCH=$(detect_arch)
echo -e "${BLUE}[2/6] 检测到系统架构：${ARCH}${RESET}"

# 步骤3：获取订阅链接
get_subscription_url

# 步骤4：下载Mihomo
MIHOMO_VERSION="v1.19.12"
INSTALL_DIR="/opt/mihomo"
CONFIG_FILE="${INSTALL_DIR}/config.yaml"
SERVICE_FILE="/etc/systemd/system/mihomo.service"

echo -e "${BLUE}[4/6] 正在下载Mihomo...${RESET}"
case "$ARCH" in
    amd64)  BINARY_URL="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VERSION}/mihomo-linux-amd64-compatible-${MIHOMO_VERSION}.gz" ;;
    arm64)  BINARY_URL="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VERSION}/mihomo-linux-arm64-${MIHOMO_VERSION}.gz" ;;
    armv7)  BINARY_URL="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VERSION}/mihomo-linux-armv7-${MIHOMO_VERSION}.gz" ;;
esac

mkdir -p "$INSTALL_DIR"
curl -L "$BINARY_URL" | gzip -d > "${INSTALL_DIR}/mihomo" || {
    echo -e "${RED}错误：下载失败！${RESET}"
    exit 1
}
chmod +x "${INSTALL_DIR}/mihomo"

# 步骤5：下载订阅配置
download_config "$CONFIG_FILE"

# 步骤6：配置系统服务
echo -e "${BLUE}[5/6] 正在配置系统服务...${RESET}"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Mihomo Proxy Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/mihomo -d ${INSTALL_DIR}
Restart=always
RestartSec=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mihomo --now

# 步骤7：配置环境变量
echo -e "${BLUE}[6/6] 正在配置环境变量...${RESET}"
echo "export http_proxy=http://127.0.0.1:7890" >> /etc/profile
echo "export https_proxy=http://127.0.0.1:7890" >> /etc/profile
source /etc/profile

# 完成提示
echo -e "${GREEN}
=======================================
安装完成！服务状态：
$(systemctl status mihomo --no-pager | head -n 5)

管理命令：
启动服务：systemctl start mihomo
停止服务：systemctl stop mihomo
查看日志：journalctl -u mihomo -f

代理地址：127.0.0.1:7890
测试代理: curl -I https://www.google.com
=======================================
${RESET}"
