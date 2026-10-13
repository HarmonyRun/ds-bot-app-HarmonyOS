# 移动端与 DS Bot / DeepSeek Harness 对齐清单

本清单以本仓库 DS Bot 源码和所用 Harness 版本的公开插件文档为准。Grok 仅用于手机交互尚无原版对应时的参考，不能覆盖原版 Bot 的权限、群聊、长期会话和数据语义。

核对基线：DS Bot `351ae74` 加当前工作区改动；Harness checkout `5badb15`；第一轮移动客户端 `0.1.0`。以下“初始移动端”指本轮补齐开始前的源码状态，不能据此判断后续已修改代码仍存在同一差距。已验证交付另见[移动端验证记录](mobile-validation.zh.md)。这是源码及公开接口审查；尚未据此声称两端像素一致或所有原生设备行为已验证。

状态分类：**界面可补**＝数据和移动接口已有；**桥接可补**＝DS Bot 自有能力或 Harness 公开服务已有，但移动协议尚未暴露；**平台适配**＝能力依赖桌面、浏览器或原生环境，需要明确等价实现；**待公开接口核实**＝不能先写成“不支持”。“手机尚未实现”不是“上游 API 缺失”。

## 优先修正的行为差异

| 编号 | 原版基线及证据 | 初始移动端差距及证据 | 接口与处理边界 |
| --- | --- | --- | --- |
| B01 | 群聊至少两名 Bot；新群先选管理员，再选其他成员。[group-settings.js](../ds-bot/src/client/group-settings.js#L103) | 保存只检查 `members.length` 非零，会让单成员群进入服务器拒绝路径。[TeamScreen](../apps/mobile/src/screens/TeamScreen.tsx) 初始保存校验 | **界面可补**：`create-room` / `update-room` 已开放，校验应与主机一致。 |
| B02 | 群名可为空，自动采用成员名称；清空已命名群可恢复自动命名。[group-settings.js](../ds-bot/src/client/group-settings.js#L51) | 强制 `group.name.trim()` 非空，无法恢复自动命名。 | **界面可补**：`update-room {name:""}`；保留 `named` 标志，不能把自动生成名称当用户自定义名称再保存。 |
| B03 | 模式为 `Admin leads` / `Everyone`，可取消管理员；无有效管理员时按 Everyone 展示。[group-settings.js](../ds-bot/src/client/group-settings.js#L9) | 显示 `Coordinator`；无清除管理员入口；保存时默认补第一个成员为管理员。 | **界面可补**：`update-room {admin:null}`、`mode`；同步“@mentions always pick who answers”说明。 |
| B04 | `Main Bot` 是角色；Chief 只是默认名称。支持多个主 Bot、交接首位主 Bot，唯一主 Bot不能直接降级。[settings.js](../ds-bot/src/client/settings.js#L71)、[bot-settings.js](../ds-bot/src/client/bot-settings.js#L200) | 所有主 Bot显示 `· Chief`；没有角色切换/交接；编辑页仍显示删除按钮。 | **界面可补**：`set-main {id,main,primary,replace}` 已开放；应遵守主机主 Bot约束并展示原版解释。 |
| B05 | Bot 名称最多40字符，角色标签最多24，群名60，群公告2000。[bot-settings.js](../ds-bot/src/client/bot-settings.js#L218)、[group-settings.js](../ds-bot/src/client/group-settings.js#L51) | Bot 名称80；角色、公告等缺少相同输入限制。 | **界面可补**：限制只改善输入反馈，主机仍是最终校验者。 |
| B06 | 原版用量的 Input 包括 cache write；另列 cache hit，分母、总量遵循同一口径。[usage-data.js](../ds-bot/src/client/usage-data.js#L90) | 只把 `row[4]` 汇总为 Input，漏掉 cache write；未显示 cache hit。 | **界面可补**：已有 `usage` 返回 `[hour,owner,model,kind,input,cacheRead,cacheWrite,output,calls]`。不能把漏算的数值称为完整输入量。 |
| B07 | 新对话是选择现有 Bot、建 Bot、建群或创建普通 DSH Agent Session；选择现有 Bot重新打开原对话。[new-chat.js](../ds-bot/src/client/new-chat.js#L49) | 手机没有原版新对话选择器；当前直接进入主 Bot，没有错误的新建 part 行为。 | **界面可补 / 桥接可补**：Bot选择可直接补；普通 Agent另见 H06。必须保持一个 Bot一条长期逻辑对话，不能用创建 part冒充新聊天。 |
| B08 | 删除 Bot/群会移出团队并归档聊天；群成员仍保留。[bot-settings.js](../ds-bot/src/client/bot-settings.js#L243)、[group-settings.js](../ds-bot/src/client/group-settings.js#L93) | 删除确认只说移出主机/团队，未说明历史归档；手机本地记录可能继续存在。 | **界面可补**：同步原版文案，并区分主机归档、手机缓存与真正删除。 |

## 导航、视觉、状态和文案

| 编号 | 原版基线及证据 | 初始移动端状态 | 可补范围 |
| --- | --- | --- | --- |
| V01 | 默认 DeepSeek 主题是黑白主表面与蓝色强调色；另有 Mono、Paper、Moonlight，分别定义明暗模式。[themes.js](../ds-bot/src/client/themes.js#L9) | [theme.ts](../apps/mobile/src/theme.ts) 只随系统明暗变化，采用独立绿色配色。 | **界面可补**：使用相同8个基础色语义，并读取已有 `state.prefs`；不应只把一个绿色按钮换蓝就称视觉对齐。 |
| V02 | 主题、强调色是主机持久偏好，文案明确“on every device”；另有 Quiet/Normal/Lively 动画偏好。[settings.js](../ds-bot/src/client/settings.js#L37) | 无设置入口，忽略 prefs。 | **桥接可补**：DS Bot `set-prefs {theme,accent,motion}` 已存在；初始 mobile action白名单未开放。原生动画需尊重系统减少动态效果。 |
| V03 | Bot使用可选角色造型、色彩或照片；主 Bot、管理员、工作/等待/未读有独立标识。[characters.js](../ds-bot/src/client/characters.js)、[mark.js](../ds-bot/src/client/mark.js)、[sidebar.js](../ds-bot/src/client/sidebar.js#L43) | 用名字首字母的圆角方块；仅识别十六进制 `bot.color`，原版命名色不能正常映射；未显示头像形状/图片。 | **界面可补**：state已返回 avatar/color，`update-bot` 已允许这两字段。自定义插件注册的 SVG/主题不应假定可自动在 RN执行。 |
| V04 | 左侧主 Bot优先，其余聊天按 pin、活动时间排列；隐藏仍可被搜索找到。[sidebar.js](../ds-bot/src/client/sidebar.js#L220)、[palette.js](../ds-bot/src/client/palette.js#L52) | Chat/Team/Settings三页，聊天选择为简单列表，未还原 pin/hidden 操作和全部可见状态。 | **桥接可补**：`set-flags {id,pinned,hidden}` 是 DS Bot既有接口；默认排序、工作/等你回答/未读可以据state和conversation数据实现。手机抽屉替代桌面侧栏属于等价适配。 |
| V05 | 详情入口含名称、角色、模型、说明、记忆、用量、计划任务，群含公告、成员和管理员。[details-drawer.js](../ds-bot/src/client/details-drawer.js#L121) | Bot管理移到Team页，聊天页无完整详情层；群详情信息分散。 | **界面可补**：以手机详情Sheet/页面保留原信息分组和入口，不能只提供编辑表单。 |
| V06 | 原版字符串通过 `t()` 跟随 DSH语言，可切换中英文，日期使用对应locale。[i18n.js](../ds-bot/src/client/i18n.js#L1) | 手机页面硬编码英文，未承接DSH语言。 | **界面可补 / 桥接可补**：先复用本项目字符串语义；Harness语言设置的读取/写入应使用公开设置能力，见H03。没有语言状态时明确手机本地选择，不能伪称已同步。 |
| V07 | Working、Waiting for your answer、Unread activity、模型未配置/已不可用分别展示；头像与活动行反映工作类型。[sidebar.js](../ds-bot/src/client/sidebar.js#L43)、[cells.js](../ds-bot/src/client/cells.js#L429) | 多数状态归为Connected/Thinking/replying；聊天运行与连接状态容易混在一起。 | **界面可补 / 桥接可补**：连接、主机执行、等待用户、等待审批应分开；工具生命周期和审批投影参见C03/H01。 |
| V08 | 原版表单原位保存；失败保留输入并在对应表面显示错误；删除有明确二次确认。[bot-settings.js](../ds-bot/src/client/bot-settings.js#L35) | 手机采用Save按钮与Sheet，错误有时位于外层页。 | **界面可补**：手机可保留显式保存，但校验、成功、失败、重复点击、退出未保存和禁用态必须完整；不能要求桌面hover才可操作。 |

## 聊天和多模态

| 编号 | 原版基线及证据 | 初始移动端状态 | 接口与差距性质 |
| --- | --- | --- | --- |
| C01 | DSH Markdown组件处理消息正文，DS Bot加 @引用、代码复制等。[cells.js](../ds-bot/src/client/cells.js#L16) | MessageBubble只识别围栏代码、粗体和行内代码；标题、链接、表格、引用等未等价渲染。[MessageBubble](../apps/mobile/src/components/MessageBubble.tsx) | **界面可补**：正文已返回；RN渲染器需明确支持列表和安全链接方案，不能在手机执行消息HTML。 |
| C02 | 原版回复支持引用回复、本地反应、复制和Markdown下载。[cells.js](../ds-bot/src/client/cells.js#L64)、[index.js](../ds-bot/src/client/index.js#L484) | Copy、Share、Read aloud已有；无引用和反应，无法整段对话导出。 | **界面可补**：反应原版本来是本地数据，不应误写成需要主机API；引用可以同原版转文本前缀；对话导出应声明是已加载部分还是完整历史。 |
| C03 | reasoning、工作活动、普通工具与特定Bot工具有各自呈现；原版也有主动隐藏的内部团队turn。[cells.js](../ds-bot/src/client/cells.js#L102)、[cells.js](../ds-bot/src/client/cells.js#L532) | mobile projection只保留用户/助手文本和群relay回复；工具call只是用于识别relay，普通tool结果、reasoning被丢弃。[projection.js](../ds-bot/src/mobile/projection.js#L12) | **桥接可补**：公开Session事件/流可投影类型化活动、reasoning和安全工具摘要；不得取消原版hiddenTurns等过滤，把隐藏内部轮次全部泄露到聊天。 |
| C04 | 对话有日期、turn耗时、新消息分隔、群发言者、失败原因和交接标记。[cells.js](../ds-bot/src/client/cells.js#L259) | 仅作者+正文，多数source事件未进入移动投影；失败群reply是system文本。 | **界面可补 / 桥接可补**：时间和作者已有；schedule、handoff、bot request/reply需保留类型化source语义。不能把系统通知画成Bot正常回答。 |
| C05 | 群进行中显示当前发言者、已收到回复及各成员失败；@成员决定回应者。[cells.js](../ds-bot/src/client/cells.js#L484)、[group-settings.js](../ds-bot/src/client/group-settings.js#L62) | 群最终回复可见；缺完整实时成员进度/来源导航。 | **界面可补**：`room-progress {roomId}` 已开放；主机仍执行群路由，不在手机并行复制发给所有成员。 |
| C06 | 模型按provider分组，显示Default、已不可用、已应用/下条生效；打开选择器刷新目录。[model-menu.js](../ds-bot/src/client/model-menu.js#L16) | 按钮列表能切换，但无完整分组、默认、appliedModel状态；初始创建强制model非空。 | **界面可补**：state/models/update-bot 已有；无模型时显示原版引导，模型供应商设置另见H03。 |
| C07 | 用户提问卡有问题、选项、单/多选、自定义答案、提交/过期状态。[questions.js](../ds-bot/src/client/questions.js) | QuestionCard已有，但需逐项验证required、自定义、单/多选和跨设备已回答冲突。 | **界面可补**：`answer-question` / `dismiss-question` 已有；失效必须由questionId校验，不能重投普通聊天来伪造回答。 |
| C08 | 输入器支持引用、@选择、附件、录音及运行时操作。[composer.js](../ds-bot/src/client/composer.js) | 文本、图片/TXT/MD、录音转写、队列删除已有；引用与完整@交互不足。 | **界面可补**：已有prompt与附件接口；保持提交去重与当前session绑定。附件支持范围不能超过bridge和模型真实能力。 |
| C09 | 原版语音模式有Listening→Thinking→Speaking循环、暂停、听见/说出的字幕。[voice.js](../ds-bot/src/client/voice.js#L54) | 录音整段转写后编辑发送，另有手动Read aloud；没有同一语音会话循环。 | **平台适配**：已有whole-clip ASR和本机TTS可实现轮替模式；这不是全双工，不等于浏览器SpeechRecognition可直接运行于RN。自动发送、权限/中断/后台停止必须显式处理。 |
| C10 | 图片是可查看的消息内容，文件关联其消息；桌面上下文可打开主机资源。 | 初始图片点击下载后才出现预览，TXT/MD仅显示available on host。 | **界面可补 / 桥接可补**：鉴权图片下载已存在；文件下载/预览要有对应公开attachment读取与归属验证。不能把主机路径直接当手机URI。 |
| C11 | 搜索同时搜Bot/群名称、角色、DSH Agent、命令和已投影消息；原版只查当前part turnOutline且最多30条。[palette.js](../ds-bot/src/client/palette.js#L26) | 仅搜索当前对话本地缓存，清楚标注不搜主机全历史。 | **界面可补**：名称/命令搜索不需新主机API。跨part全文不是原版palette现成能力；模型工具read_own_chat不等于用户端公开search接口。 |
| C12 | 原版较早part可翻阅；Bot保持身份和逻辑对话连续。[cells.js](../ds-bot/src/client/cells.js#L184) | history分页、缓存和重连已有，需保留。 | **已具备基础**：补UI时不得破坏跨part历史游标、当前part发送、重复帧去重、旧配对不重放。 |

## 团队管理和设置

| 编号 | 原版基线及证据 | 初始移动端状态 | 对应能力 |
| --- | --- | --- | --- |
| S01 | Bot profile包含头像、角色、指令、模型、记忆、任务、主Bot、pin/hide、duplicate。[bot-settings.js](../ds-bot/src/client/bot-settings.js#L188) | 只有name/role/instructions/model和删除。 | 已有create/update/duplicate/set-main；set-flags需要桥接。复制应说明保留工作与模型、记忆重新开始。 |
| S02 | 记忆有summary/all entries、重生成、更新中/更新时间、Ask or update以及修改结果。[memory-panel.js](../ds-bot/src/client/memory-panel.js#L204) | 只有条目读取和删除。 | **界面可补**：`memory-view {botId,summarize,regenerate}`、`memory-ask {botId,text}` 已开放；不能把summary生成中显示为空记忆。 |
| S03 | 用量含24h/7d/30d/12w/12m/自定义范围、Bot/model分组、缓存命中率、时间序列与活动热图。[usage-page.js](../ds-bot/src/client/usage-page.js#L380) | 只有所有记录的Input/Output/Requests总和。 | **界面可补**：usage现有返回足够支持原版统计视图；至少口径、范围、分组和选择状态等价，图表按手机宽度适配。 |
| S04 | 定时任务可查/创建/删除，支持一次、每天、每周、重复，显示目标、时区、下一次、已结束；可用于Bot或群。[schedules.js](../ds-bot/src/client/schedules.js#L108) | 没有入口。 | **桥接可补**：自有`schedules`/`schedule-create`/`schedule-delete`委托公开`ctx.schedule.catalog/create/delete`，[host/schedules.js](../ds-bot/src/host/schedules.js#L93)。服务未启用返回available:false，不可伪造成功。 |
| S05 | Secrets包含名称、用途、授权Bot范围，聊天有请求卡；已有值绝不回传。[channel.js](../ds-bot/src/host/channel.js#L52)、[secret-card.js](../ds-bot/src/client/secret-card.js) | state过滤掉secrets/secretRequests，无管理页和请求卡。 | **桥接可补，不是上游API缺失**：DS Bot自有secret-set/allow/cancel/update/delete已有；见下方敏感设置边界。 |
| S06 | GitHub Connector支持令牌输入、连接中、账号、错误重试、断开。[connectors.js](../ds-bot/src/client/connectors.js) | 无入口且state过滤connectors。 | **桥接可补**：connector-connect/disconnect/retry 已有；一次性写入密钥，响应只返回元信息，状态遵循主机。 |
| S07 | Feedback提供兼容性诊断、客户端/主机错误、报告复制与日志清除/下载。[feedback.js](../ds-bot/src/client/feedback.js#L48) | 只有界面errorText，无诊断页。 | **桥接可补**：diagnostics/diagnostics-log/diagnostics-clear 自有接口；移动客户端需提供自己的平台版本/错误摘要并继续执行脱敏，不能直接共享全环境。 |
| S08 | 原版提供Classic Agent模式、Plugins/Harness settings、更新入口。[settings.js](../ds-bot/src/client/settings.js#L63)、[sidebar.js](../ds-bot/src/client/sidebar.js#L266) | 无对应入口。 | **分项适配**：普通Agent见H06；插件配置见H03；更新主机和更新手机是两件事，不能将host update-install伪装成App升级。 |

## Harness公开能力与真正的平台边界

这里的“公开”指文档声明的Cordis服务、事件和Remote namespace。DS Bot自身的`/api/bot` handler可以在插件内复用；不得读取Harness安装目录、复制私有实现或修改Harness。

| 编号 | 能力 | 已核实证据 | 结论与必要约束 |
| --- | --- | --- | --- |
| H01 | 工具审批 | [公开approval文档](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15/docs/subsystems/approval.md)声明`ctx.approval`、`approval/request` waterfall、`approval/asked`/`approval/decided`事件，支持UI channel提供answerer。 | **存在公开扩展缝隙，不能说只能桌面审批**。初始mobile没有审批接口。若接入，需按请求/Session归属展示动作原因，保留取消、超时、多端竞争单决、ask/never策略与默认拒绝；不能把普通user-question当审批。具体answerer顺序和SDK协议需实现及集成验证后才标完成。 |
| H02 | 工具、reasoning、会话状态 | [Session公开文档](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15/docs/subsystems/session.md)、[工具执行文档](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15/docs/tool-execution-pipeline.md)；当前adapter已经使用公开Session读/流。 | **桥接可补**。投影数据可供RN原生展示；Harness浏览器React Slot组件不能直接被当作RN组件复用，动态插件专属UI需要renderer适配或清晰降级。 |
| H03 | Harness Settings、模型供应商和插件配置 | [公开settings文档](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15/docs/subsystems/settings.md#ctxsettingscontroller--settingscontroller)列出`ctx.settingsController.describe/update/replace/mutate`，remote读一律`redactSecrets:true`；修改支持expectedRevision与冲突拒绝。 | **有公开API，可通过受控桥接补齐**。需消费schema/当前revision/secret字段提示，使用mutate/update保留未返回的密钥，不能把redacted值整体replace造成密钥被清空。打开主机设置文件`openSettingsDocument`是主机桌面动作，不是手机编辑器。并非所有插件自定义浏览器页面都能由schema自动重建。 |
| H04 | DS Bot Secrets | 自有[channel handler](../ds-bot/src/host/channel.js#L205)和[secret实现](../ds-bot/src/host/secrets.js#L303)已支持授权、取消、范围修改和删除；secretView仅出元信息。 | **插件内可补齐**，无需修改Harness。新值仅HTTPS一次性提交，不能进SQLite草稿、重放队列、日志、剪贴板自动复制或响应；已有值不能“显示明文”。授权卡必须绑定requestId，失效不应当重新授权。 |
| H05 | Bot Desktop浏览器 | [bot-browsers.js](../ds-bot/src/client/bot-browsers.js#L1)依赖`dshDesktop.browser.acquire('bot:<id>')`、Electron webview、Desktop本地tab状态和独立cookie分区；`browser-wait/result`仅是read_browser请求/结果通道。[index.js](../ds-bot/src/client/index.js#L546)无Desktop bridge时不注册浏览器控制。 | **真实平台差异**：现有主机接口不是“远程操作桌面标签页”的公开接口。手机独立WebView不会自动继承Desktop登录态，普通外链也不等价。可审查公开browser-use provider的能力并实现独立适配；在API证据和会话归属机制完整前，保留明确Desktop能力说明，不能假称同一浏览器。 |
| H06 | DSH Agent普通会话 | DS Bot现有add-agent/agent-session/agent-adopt/agent-archive/agent-rename/remove-agent，[channel.js](../ds-bot/src/host/channel.js#L170)；与Bot长期会话是不同身份。 | **桥接可补**：初始mobile state未返回agents，conversations只覆盖Bot/群。需独立identity/创建归属/历史/模型/工作区配置，不可把普通Session强行注册成Bot或改Bot part语义。 |
| H07 | 原版语言、深浅色和客户端偏好 | DS Bot [installLocale/language](../ds-bot/src/client/i18n.js)跟随Harness客户端；Bot主题保存在state.prefs；Harness [locale-settings.ts](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15/packages/client/locale/src/locale-settings.ts)公开namespace `locale`、字段`preference`，内置zh/en。 | **可通过公开settings同步宿主语言**；手机仍需自己的翻译渲染与偏好订阅，不是保存locale就自动翻译RN页面。Bot主题与Harness明暗模式是独立偏好，来源不能混淆。 |
| H08 | 动态插件客户端UI、终端、桌面资源与更新 | [Extensions公开文档](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15/docs/subsystems/extensions.md)区分Host/Client halves；[Web client文档](https://github.com/deepseek-ai/deepseek-harness/blob/5badb15/docs/subsystems/web-client.md)定义浏览器组件与slots。 | **平台适配，不是统一一个缺接口结论**：Host动作与数据可能可桥接；浏览器DOM、Electron窗口、终端交互和本机文件路径需要分别实现renderer或宿主适配。未实现的表面需保留真实能力提示，不能用无响应按钮占位。 |

## 对齐验收规则

每项完成都要同时检查正常、空、加载、失败、权限/能力不可用、离线、重连以及另一设备修改后的状态。主机持久设置必须在桌面和手机相互刷新后相同；手机本地显示/缓存偏好不能伪装为主机设置。

最先验收 B01–B06、C03、H01/H03/H04：这些影响群权限、状态可信度、用量正确性及敏感配置。主题、头像和布局要用同一组Bot/群/模型数据进行明暗两组截图对照；字体与点击区域采用原生可读、可操作尺寸，桌面hover菜单在手机应有点击或长按等价入口。

以下记录本轮当前源码复核结果。上方表格保留初始差距作为基线；以本表判断当前完成范围。源码存在、单元测试通过、真实协议通过与原生真机验收是不同证据，不能把其中一项替代其余项。

| 更新批次 | 已复核完成项 | 仍有边界/待验证 |
| --- | --- | --- |
| 初始源码审查 | 建立B/V/C/S/H逐项基线与公开API分类 | 后续补齐实现与截图/原生验收进行中；本表不宣称全量一致。 |
| Host设置面板初稿 | [HostSettingsPanel](../apps/mobile/src/host-settings/HostSettingsPanel.tsx)接入Connector状态/连接/重试/断开、Secrets元信息/请求/写入/权限/删除、Feedback预览/复制/手动打开issue/错误日志、Harness公开schema读取与逐字段修改；原生配置修改带expectedRevision，secret输入不进入缓存、后台清空，失败不显示provider原始错误。 | Harness复杂条件表单、集合项增删、自定义插件专属UI仍指向对应宿主页面，不能标为上游API缺失；设置schema的普通字段不等同于完整Models/Plugins页面。原生屏幕截图和真机输入行为待验收。 |


## 本轮实现后的逐项复核

截至本次工作区，主机插件 363 项、SDK 23 项、App 30 项单元测试通过；App 类型检查通过。真实 DSH mock 协议回归 24/24 通过（`MOBILE_PARITY=1 node dev/mobile-smoke.mjs parity-baseline 3101 8790`），其中 HTTP 环境下的敏感设置检查是确认写入被拒绝，不是已验证真实 HTTPS 配置写入。手机浏览器界面回归37/37，另有8/8项受控语音生命周期检查、桌面共享审批DOM8/8通过；新 APK 已完成签名/权限/哈希核验，具体结果以[验证记录](mobile-validation.zh.md)为准；以下不声称已完成真机验收。

| 对应基线 | 当前实现及证据 | 尚存范围 / 验收注意 |
| --- | --- | --- |
| B01–B03、B05 群规则 | [TeamScreen](../apps/mobile/src/screens/TeamScreen.tsx)按至少两成员校验；空名自动命名，名称60/公告2000；可取消管理员，保留 Admin leads / Everyone 语义。 | 管理员及成员最终有效性仍由主机判断；另一设备删 Bot 后要显示真实失败，不自行更换管理员。 |
| B04、B05、S01 主 Bot 与 Bot 表单 | Main Bot 与 Chief 名称分离；支持多主 Bot、首位调整/替换；姓名40、角色24、模型按provider分组；指令失焦保存、duplicate、pin/hide和归档删除均调用真实主机动作。[TeamScreen](../apps/mobile/src/screens/TeamScreen.tsx) | 最后一位主 Bot的限制保留；头像、记忆和角色是同一 Bot，不重新创建会话。 |
| B07、H06 Classic Agent | [App](../apps/mobile/src/App.tsx)、[AgentDetails](../apps/mobile/src/components/AgentDetails.tsx)新增普通Agent身份、会话创建/重命名/归档/移除、Bot/群/Agent导航筛选。 | 普通Agent会话与Bot长期逻辑对话分开；新建Bot不会偷偷创建现有Bot的新part。 |
| B08 归档语义 | Bot/群删除确认说明历史归档；普通Agent归档同样使用主机动作。 | 手机缓存、旧配对的归档提交仍是本地数据；归档不是安全擦除，见部署指南。 |
| V01–V02 主题与偏好 | [theme](../apps/mobile/src/theme.ts)使用原版 DeepSeek/Mono/Paper/Moonlight 明暗色值、共享accent；主题/强调色/motion经`set-prefs`写回主机。 | 手机外观随系统明暗；主机主题偏好与操作系统明暗模式不是同一个字段。 |
| V03 角色头像 | [BotAvatar](../apps/mobile/src/components/BotAvatar.tsx)、[AvatarEditor](../apps/mobile/src/components/AvatarEditor.tsx)使用本项目原版20个角色SVG、12种命名色、确定性默认外观，支持照片、颜色、随机和重置。 | 原版复杂CSS眨眼/抚摸没有逐帧移植；原生轻浮动遵循 Quiet/Normal/Lively 和系统减少动态效果。新增SVG与图片转换依赖需重新原生构建。 |
| V04–V05 导航详情 | [App](../apps/mobile/src/App.tsx)全屏主页包含主 Bot 大入口、头像/搜索/新建与会话列表；头像打开分组设置，详情连接记忆、任务、用量、群成员公告及主机设置。最新界面取消抽屉，消息操作长按触发。 | 手机单页/Sheet替代桌面浮窗，触控入口不依赖hover；不宣称像素等同。 |
| V06、H07 语言 | [i18n](../apps/mobile/src/i18n.ts)复用原版中文语义，读取公开`locale.preference`；本机有跟随主机/系统/en/zh选择。[Host词表](../apps/mobile/src/host-settings/locale.zh.json)覆盖主要设置静态控件。 | 用户名称、插件schema描述和服务端错误不做字符串猜测翻译；本轮补齐聊天、文件、导出、语音、记忆、计划任务、历史与用量静态文案；少数动态状态仍回退英文，尚非全量逐句翻译。 |
| V07–V08 状态、表单 | 工作、连接、提问、审批分开呈现；修改保留加载/禁用/错误；敏感输入在提交、后台及卸载后不保留。[ApprovalCards](../apps/mobile/src/components/ApprovalCards.tsx)、[shared](../apps/mobile/src/host-settings/shared.tsx) | 每个表面仍需真机键盘、安全区、屏幕阅读和另一设备并发修改验收。不能把源码有disabled属性视作全部无障碍通过。 |
| C01 Markdown | [MarkdownText](../apps/mobile/src/components/MarkdownText.tsx)、[markdown](../apps/mobile/src/logic/markdown.ts)支持标题、列表、表格、引用、强调、删除线、代码复制与安全链接；不执行消息HTML。 | 任意插件注册的浏览器Markdown扩展不自动成为原生组件；外部Markdown图片为安全链接，真实上传图片独立鉴权预览。 |
| C02 引用/反应/导出 | [MessageBubble](../apps/mobile/src/components/MessageBubble.tsx)支持引用、6种本地反应、复制、单条Markdown下载、系统分享和TTS。 | 新增跨所有可读取分段的 Markdown/JSON 对话导出，分页去重并过滤传输元数据；取消、重复游标和大小超限均停止，不保存半成品。附件字节单独下载；本地反应不伪装多端同步。 |
| C03、H02 工具与思考 | [projection](../ds-bot/src/mobile/projection.js)保留typed工具运行/结果/错误与reasoning，并保持隐藏内部turn过滤；[MessageBubble](../apps/mobile/src/components/MessageBubble.tsx)可折叠查看有界input/result与思考。 | 已有终端、文件、差异、检索、网页、技能、任务专用卡片及通用回退、复制、原始详情和耗时；超长结果明确为excerpt，任意插件自定义 DOM 控件仍需宿主界面。 |
| C04–C05 来源与群进度 | 投影保留群作者、用户及工具记录；聊天展示日期、运行/中断和Bot导航；[GroupProgress](../apps/mobile/src/components/GroupProgress.tsx)在运行且前台在线时读取`room-progress`，展示当前发言者、已回复、失败及已有查找状态。[ChatScreen](../apps/mobile/src/screens/ChatScreen.tsx) | 接口未返回的waiting槽位不伪造，未响应者只列姓名；**仍未完整呈现schedule/handoff等typed来源、耗时与原版全部活动组件**，保持原版隐藏内部轮次边界。 |
| C06 模型 | 创建/编辑/聊天选择器按provider分组，刷新目录并显示default及已应用模型语义。[TeamScreen](../apps/mobile/src/screens/TeamScreen.tsx)、[ChatScreen](../apps/mobile/src/screens/ChatScreen.tsx) | 选择不可用模型必须呈现主机失败；模型供应商配置为下述Harness字段编辑器支持范围。 |
| C07 提问 | [QuestionCard](../apps/mobile/src/components/QuestionCard.tsx)保留单/多选、自定义回答、跳过与失效状态；按question ID提交。 | 与工具授权、密钥授权是三类不同请求；另一端已回答后不得转成普通prompt重放。 |
| C08 输入器 | [MediaComposer](../apps/mobile/src/components/MediaComposer.tsx)增加相机/相册/文件、HEIC转JPEG；聊天引用与@成员、队列状态/指定删除保持主机提交去重。 | 普通文件使用Harness上传服务，能上传不代表模型能解析该格式；离线草稿不会自动执行。 |
| C09 语音 | 支持整段录音→ASR→检查后发送；新增独立语音轮替模式，显式开始后停顿转写、自动发送、朗读本轮已接受请求的回复并继续聆听。暂停/后台/断线/中断均停录音。 | 受控浏览器8项生命周期检查通过，真实SenseVoice整段识别另行通过；尚无流式ASR或全双工，未完成真机麦克风/蓝牙/后台验收。 |
| C10 附件 | 上传图片自动鉴权加载缩略图，可打开预览并分享/下载；普通文件显示name/type/size，可鉴权下载并预览常见纯文本。[MessageBubble](../apps/mobile/src/components/MessageBubble.tsx) | 文件必须由所属会话的可见消息引用，通过公开readFileStream完整校验；限20 MiB，文本预览前64 KiB，HTML/脚本仅作为文本。主机路径不作为手机URI。 |
| C11–C12 历史 | [HistoryPanels](../apps/mobile/src/features/HistoryPanels.tsx)按真实parts列历史，scope限定跨part搜索、高亮和上下文跳转，绑定part游标读取。 | 每轮搜索最多扫10页，需按cursor继续；“暂未找到”不宣称已搜索全历史。手机缓存仍仅最近1000条，不能作为完整历史备份。 |
| S02 记忆 | [MemoryPanel](../apps/mobile/src/features/MemoryPanel.tsx)提供摘要/条目、own/team/topics/quota、提问更新与change结果、删除、重新摘要、生成中轮询。 | 服务未启用、正在生成与空记忆分别展示；生成仍由主机模型执行并计入真实用量。 |
| B06、S03 用量 | [usage-model](../apps/mobile/src/features/usage-model.ts)、[UsagePanel](../apps/mobile/src/features/UsagePanel.tsx)修正cache write计入口径，支持全部时间范围/custom、Bot/群与模型筛选、前期对比、堆叠图详情/图例、排行和53周活动图。 | 图表是原生触控适配；未推断货币费用，不把token计数当账单。数据/日期口径由7项feature测试覆盖。 |
| S04 定时任务 | [SchedulesPanel](../apps/mobile/src/features/SchedulesPanel.tsx)支持全团队或单Bot筛选，at/daily/weekly/every、时区/星期/间隔与真实创建删除、能力/离线/只读状态。 | 主机必须持续运行；手机无本地后台任务引擎，也没有推送承诺。 |
| S05、H04 Secrets | [SecretsPanel](../apps/mobile/src/host-settings/SecretsPanel.tsx)提供新建/替换/用途/范围/删除与聊天请求卡；响应只含metadata；提交/后台清空，错误固定文案。 | HTTPS写入；loopback测试仅允许特定合成值。无读回密钥、缓存密钥、离线自动授权或后台重发。 |
| S06 Connectors | [ConnectorsPanel](../apps/mobile/src/host-settings/ConnectorsPanel.tsx)真实连接中/账号/错误状态、连接、重试、确认断开；显式打开GitHub创建令牌。 | Connector能力由主机决定；无手机仿造已连接状态。敏感输入与Secrets相同边界。 |
| S07 Feedback | [FeedbackPanel](../apps/mobile/src/host-settings/FeedbackPanel.tsx)预览主机脱敏诊断、近期错误、复制、导出/清除日志和主动打开issue草稿。 | 不自动外发、不把诊断塞入issue URL；分享前由用户检查。没有客户端持久错误采集队列，当前上传clientErrors为空。 |
| H01 工具审批 | [approvals](../ds-bot/src/mobile/approvals.js)实现共享broker与稳定请求ID；桌面/手机共享单次决定，ask/never、无answerer拒绝、取消与销毁保留；8项真实Cordis服务测试及24步协议中的审批用例通过。 | 移动只提供Allow once/Reject，不新增绕过主机策略的永久授权；原生前后台恢复仍需真机验收。 |
| H03 Harness设置/凭据 | [HarnessPanel](../apps/mobile/src/host-settings/HarnessPanel.tsx)消费公开Schemastery envelope与revision，逐字段mutate；[CredentialsPanel](../apps/mobile/src/host-settings/CredentialsPanel.tsx)仅列既有apiKeyEnv引用并set/unset。 | **复杂条件表单、集合项增删、自定义插件控件尚未移植**；能编辑既有集合值。是移动UI范围，不是公开API缺失；不replace被脱敏的整份配置。 |
| S08、H08 Plugins与更新 | 已支持包检查、固定版本安装、阶段与结果查询、取消、确认卸载；插件启停与专用 DS Bot 更新保留。 | 构建脚本单独批准；保护 DS Bot/受保护包；真实第三方安装仍需部署验收。 |
| H08 Skills | 已支持 Bot/Agent 作用域目录、正文预览、草稿 `/技能名` 调用及自有库编辑/删除。 | 不改写项目/用户/插件文件；模型专用技能不伪造用户调用；并发保存按 revision 校验。 |
| H05 Desktop Browser | 已支持桌面 opt-in 后的标签、导航、读取、滚动、确认点击与输入；固定指令及快照校验。 | 已联调受控 Chromium 窗口和真实手机界面；原生 Electron/Windows/macOS 实机尚未验收；不共享 Cookie。 |

本轮增加了专用工具卡片和移动通知中心，详见[六项功能说明](mobile-features.zh.md)。剩余边界包括任意插件自定义 DOM 界面、复杂条件设置编辑器、少数动态文案及原生设备验收。后台推送实现可配置，但当前测试包未配置平台凭据，不宣称实际投递。
