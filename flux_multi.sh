#!/usr/bin/env bash
# flux_agent multi-panel manager (optimized version)
# 作者: echo00023 (优化版)

set -e

BASE_DIR="/etc/flux_agent"
PANELS_ROOT="/etc/flux_agent_panels"
SYSTEMD_DIR="/etc/systemd/system"

mkdir -p "$PANELS_ROOT"

show_existing_services() {
  echo "[INFO] 当前系统中的 flux_agent 相关服务："
  systemctl list-units 'flux_agent*.service' --no-pager --all || true
  echo ""
}

create_base_service() {
  if systemctl list-unit-files | grep -q '^flux_agent\.service'; then
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

ensure_base() {
  create_base_service
}

list_panels() {
  echo "当前已配置的面板实例:"
  if [ ! -d "$PANELS_ROOT" ] || [ -z "$(ls -A "$PANELS_ROOT")" ]; then
    echo "  (无面板，请先添加)"
    return
  fi
  for d in "$PANELS_ROOT"/*; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    echo "  - $name"
  done
}

add_panel() {
  ensure_base

  read -rp "为新面板输入一个标识名(例如: p1 / hk1): " PANEL_NAME
  PANEL_NAME="${PANEL_NAME// /}"
  if [ -z "$PANEL_NAME" ]; then
    echo "[ERROR] 面板标识名不能为空。"
    return
  fi

  PANEL_DIR="$PANELS_ROOT/$PANEL_NAME"
  if [ -d "$PANEL_DIR" ]; then
    echo "[ERROR] 面板目录 $PANEL_DIR 已存在，换一个名字。"
    return
  fi

  mkdir -p "$PANEL_DIR"
  cp -a "$BASE_DIR/." "$PANEL_DIR/"
  rm -f "$PANEL_DIR/device.id"

  read -rp "请输入该面板的后端地址 (IP:端口): " PANEL_ADDR
  read -rp "请输入该面板的密钥: " PANEL_SECRET

  CONFIG_FILE="$PANEL_DIR/config.json"
  if command -v jq >/dev/null 2>&1 && [ -f "$CONFIG_FILE" ]; then
    jq --arg addr "$PANEL_ADDR" --arg secret "$PANEL_SECRET" '.addr = $addr | .secret = $secret' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  else
    cat >"$CONFIG_FILE" <<EOF
{
  "addr": "$PANEL_ADDR",
  "secret": "$PANEL_SECRET"
}
EOF
  fi

  SERVICE_NAME="flux_agent_${PANEL_NAME}.service"
  cat >"$SYSTEMD_DIR/$SERVICE_NAME" <<EOF
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
  echo "[SUCCESS] 面板 $PANEL_NAME 添加完成并启动！"
}

remove_panel() {
  list_panels
  read -rp "请输入要删除的面板标识名: " PANEL_NAME
  PANEL_NAME="${PANEL_NAME// /}"
  PANEL_DIR="$PANELS_ROOT/$PANEL_NAME"
  SERVICE_NAME="flux_agent_${PANEL_NAME}.service"

  if [ ! -d "$PANEL_DIR" ]; then
    echo "[ERROR] 面板目录 $PANEL_DIR 不存在。"
    return
  fi

  systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
  rm -rf "$PANEL_DIR"
  rm -f "$SYSTEMD_DIR/$SERVICE_NAME"
  systemctl daemon-reload
  echo "[SUCCESS] 面板 $PANEL_NAME 已删除。"
}

remove_all_and_cleanup() {
  echo "[WARN] 该操作将删除所有面板和服务！"
  read -rp "确认继续？(yes/NO): " ans
  [ "$ans" != "yes" ] && echo "[INFO] 已取消。" && return

  for unit in $(systemctl list-unit-files 'flux_agent_*.service' --no-legend | awk '{print $1}') $(systemctl list-unit-files 'flux_agent@*.service' --no-legend | awk '{print $1}'); do
    systemctl disable --now "$unit" 2>/dev/null || true
    rm -f "$SYSTEMD_DIR/$unit" 2>/dev/null || true
  done

  rm -rf "$PANELS_ROOT"
  systemctl daemon-reload
  echo "[SUCCESS] 所有面板已清理完毕。"
}

menu() {
  show_existing_services

  while true; do
    echo ""
    echo "===== flux_agent 多面板管理 ====="
    list_panels
    echo "---------------------------------"
    echo "1) 添加新面板"
    echo "2) 删除面板"
    echo "3) 删除所有面板并清理服务"
    echo "0) 退出程序"
    echo ""
    read -rp "请选择操作 [0-3]（或 q 退出）: " choice
    case "${choice,,}" in  # 不区分大小写
      1)
        add_panel
        ;;
      2)
        remove_panel
        ;;
      3)
        remove_all_and_cleanup
        ;;
      0|q|quit|exit)
        read -rp "确认退出程序？(y/N): " confirm
        if [[ "${confirm,,}" == "y" || "${confirm,,}" == "yes" ]]; then
          echo "已退出。"
          exit 0
        else
          echo "已取消，继续管理。"
        fi
        ;;
      *)
        echo "无效选择，请重试。"
        ;;
    esac
    echo "按 Enter 继续..."
    read -r
  done
}

# 直接进入菜单（即使已有基础服务）
menu
