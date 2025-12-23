#!/usr/bin/env bash
# flux_agent multi-panel manager
# Usage: bash flux_multi.sh

set -e

BASE_DIR="/etc/flux_agent"          # 官方 install.sh 默认目录
PANELS_ROOT="/etc/flux_agent_panels"
SYSTEMD_DIR="/etc/systemd/system"

mkdir -p "$PANELS_ROOT"

# 创建基础 flux_agent.service（如果不存在）
create_base_service() {
  if [ -f "$SYSTEMD_DIR/flux_agent.service" ]; then
    echo "[INFO] 检测到已存在 flux_agent.service，跳过创建基础服务。"
    return
  fi
  echo "[INFO] 未检测到 flux_agent.service，开始创建基础服务..."

  read -rp "请输入面板地址 (IP:端口): " PANEL_ADDR
  read -rp "请输入面板密钥: " PANEL_SECRET

  mkdir -p "$BASE_DIR"
  cd "$BASE_DIR"

  echo "[INFO] 下载并安装 flux_agent..."
  curl -L https://github.com/bqlpfy/flux-panel/releases/download/2.0.6-beta/install.sh -o ./install.sh
  chmod +x ./install.sh
  ./install.sh -a "$PANEL_ADDR" -s "$PANEL_SECRET"

  echo "[INFO] 基础 flux_agent.service 已创建并运行。"
}

# 确保基础目录和服务至少存在一次
ensure_base() {
  create_base_service
}

# 列出已配置面板
list_panels() {
  echo "当前已配置的面板实例:"
  if [ ! -d "$PANELS_ROOT" ]; then
    echo "  (无)"
    return
  fi
  local has=0
  for d in "$PANELS_ROOT"/*; do
    [ -d "$d" ] || continue
    has=1
    name="$(basename "$d")"
    echo "  - $name"
  done
  [ "$has" -eq 0 ] && echo "  (无)"
}

# 添加新面板
add_panel() {
  ensure_base

  read -rp "为新面板输入一个标识名(例如: p1 / hk1): " PANEL_NAME
  PANEL_DIR="$PANELS_ROOT/$PANEL_NAME"

  if [ -d "$PANEL_DIR" ]; then
    echo "[ERROR] 面板目录 $PANEL_DIR 已存在，换一个名字。"
    return
  fi

  echo "[INFO] 创建面板目录 $PANEL_DIR ..."
  mkdir -p "$PANEL_DIR"

  echo "[INFO] 从基础目录复制文件..."
  cp -a "$BASE_DIR/." "$PANEL_DIR/"

  # 删除旧的 device.id，让该实例获得新的 ID
  if [ -f "$PANEL_DIR/device.id" ]; then
    rm -f "$PANEL_DIR/device.id"
  fi

  # 让用户设置该面板的后端地址和密钥
  read -rp "请输入该面板的后端地址 (IP:端口): " PANEL_ADDR
  read -rp "请输入该面板的密钥: " PANEL_SECRET

  CONFIG_FILE="$PANEL_DIR/config.json"
  if command -v jq >/dev/null 2>&1 && [ -f "$CONFIG_FILE" ]; then
    echo "[INFO] 使用 jq 更新 config.json 中的地址和密钥。"
    tmp="$(mktemp)"
    jq \
      --arg addr "$PANEL_ADDR" \
      --arg secret "$PANEL_SECRET" \
      '.addr = $addr | .secret = $secret' \
      "$CONFIG_FILE" >"$tmp"
    if [ -s "$tmp" ]; then
      mv "$tmp" "$CONFIG_FILE"
    else
      rm -f "$tmp"
      echo "[WARN] jq 修改失败，请手动检查 $CONFIG_FILE。"
    fi
  else
    echo "[WARN] 未检测到 jq 或 config.json 不存在，写入一个简单模板配置，请按需手动调整: $CONFIG_FILE"
    cat >"$CONFIG_FILE" <<EOF_CFG
{
  "addr": "$PANEL_ADDR",
  "secret": "$PANEL_SECRET"
}
EOF_CFG
  fi

  SERVICE_NAME="flux_agent_${PANEL_NAME}.service"
  SERVICE_PATH="$SYSTEMD_DIR/$SERVICE_NAME"

  echo "[INFO] 创建 systemd 服务 $SERVICE_NAME ..."
  cat >"$SERVICE_PATH" <<EOF
[Unit]
Description=Flux Agent panel $PANEL_NAME
After=network.target

[Service]
WorkingDirectory=$PANEL_DIR
ExecStart=$PANEL_DIR/flux_agent -C config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
  systemctl status "$SERVICE_NAME" --no-pager -n 5 || true
}

# 删除面板
remove_panel() {
  list_panels
  read -rp "请输入要删除的面板标识名: " PANEL_NAME
  PANEL_DIR="$PANELS_ROOT/$PANEL_NAME"
  SERVICE_NAME="flux_agent_${PANEL_NAME}.service"

  if [ ! -d "$PANEL_DIR" ]; then
    echo "[ERROR] 面板目录 $PANEL_DIR 不存在。"
    return
  fi

  echo "[INFO] 停止并禁用服务 $SERVICE_NAME ..."
  systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true

  echo "[INFO] 删除目录 $PANEL_DIR ..."
  rm -rf "$PANEL_DIR"

  SERVICE_PATH="$SYSTEMD_DIR/$SERVICE_NAME"
  if [ -f "$SERVICE_PATH" ]; then
    rm -f "$SERVICE_PATH"
  fi

  systemctl daemon-reload
  echo "[INFO] 已删除面板 $PANEL_NAME。"
}

# 简单菜单
menu() {
  while true; do
    echo ""
    echo "===== flux_agent 多面板管理 ====="
    list_panels
    echo "---------------------------------"
    echo "1) 添加新面板"
    echo "2) 删除面板"
    echo "3) 退出"
    read -rp "请选择操作: " choice
    case "$choice" in
      1)
        add_panel
        ;;
      2)
        remove_panel
        ;;
      3)
        echo "退出。"
        exit 0
        ;;
      *)
        echo "无效选择。"
        ;;
    esac
  done
}

menu
