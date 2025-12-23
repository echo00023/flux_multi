# flux_multi - Flux Agent 多面板管理脚本

一个简单实用的 Bash 脚本，用于在同一台服务器上管理多个 **Flux Agent** 实例（多面板）。  
基于 [flux-panel](https://github.com/bqlpfy/flux-panel) 的客户端代理程序，实现轻松添加、删除和清理不同面板的独立运行实例。

## 项目背景

Flux-panel 是一个功能强大的流量转发管理平台（基于 gost），其客户端程序 `flux_agent` 通过连接不同面板的后端，实现流量代理、计费、限速、设备管理等功能。

官方安装脚本仅支持单实例运行。本脚本通过复制配置目录、生成独立 systemd 服务的方式，实现**多面板共存**，每个面板拥有独立的：

- 配置目录（`/etc/flux_agent_panels/<标识名>`）
- `config.json`（独立的地址与密钥）
- `device.id`（重新生成，确保新设备 ID）
- systemd 服务（`flux_agent_<标识名>.service`）

适用于需要同时连接多个 Flux 面板的用户（如多账号、多地区节点管理）。

## 功能特性

- 交互式菜单操作（添加、删除、批量清理、退出）
- 首次运行自动安装基础 Flux Agent
- 为每个面板自动创建独立的 systemd 服务，支持开机自启与自动重启
- 支持 `jq` 优雅修改 `config.json`，无 `jq` 时使用兼容方式
- 删除旧 `device.id`，确保新面板生成全新设备 ID
- 实时显示当前所有 `flux_agent*` 服务状态与已配置面板列表
- 安全退出确认，防止误操作
- 批量清理功能（仅清理自定义面板，不影响官方单实例服务）

## 使用方法

### 一键运行

bash <(curl -fsSL https://raw.githubusercontent.com/echo00023/flux_multi/refs/heads/main/flux_multi.sh)

或使用短链（若可用）：

Bashbash <(curl -fsSL https://go.saku.foo/https://raw.githubusercontent.com/echo00023/flux_multi/refs/heads/main/flux_multi.sh)

脚本启动后会自动进入交互式菜单：
text===== flux_agent 多面板管理 =====
当前已配置的面板实例:
  - p1  (服务状态: active)
  - hk1 (服务状态: active)

1) 添加新面板
2) 删除指定面板
3) 删除所有面板并清理
0) 退出程序

请选择 [0-3]:
## 操作说明

添加新面板
输入唯一标识名（建议使用半角英文、数字，如 p1、us1、hk2）
输入该面板的后端地址（格式：IP:端口）
输入该面板的密钥
→ 自动创建目录、修改配置、生成并启动 systemd 服务

删除指定面板
输入要删除的面板标识名
→ 停止服务、删除目录和服务文件

删除所有面板并清理
需要输入 yes 确认
→ 删除所有自定义面板目录及对应 systemd 服务

退出程序
需要二次确认，防止误退出


## 路径说明

基础安装目录：/etc/flux_agent
多面板配置根目录：/etc/flux_agent_panels/<标识名>/
服务文件位置：/etc/systemd/system/flux_agent_<标识名>.service
日志查看：journalctl -u flux_agent_p1.service -f

## 注意事项

标识名必须为半角字符：只能包含英文字母、数字、下划线 _、破折号 -。禁止使用中文、全角字符、空格，否则会导致 systemd 服务创建失败。
依赖工具：curl、systemctl、jq（可选）
首次运行若系统中未检测到基础 flux_agent，脚本会自动下载并安装官方客户端（来自 bqlpfy/flux-panel v2.0.6-beta）
本脚本不会修改或删除官方的单实例服务 flux_agent.service
添加面板后若服务启动失败，请查看日志：journalctl -u flux_agent_<标识名>.service

## 常见问题
Q: 添加面板后服务启动失败？
A: 常见原因：地址/密钥错误、网络不通、端口被占用。请执行 journalctl -u flux_agent_p1.service -f 查看详细日志。

Q: 如何查看所有 Flux Agent 服务状态？
A:Bashsystemctl list-units 'flux_agent*.service'

Q: 如何手动修改某个面板的配置？
A: 编辑对应目录下的配置文件：
Bashnano /etc/flux_agent_panels/p1/config.json
修改后重启服务：
Bashsystemctl restart flux_agent_p1.service

Q: 想删除旧的 device.id 重新绑定设备？
A: 删除对应目录下的 device.id 文件后重启服务即可：
Bashrm /etc/flux_agent_panels/p1/device.id
systemctl restart flux_agent_p1.service

# 贡献与反馈
欢迎提交 Issue 或 Pull Request 改进脚本！
仓库地址：https://github.com/echo00023/flux_multi
