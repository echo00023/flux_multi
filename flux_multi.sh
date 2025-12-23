#!/usr/bin/env bash
# flux_agent 多面板管理脚本 - 完整修复版
# 修复了：不进入菜单、退出不确认、添加面板时自动创建服务等问题

set -e

BASE_DIR="/etc/flux_agent"
PANELS_ROOT="/etc/flux_agent_panels"
SYSTEMD_DIR="/etc/systemd/system"

mkdir -p "$PANELS_ROOT"

show_existing_services() {
  echo "[INFO] 当前系统中的 flux_agent 相关服务："
  systemctl list-units 'flux_agent*.service' --no-pager --all 2>/dev/null || true
  echo
}

# 基础服务安装（只在第一次需要时运行）
create_base_service() {
  if [ -f "/etc/systemd/system/flux_agent.service" ] || systemctl list-unit-files | grep -q '^flux_agent\.service'; then
    echo "[INFO] 检测到基础 flux_agent 已存在，跳过安装。"
    return
  fi

  echo "[INFO] 未检测到基础 flux_agent，开始安装..."
  read -rp "请输入基础面板地址 (IP:端口): " BASE_ADDR
  read -rp "请输入基础面板密钥: " BASE_SECRET

  mkdir -p "$BASE_DIR"
  cd "$BASE_DIR"

  curl -L https://github.com/bqlpfy/flux-panel/releases/download/2.0.6-beta/install.sh -o install.sh
  chmod +x install.sh
  ./install.sh -a "$BASE_ADDR" -s "$BASE_SECRET"

  echo "[SUCCESS] 基础 flux_agent 安装完成。"
}

ensure_base() {
  if [ ! -d "$BASE_DIR" ] || [ ! -f "$BASE_DIR/flux_agent" ]; then
    create_base_service
  fi
}

list_panels() {
  echo "当前已配置的面板实例:"
  if [ ! "$(ls -A "$PANELS_ROOT" 2>/dev/null)" ]; then
    echo "  (无面板实例，请先添加)"
    return
  fi
  for d in "$PANELS_ROOT"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    status=$(systemctl is-active "flux_agent_${name}.service" 2>/dev/null || echo "unknown")
    echo "  - $name  (服务状态: $status)"
  done
}

add_panel() {
  ensure_base

  read -rp "输入新面板标识名 (英文/数字，如 p1, hk1): " name
  name=${name// /}
  if [ -z "$name" ]; then
    echo "[ERROR] 标识名不能为空"
    return
  fi
  if [ -d "$PANELS_ROOT/$name" ]; then
    echo "[ERROR] 面板 $name 已存在"
    return
  fi

  mkdir -p "$PANELS_ROOT/$name"
  cp -a "$BASE_DIR/." "$PANELS_ROOT/$name/"
  rm -f "$PANELS_ROOT/$name/device.id"

  read -rp "输入该面板地址 (IP:端口): " addr
  read -rp "输入该面板密钥: " secret

  config="$PANELS_ROOT/$name/config.json"
  if command -v jq >/dev/null 2>&1; then
    jq --arg a "$addr" --arg s "$secret" '.addr=$a | .secret=$s' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
  else
    sed -i "s|\"addr\": \".*\"|\"addr\": \"$addr\"|; s|\"secret\": \".*\"|\"secret\": \"$secret\"|" "$config"
  fi

  service="flux_agent_${name}.service"
  cat > "$SYSTEMD_DIR/$service" <<EOF
[Unit]
Description=Flux Agent Panel $name
After=network.target

[Service]
WorkingDirectory=$PANELS_ROOT/$name
ExecStart=$PANELS_ROOT/$name/flux_agent -C config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$service"
  echo "[SUCCESS] 面板 $name 添加成功并已启动！"
}

remove_panel() {
  list_panels
  read -rp "输入要删除的面板标识名: " name
  name=${name// /}
  if [ ! -d "$PANELS_ROOT/$name" ]; then
    echo "[ERROR] 面板 $name 不存在"
    return
  fi

  service="flux_agent_${name}.service"
  systemctl disable --now "$service" 2>/dev/null || true
  rm -f "$SYSTEMD_DIR/$service"
  rm -rf "$PANELS_ROOT/$name"
  systemctl daemon-reload
  echo "[SUCCESS] 面板 $name 已删除"
}

remove_all() {
  read -rp "警告：将删除所有面板和服务！输入 yes 确认: " confirm
  [ "$confirm" != "yes" ] && echo "已取消" && return

  for s in "$SYSTEMD_DIR"/flux_agent_*.service; do
    [ -f "$s" ] || continue
    systemctl disable --now "$(basename "$s")" 2>/dev/null || true
    rm -f "$s"
  done
  rm -rf "$PANELS_ROOT"
  systemctl daemon-reload
  echo "[SUCCESS] 所有面板已清理"
}

menu() {
  clear
  show_existing_services
  while true; do
    echo "===== flux_agent 多面板管理 ====="
    list_panels
    echo
    echo "1) 添加新面板"
    echo "2) 删除指定面板"
    echo "3) 删除所有面板并清理"
    echo "0) 退出程序"
    echo
    read -rp "请选择 [0-3]: " choice

    case "$choice" in
      1) add_panel ;;
      2) remove_panel ;;
      3) remove_all ;;
      0) 
        read -rp "确认退出？(y/N): " yn
        [[ "$yn" =~ ^[Yy]$ ]] && echo "再见！" && exit 0
        ;;
      *) echo "无效选项，请重试" ;;
    esac
    echo
    read -rp "按 Enter 键继续..." 
    clear
    show_existing_services
  done
}

# 关键：真正进入交互菜单
menu
