# 测试记录

日期：2026-10-15
环境：DevEco Studio 6.x，HarmonyOS SDK API 24

## 已通过

- `assembleHap`：ArkTS 类型检查、资源编译、打包检查均成功。
- `PreviewBuild`：成功。
- DevEco Previewer：Phone、Tablet、Foldable 展开态、2in1 均成功渲染连接页，无溢出或裁切。
- API 24 手机模拟器：DevEco 安装成功，应用在 561 ms 内启动，Ability 进入 `FOREGROUND`。
- 模拟器界面：系统状态栏、底部安全区、标题、表单和按钮显示正常，无裁切。
- 表单状态：配对内容为空时连接按钮禁用；输入 `{}` 后按钮启用，提交后正确显示“请粘贴电脑端显示的完整配对 JSON”。
- 生命周期：后台/前台切换正常；强制停止后冷启动成功，临时配对输入未错误持久化。
- 包兼容性：`compatibleSdkVersion=20`，`targetSdkVersion=24`，设备类型为 `phone`、`tablet`、`2in1`。
- 上游协议核对：以 `QingJ01/ds-bot-app@7e1c3f6` 的 `/mobile/v1` 协议为基线，已核对配对、刷新、会话、消息、提交、取消、团队操作、审批与设备列表端点。
- 身份保护：已验证 HTTPS 限制、SPKI SHA-256 指纹格式、协议版本、`serverId` 以及会话所属主机的一致性检查。
- 手动配对：用户已在 API 24 模拟器中使用电脑端短期配对数据完成连接，HTTPS/SPKI 主机身份校验与设备批准流程通过。
- 源码凭据扫描：未发现写入仓库的令牌、API Key 或私钥。

## 非阻断提示

- DevEco 仍有 3 条 ArkTSCheck 建议，均是将固定颜色迁移到分层资源，不影响编译和运行。
- Hvigor 会对 Network Kit 和 Preferences 的可抛异常 API 输出静态提示；调用方已通过 `try/catch/finally` 处理失败与资源释放。
- 调试 HAP 尚未配置签名，产物为 `entry-default-unsigned.hap`。

## 后续回归建议

安装、运行与实际配对连接阻塞均已解除。后续建议继续回归令牌刷新、会话加载、消息往返和停止生成，并补充平板、折叠屏与 2in1 真机测试。
