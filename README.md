# flux_multi

`flux_multi` 是一个用于在同一台服务器上 **多开 flux_agent、对接多个 Flux Panel 面板** 的一键管理脚本。  
它会自动处理目录划分、`device.id` 区分以及 systemd 服务创建，让多面板并存变得简单可控。  

> 适用环境：Debian / Ubuntu 等使用 systemd 的 Linux 服务器（需有 root 权限）。

---

## 功能特性

- 自动检测是否已安装基础 `flux_agent` 服务  
- 一键添加新面板：
  - 从基础目录复制一份独立实例
  - 删除 `device.id`，为新面板生成独立设备 ID
  - 更新 `config.json` 中的面板地址与密钥
  - 自动创建并启动对应的 systemd 服务  
- 一键删除面板：
  - 停止并禁用 systemd 服务
  - 删除对应目录与服务文件  
- 通过交互菜单管理多个面板实例，简单直观。  

---

## 一键安装 / 运行

在服务器上执行下面命令启动管理脚本（请根据实际仓库路径替换用户名与仓库名）：  

bash <(curl -fsSL https://raw.githubusercontent.com/echo00023/flux_multi/refs/heads/main/flux_multi.sh)

执行后会进入交互式菜单，无需手动编辑 systemd 单元文件。  

---

## 工作原理

### 目录结构

- 官方安装脚本默认目录：  
  - `/etc/flux_agent`
- 多面板实例根目录：  
  - `/etc/flux_agent_panels`
  - 每个面板一个子目录，例如：
    - `/etc/flux_agent_panels/p1`
    - `/etc/flux_agent_panels/hk1`

每个面板目录包含自己的一套：  

- `flux_agent` 二进制  
- `config.json` 配置  
- `device.id` 设备 ID（用于在面板侧区分不同节点）

这样可以保证不同面板之间互不影响。  

### systemd 服务命名

脚本为每个面板生成一个独立的 systemd 服务，例如：  

- `flux_agent_p1.service`  
- `flux_agent_hk1.service`  

服务配置中会指定：  

- `WorkingDirectory=/etc/flux_agent_panels/<面板名>`  
- `ExecStart=/etc/flux_agent_panels/<面板名>/flux_agent -C config.json`  

---


### 1. 第一次运行（创建基础服务）

如果系统上尚未安装 `flux_agent`，脚本会提示你输入：  

- 面板地址：`IP:端口`  
- 面板密钥：面板生成的节点密钥字符串  

脚本会调用官方 `install.sh` 在 `/etc/flux_agent` 中安装基础实例，用作后续复制模板。  

### 2. 添加新面板

选择菜单 `1) 添加新面板` 后，脚本会依次询问：  

1. 面板标识名（例如：`p1`、`hk1` 等）  
2. 该面板的后端地址（`IP:端口`）  
3. 该面板的密钥  

脚本会自动完成：  

- 在 `/etc/flux_agent_panels/<标识名>` 创建目录  
- 从 `/etc/flux_agent` 复制基础文件  
- 删除旧 `device.id`，为该实例生成新 ID  
- 更新 `config.json` 中的 `api` 与 `secret` 字段（若系统安装了 `jq`）  
- 创建并启动 `flux_agent_<标识名>.service`  

### 3. 删除面板

选择菜单 `2) 删除面板` 后：  

- 选择要删除的面板标识名  
- 脚本会停止并禁用对应服务  
- 删除该面板目录与服务文件  

### 4. 查看运行状态

你可以使用 systemd 命令查看某个面板的运行情况：  

systemctl status flux_agent_p1.service
journalctl -u flux_agent_p1.service -n 50 --no-pager


---

## 注意事项

- 脚本会使用官方 `install.sh` 安装基础实例，依赖于 `curl` 与 `systemd`。  
- 默认假设 `config.json` 中使用 `api` 与 `secret` 字段来保存面板地址与密钥，如你的配置结构不同，请根据实际字段名自行调整脚本中使用 `jq` 的部分。  
- 若再次手动执行官方 `install.sh`，可能会覆盖 `/etc/flux_agent` 中的内容，建议以后只通过本脚本管理多面板。  

---

## 许可证

本项目脚本仅用于学习与运维自用，如需在生产环境/商用场景中使用，请自行审阅风险并根据实际需求调整。  


