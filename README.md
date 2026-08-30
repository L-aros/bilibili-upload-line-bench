# Bilibili 投稿线路网络测评

[中文](README.md) | [English](README_EN.md)

`biliup.sh` 是面向 Linux VPS 的 B站投稿线路专项测评脚本，用于评估服务器与 B站之间的双向网络质量，尤其适合部署了 biliLive-tools 的录播投稿服务器。

默认测试全部是只读操作，不登录账号、不上传文件、不创建投稿，主要检查：

- B站主站、公共 API、投稿 API 和静态 CDN 是否可达；
- B站 `preupload` 接口当前给出的自动投稿候选；
- biliLive-tools 各条 UPOS 投稿线路的 DNS、TCP、TLS、TTFB、总耗时、P95、抖动和成功率；
- 可选的公开视频 CDN 下载吞吐，用于观察“B站到服务器”方向。

## 快速开始

```bash
chmod +x biliup.sh
./biliup.sh
```

通过 GitHub 下载运行：

```bash
curl --proto '=https' --tlsv1.2 -fsSLO \
  https://raw.githubusercontent.com/L-aros/bilibili-upload-line-bench/main/biliup.sh
chmod +x biliup.sh
./biliup.sh
```

建议先下载并检查脚本再运行；无需 root 权限，也不会自动安装软件包或修改系统网络配置。

增加样本数并测试旧线路：

```bash
./biliup.sh --samples 15 --all-lines
```

使用一个公开 BVID 测试 B站 CDN 下载方向：

```bash
./biliup.sh --bvid BVxxxxxxxxxx --download-mb 64
```

保存报告：

```bash
./biliup.sh --samples 15 --output bili-bench-$(date +%F-%H%M).log
```

## 依赖

必需：Bash 4+、`curl`、`awk`、`sort` 以及常见 GNU/Linux 基础工具。

推荐安装 `python3`，用于可靠解析 B站动态线路和 BVID 播放地址。没有 Python 时，基础投稿线路测试仍可运行。

## 如何判断

线路排序首先比较成功率，然后比较 P95 和抖动：

- `A`：所有样本成功且延迟、抖动较低；
- `B`：所有样本成功，质量可以接受；
- `C`：存在高延迟或少量失败，长视频投稿有风险；
- `D`：失败较多，不建议选择。

`/OK` 探测不会发送视频数据，适合长期、重复比较线路。它能发现 DNS 失败、TLS 建连问题、HTTP 500 和明显抖动，但不能百分之百模拟长视频的分片 PUT 与合并流程。

建议在每天业务高峰和低峰分别运行，至少使用 `--samples 15`。如果 `auto` 候选会变化，而某条固定线路持续排名靠前，可在 biliLive-tools 中选择对应线路并降低上传并发。

脚本末尾的“当前推荐候选”只代表本次网络采样。正式切换生产线路前，建议比较至少两次不同时段的报告。常见 curl 错误码为：`6` DNS 解析失败、`7` 建连失败、`28` 超时、`35` TLS 失败、`60` 证书校验失败。

## 参数

运行 `./biliup.sh --help` 查看全部参数。默认使用 IPv4；只有服务器和 B站目标均具备正常 IPv6 时才使用 `--ipv6`。

## 兼容性

- Ubuntu、Debian、CentOS Stream、Rocky Linux、AlmaLinux 等常见 Linux 发行版；
- amd64、arm64 等能够运行 Bash 与 curl 的架构；
- 无需 root；
- 默认不安装或卸载依赖，不修改防火墙、路由、DNS、sysctl 或 Docker 配置。

## 测试边界

本项目定位是网络测评，不是投稿客户端。详细指标、动态线路映射和安全小请求无法覆盖的场景见 [测评指标与边界](docs/METRICS.md)。隐私及临时文件处理见 [安全说明](SECURITY.md)。

## 仓库结构

```text
.
├── biliup.sh                 # 可独立下载执行的入口脚本
├── README.md                 # 中文文档
├── README_EN.md              # English documentation
├── CHANGELOG.md
├── VERSION
├── LICENSE
├── SECURITY.md
├── docs/METRICS.md           # 指标定义、评级与限制
├── tests/smoke.sh            # 无网络冒烟测试
└── .github/workflows/lint.yml
```

## 致谢与声明

- 仓库展示和单脚本运行方式参考 [spiritLHLS/ecs](https://github.com/spiritLHLS/ecs)；
- 投稿线路选择器参考 [renmu123/biliLive-tools](https://github.com/renmu123/biliLive-tools)；
- UPOS 请求流程参考 [renmu123/biliAPI](https://github.com/renmu123/biliAPI)。

本项目与哔哩哔哩无隶属或官方合作关系。B站接口和线路映射可能随时变化，请勿将一次测评结果视为长期服务承诺。

## 开源许可

[MIT](LICENSE)
