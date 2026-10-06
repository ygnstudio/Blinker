# 状态图标路线图：对齐并超越 Status Trio

[返回 README](../README.md) · 状态：Stage 1–4 已交付（2026-10-06） · 分支：`dev`

## 方向

Blinker 的状态图标改编自已归档的 Status Trio（Apache 2.0，钉在 `d1672377`）。0.7.0 引入时刻意收敛了范围（不含 VPN、Wi-Fi 名称、蓝牙设备管理、BLE 扫描、DDC、更新器、分析）。本路线图推翻这一收敛：**对齐 Trio 的全部功能宽度，并在细节深度上超越它**。

两条硬约束：

1. **pt 对齐**：菜单栏图标渲染范围 16–36 pt 与 Trio 一致（Blinker 原本即一致），默认值对齐 Trio 的 20 pt。
2. **诚实声明**：凡无官方标准、依赖权限或硬件支持不一的能力，在设置与面板就地标注限制，不以模拟数据冒充真实状态。

## A 系列 · 对齐 Trio

| # | 项 | 数据源 | 权限 | 阶段 |
|---|------|--------|------|------|
| A1 | VPN 状态行（面板区块）✅ | getifaddrs 隧道探针 + SCNetworkService + 系统代理端点 | 无 | 2 |
| A2 | Wi-Fi 名称（SSID）+ 面板内定位权限引导行 ✅ | CoreWLAN + CoreLocation 授权流 | 定位 | 2 |
| A3 | 蓝牙设备列表：已配对、连接态、类型图标、电量（含 L/R/充电盒）、可见性、拖拽排序、上限 ✅ | system_profiler（上游同源方案） | 无新权限 | 3 |
| A4 | 附近 BLE 设备电量扫描（可关，默认关）✅ | CoreBluetooth GATT（180F/2A19 + DIS） | 蓝牙 | 3 |
| A5 | 声音输入区块（默认输入设备，音量/静音/使用中标记）✅ | CoreAudio | 无 | 2 |
| A6 | Wi-Fi 替换样式补全：个人热点 / 临时连接 / 互联网共享 ✅ | 网络类型分类（参照上游 WiFiMonitor） | 无 | 1 |
| A7 | 电池标记缩放放宽：0.9–1.1 → 0.5–2.0（数字/闪电统一）✅ | — | — | 1 |
| A8 | 面板行内齿轮直达对应设置页 ✅ | 设置窗路由 | — | 1 |
| A9 | 枚举选择器卡片化：显示位置 / 线条粗细 / Dock 背景 / 音量样式 ✅ | 复用 TrioIconRenderer / DockIconRenderer | — | 1 |
| A10 | 自然滚动与 MOS / Scroll Reverser / LinearMouse 冲突的诚实文案 ✅ | — | — | 1 |
| A11 | 区块与设备排序改拖拽（替换箭头按钮）✅ | — | — | 1 |

## B 系列 · 超越 Trio

| # | 项 | 数据源 | 权限 | 阶段 |
|---|------|--------|------|------|
| B1 | 电池深度：循环次数、健康度、温度、充放功率 ✅ | IOKit / AppleSmartBattery | 无 | 4 |
| B2 | 网络深度：实时上下行速率、本机 / 公网 IP 行 ✅ | getifaddrs / api.ipify.org（默认关） | 无（公网 IP 出网，已明示） | 4 |
| B3 | 蓝牙深度：RSSI ✅、编解码器与单设备断开 ✅ | 报告 RSSI；IOBluetooth（编解码/断开） | RSSI 无；编解码/断开走蓝牙授权（默认关） | 4 |
| B4 | 面板密度：舒适 / 紧凑两档 ✅ + 行级副标题显示自定义 ✅ | — | — | 4 |

## 阶段

1. **表现层**（已交付，`dde9544`）：A6、A7、A8、A9、A10、A11 + pt 默认值 20。无权限、无新数据源。
2. **面板内容**（已交付）：A1、A2、A5。新增定位权限引导（A2），Info.plist 已含 `NSLocationWhenInUseUsageDescription`。
3. **蓝牙域**（已交付）：A3、A4。配对设备走 `system_profiler`（与上游同方案：名称不陈旧、电量同报告、免权限、免私有 API）；BLE 扫描复刻上游候选过滤与并发/冷却策略（5 秒窗口 / 60 秒间隔 / 2 并发 / 8 队列 / 4 秒超时），Info.plist 已含 `NSBluetoothAlwaysUsageDescription`。HID usage 修正（罗技误标类）已补齐：连接中的 HID 设备按 I/O Registry 枚举的 usage 纠正报告里的厂商误标分类。
4. **超越项**（已交付）：B1–B4。电池深度走 IOKit 电池控制器（无权限，温度按控制器代际在厘开氏/分开氏/厘摄氏间按工作温域消歧）；网络深度走 getifaddrs 计数器差值（en* 物理接口，32 位回绕恢复）与本机 IPv4 选取（跳过链路本地占位地址），公网 IP 经 api.ipify.org（唯一出网行为，默认关，TTL 缓存 + 失败退避）；蓝牙 RSSI 沿用 system_profiler 报告字段（零权限），编解码器与单设备断开必须 IOBluetooth——该框架在 macOS 15 与附近扫描同属蓝牙隐私门控，故独立开关默认关、授权确认前 reader 不触碰 IOBluetooth；面板密度舒适/紧凑两档，全部副标题行均有独立开关。

每阶段验收：`swift build` + `swift test` 全量 + SwiftLint / SwiftFormat 通过；新配置键走 `MenuBarConfiguration+Coding` 向后兼容解码（缺键取默认）。

## Attribution 义务

扩大改编范围后必须同步更新：

- `ThirdParty/StatusTrio/README.md` 的 Scope and modifications 段（当前声明"不含 VPN、SSID、DDC"等，A1/A2 落地后需改写）与文件映射表；
- 设置内离线许可证视图（随 README 自动生效的话需确认）；
- CHANGELOG 对应条目。

## 已知取舍

- DDC 显示器亮度、应用内更新器、分析：维持不做，与 Trio 对齐目标无关。
- 公网 IP（B2）是唯一出网行为，默认关，开启时明示端点。
- HID usage 修正（上游遍历 IORegistry 纠正厂商误标的类型，如罗技键盘报为鼠标）已交付；未连接设备仍以系统报告的分类为准。
- BLE 结果 30 分钟有效期内按名折叠进配对列表（上游同规则）；非苹果移动设备留在附近行。
