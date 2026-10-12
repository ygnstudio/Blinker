# Blinker 界面规范入口

唯一生效规范：[design-spec.md](design-spec.md)。开发或审查界面时，先读执行速查，再查对应章节及实现入口；此文件不另定义 token、布局或动效。

- 当前规则：窗口、功能归属、材质透明度、尺寸留白、圆角分割、控件、输入、动画、扩展和验收。
- 验收证据：[macOS 26–27 审查](docs/macos26-ui-audit.md)，按构建和场景记录，不代表全部通过。
- 历史资料：[历次设计修订](docs/ui-design-history.md)、[初始审查](docs/ui-system-proposal.md)、[HTML 设计稿](docs/ui-system-preview.html)，不覆盖当前规范。

修改规则时直接更新 design-spec.md 的原条目；数值和组件同步核对代码，验证全部受影响消费者。用户新确认的要求优先于旧规则，差异与尚未验证项必须明确记录。
