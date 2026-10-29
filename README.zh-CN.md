# BlackBerry 10 VoLTE 实验研究资料

[English — default documentation](README.md)

**注意** 如果你想直接使用 请参见Oleksandr的成果:https://github.com/bb10root/bb10-volte

本资料包整理了 BB10 10.3.3.3216 上的 VoLTE 实验、源码、配置、脱敏证据、失败边界，以及来自其他研究者的联通移植包。感谢 Oleksandr 的 [BB10 root 研究](https://bb10.root.sx/) 提供了研究所需的权限基础。

## 当前结果

| 设备与运营商 | 已知结果 | 边界 |
|---|---|---|
| Classic AT&T / 中国移动 460-00 | 本地实测 IMS 注册、去电、双向 RTP、原生莓标联动 | **来电尚未建立成功结论；已收到 Q20 无法接听的反馈** |
| Classic Verizon / 中国联通 460-01 | 提供的移植包记录 IMS 注册成功 | 本次整理未独立重测通话；不能据注册推断接打都成功 |
| Passport / 中国联通 460-01 v1.1 | 提供的资料记录去电、普通手机拨入并接听成功 | 属于提供者测试记录，尚未在本次交接独立复测 |
| Z30 STA100-3 / 中国移动 460-00 | 本地 LTE-only 搜网未注册，能力仅 B4/B13 | 卡在 LTE 频段接入，未部署 IMS 改动 |

**IMS 注册、去电、来电、双向语音和莓标显示是五件不同的事。不要将 Q20 描述为接打电话均已验证。**

## 资料内容

英文默认首页提供全部技术文档的导航，包括 DCA/IR92、IMS APN 与 P-CSCF、ESP NULL + HMAC-SHA1 软件供应器问题、原生莓标接口、Passport 来电改动、执行信任与备份恢复、构建、证据分级和待研究问题。

`variants/` 保留三个版本的脚本、源码与运营商 XML。`distributions/` 保留原始 ZIP 供对照，它们的旧版界面与说明为中文；研究材料以英文为默认。`src/` 是本地移动版的原始源码，不是已经把所有移植改动合并后的通用版本。

资料不含密钥、密码、SIM PIN、IMSI/ICCID、完整 SIP 鉴权日志、个人设备备份、黑莓固件程序或 NDK 库。不能把自己的原始日志或备份目录直接加到 GitHub。

## 来电差异

Passport 1.1 资料在 IMS 注册之外增加了语音域工程项、`AllowVoLteProvisioning` 和 IR92 兼容设置，并记录了普通手机来电成功。不过部分旧说明、脚本注释与后续结论存在不一致：这些改动尚不能直接证明是 Q20 来电问题的通用修复。详细对比见[英文来电分析](docs/03-incoming-calls.md)。

## 发布

GitHub 仓库根目录直接使用本目录内容，让 README.md 默认显示英文。建议先阅读 [PUBLICATION.md](PUBLICATION.md)，并运行 `python tools/validate_release.py .`。本次没有代为上传 GitHub，也没有为其他贡献者的材料擅自指定新许可证。
