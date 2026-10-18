import { Connector, PluginBundle, PluginEntry, SkillItem, SkillDetail } from '../model/Models';
import { actionLabel, isBusy, stateLabel, tokenProblem } from '../logic/Connectors';
import {
  bundleStatus, canOpenSkill, canToggleBundle, canTogglePlugin, describeInvocation, describeSkillBadge,
  groupSkills, pluginLabel, pluginStatus, readOnlyNotice, SkillGroup
} from '../logic/Capabilities2';
import { SecondaryPageTheme } from './SecondaryPages';

/**
 * 工具与技能（P2-8）。
 *
 * 三个分区：技能 / 插件 / 插件包。
 * - 技能：列表 + 点开看全文（宿主只允许 `userInvocable` 的技能）；
 * - 插件与插件包：开关（宿主只读或标记"手机连接必需"时禁用）。
 *
 * 设计取舍：
 * - **不做安装/卸载**（`plugins-install` / `plugins-remove` 是异步长任务，
 *   需要 inspect → 批准构建 → 轮询 operation，属于命令行更合适的场景）；
 * - 技能详情用全屏覆盖而不是弹层，长文本（最多 128KB）需要整屏滚动。
 */
@Component
export struct ToolsSkillsPanel {
  @Prop theme: SecondaryPageTheme = {
    pageBg: '#F5F7FA', rowBg: '#FFFFFF', chipBg: '#FFFFFF', chipLine: '#E3E8F0',
    ink: '#172033', muted: '#657086', line: '#E3E8F0', brand: '#3F5EF5', brandSoft: '#EEF2FF', danger: '#C93F49', dangerBg: '#FFF0F1'
  };
  @Prop skills: SkillItem[] = [];
  @Prop skillsAvailable: boolean = true;
  @Prop plugins: PluginEntry[] = [];
  /** 连接器（P3 工具与技能补全） */
  @Prop connectors: Connector[] = [];
  /** 正在输入 token 的连接器 id（空串表示没有展开） */
  @Prop tokenFor: string = '';
  @Prop tokenDraft: string = '';
  @Prop connectorBusy: boolean = false;
  @Prop bundles: PluginBundle[] = [];
  @Prop writable: boolean = true;
  @Prop loading: boolean = false;
  @Prop error: string = '';
  /** 打开的技能详情（null 表示在列表） */
  @Prop detail: SkillDetail | null = null;
  @Prop detailLoading: boolean = false;
  @Prop busy: boolean = false;

  onClose: () => void = (): void => {};
  onRefresh: () => void = (): void => {};
  onOpenSkill: (name: string) => void = (): void => {};
  onCloseDetail: () => void = (): void => {};
  onTogglePlugin: (entryId: string, enabled: boolean) => void = (): void => {};
  onToggleBundle: (name: string, enabled: boolean) => void = (): void => {};
  /** 打开能力库（P2-7 页面） */
  onOpenCapabilities: () => void = (): void => {};
  /** 点连接器主按钮：连接 / 重试 / 断开 */
  onConnectorAction: (connector: Connector) => void = (): void => {};
  /** token 输入变化 */
  onTokenChange: (value: string) => void = (): void => {};
  /** 提交 token */
  onSubmitToken: (connectorId: string) => void = (): void => {};
  /** 取消 token 输入 */
  onCancelToken: () => void = (): void => {};

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 14 }) {
          if (this.detail !== null) {
            this.detailView();
          } else {
            this.listView();
          }
          if (this.error.length > 0) {
            Text(this.error).fontSize(13).fontColor('#C93F49').width('100%')
              .padding(14).backgroundColor(this.theme.rowBg).borderRadius(12);
          }
        }.width('100%').padding({ left: 18, right: 18, top: 4, bottom: 28 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }.width('100%').height('100%').backgroundColor(this.theme.pageBg);
  }

  @Builder
  private header() {
    Row({ space: 12 }) {
      Button(this.detail === null ? '‹' : '←')
        .width(40).height(40).borderRadius(20).fontSize(this.detail === null ? 24 : 18)
        .backgroundColor(this.theme.rowBg).fontColor(this.theme.ink)
        .onClick(() => {
          if (this.detail === null) this.onClose();
          else this.onCloseDetail();
        });
      Text(this.detail === null ? '工具与技能' : (this.detail.name ?? '技能'))
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.theme.ink).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      if (this.detail === null) {
        Button('刷新').height(34).borderRadius(17).fontSize(13)
          .backgroundColor(this.theme.rowBg).fontColor(this.theme.ink)
          .enabled(!this.loading)
          .onClick(() => this.onRefresh());
      }
    }
    .width('100%').height(64).padding({ left: 16, right: 16 });
  }

  @Builder
  private listView() {
    Column({ space: 14 }) {
      // 能力库入口：之前只在旧的 ToolsPage 里，页面改版后丢了
      Column() {
        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Text('能力库').fontSize(15).fontColor(this.theme.ink).width('100%');
            Text('给 Bot 挂载可复用的能力（技能 / MCP / 能力包）')
              .fontSize(11).fontColor(this.theme.muted).width('100%');
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
          Text('›').fontSize(18).fontColor(this.theme.muted);
        }
        .width('100%').padding(16)
        .backgroundColor(this.theme.rowBg).borderRadius(14)
        .onClick(() => this.onOpenCapabilities());
      }.width('100%');

      this.connectorsSection();
      this.skillsSection();
      this.pluginsSection();
      this.bundlesSection();
    }.width('100%');
  }

  /**
   * 连接器分区（工具与技能补全）。
   *
   * 宿主目前只有 GitHub：`connector-connect` 需要一个 token，
   * `disconnect` 删除主机端保存的密钥，"重试"用于 error 状态。
   * token 输入用**行内展开**而不是弹窗——同一节点多个 `bindSheet` 会互相覆盖。
   */
  @Builder
  private connectorsSection() {
    Column({ space: 10 }) {
      Text(`连接器（${this.connectors.length}）`).fontSize(15)
        .fontColor(this.theme.muted).width('100%');
      if (this.connectors.length === 0) {
        Text('主机没有配置连接器。').fontSize(14).fontColor(this.theme.muted)
          .width('100%').padding(18).backgroundColor(this.theme.rowBg).borderRadius(14);
      } else {
        ForEach(this.connectors, (connector: Connector) => {
          Column({ space: 10 }) {
            Row({ space: 10 }) {
              Column({ space: 3 }) {
                Text(connector.name).fontSize(15).fontColor(this.theme.ink).width('100%');
                Text(stateLabel(connector)).fontSize(11)
                  .fontColor(this.connectorStateColor(connector)).width('100%');
                if (connector.error !== undefined && connector.error.length > 0) {
                  Text(connector.error).fontSize(11).fontColor(this.theme.danger)
                    .width('100%').maxLines(2);
                }
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Button(actionLabel(connector))
                .height(32).borderRadius(16).fontSize(12)
                .backgroundColor(connector.state === 'ready' ? this.theme.chipBg : this.theme.brand)
                .fontColor(connector.state === 'ready' ? this.theme.danger : '#FFFFFF')
                .enabled(!this.connectorBusy && !isBusy(connector))
                .onClick(() => this.onConnectorAction(connector));
            }.width('100%');

            // token 输入（只有"连接"这个动作需要）
            if (this.tokenFor === connector.id) {
              Column({ space: 8 }) {
                TextInput({ placeholder: `粘贴 ${connector.name} 访问令牌`, text: this.tokenDraft })
                  .height(42).width('100%').backgroundColor(this.theme.pageBg).borderRadius(10)
                  .fontColor(this.theme.ink).fontSize(13)
                  .type(InputType.Password)
                  .onChange((value: string) => this.onTokenChange(value));
                if (tokenProblem(this.tokenDraft).length > 0) {
                  Text(tokenProblem(this.tokenDraft)).fontSize(11)
                    .fontColor(this.theme.muted).width('100%');
                }
                Row({ space: 8 }) {
                  Button('取消').layoutWeight(1).height(36).borderRadius(10).fontSize(13)
                    .backgroundColor(this.theme.chipBg).fontColor(this.theme.ink)
                    .onClick(() => this.onCancelToken());
                  Button('连接').layoutWeight(1).height(36).borderRadius(10).fontSize(13)
                    .backgroundColor(this.theme.brand).fontColor('#FFFFFF')
                    .enabled(tokenProblem(this.tokenDraft).length === 0 && !this.connectorBusy)
                    .onClick(() => this.onSubmitToken(connector.id));
                }.width('100%');
              }.width('100%').alignItems(HorizontalAlign.Start);
            }
          }
          .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14)
          .margin({ bottom: 10 });
        }, (connector: Connector) => `${connector.id}#${connector.state}#${connector.account ?? ''}#${this.tokenFor === connector.id}`);
      }
    }.width('100%');
  }

  /**
   * 连接器状态色。
   *
   * 直接在这里按状态取主题令牌：ArkTS 不支持把本地对象结构传给
   * `logic` 里的接口参数（`arkts-no-structural-typing`），
   * 所以不再把颜色对象传进逻辑层。
   */
  private connectorStateColor(connector: Connector): string {
    if (connector.state === 'ready') return this.theme.brand;
    if (connector.state === 'error') return this.theme.danger;
    if (connector.state === 'connecting') return this.theme.brand;
    return this.theme.muted;
  }

  /** 技能分组列表。 */
  @Builder
  private skillsSection() {
    Column({ space: 10 }) {
      Text(`技能（${this.skills.length}）`).fontSize(15).fontColor(this.theme.muted).width('100%');
      if (this.skills.length === 0) {
        Text(this.skillsAvailable ? '没有可用的技能。' : '主机未启用技能服务。')
          .fontSize(14).fontColor(this.theme.muted).width('100%')
          .padding(18).backgroundColor(this.theme.rowBg).borderRadius(14);
      } else {
        ForEach(groupSkills(this.skills), (group: SkillGroup) => {
          Column({ space: 8 }) {
            Text(group.source).fontSize(12).fontColor(this.theme.muted).width('100%');
            Column() {
              ForEach(group.skills, (skill: SkillItem) => {
                Column({ space: 3 }) {
                  Row({ space: 8 }) {
                    Text(skill.name).fontSize(15).fontColor(this.theme.ink).layoutWeight(1)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                    if (describeSkillBadge(skill).length > 0) {
                      Text(describeSkillBadge(skill)).fontSize(11).fontColor(this.theme.muted);
                    }
                  }.width('100%');
                  if (skill.description !== undefined && skill.description.length > 0) {
                    Text(skill.description).fontSize(12).fontColor(this.theme.muted).width('100%')
                      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
                  }
                  Text(describeInvocation(skill)).fontSize(11).fontColor(this.theme.muted).width('100%');
                }
                .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .onClick(() => {
                  if (canOpenSkill(skill)) this.onOpenSkill(skill.name);
                });
                Divider().color(this.theme.line).margin({ left: 16 });
              }, (skill: SkillItem) => `${skill.name}#${canOpenSkill(skill)}`);
            }.width('100%').backgroundColor(this.theme.rowBg).borderRadius(14);
          }.width('100%');
        }, (group: SkillGroup) => `${group.source}#${group.skills.length}`);
      }
    }.width('100%');
  }

  /** 插件开关列表。 */
  @Builder
  private pluginsSection() {
    Column({ space: 10 }) {
      Text(`插件（${this.plugins.length}）`).fontSize(15).fontColor(this.theme.muted).width('100%');
      if (readOnlyNotice(this.writable).length > 0) {
        Text(readOnlyNotice(this.writable)).fontSize(12).fontColor('#B86A16').width('100%');
      }
      if (this.plugins.length === 0) {
        Text('没有插件信息。').fontSize(14).fontColor(this.theme.muted).width('100%')
          .padding(18).backgroundColor(this.theme.rowBg).borderRadius(14);
      } else {
        Column() {
          ForEach(this.plugins, (entry: PluginEntry) => {
            Row({ space: 10 }) {
              Column({ space: 3 }) {
                Text(pluginLabel(entry)).fontSize(15).fontColor(this.theme.ink).width('100%')
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                Text(pluginStatus(entry)).fontSize(11).fontColor(this.theme.muted).width('100%');
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Toggle({ type: ToggleType.Switch, isOn: entry.enabled === true })
                .selectedColor(this.theme.brand)
                .enabled(canTogglePlugin(entry, this.writable) && !this.busy)
                .onChange((isOn: boolean) => this.onTogglePlugin(entry.entryId, isOn));
            }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 });
            Divider().color(this.theme.line).margin({ left: 16 });
          }, (entry: PluginEntry) => `${entry.entryId}#${entry.enabled}#${entry.readOnlyReason ?? ''}`);
        }.width('100%').backgroundColor(this.theme.rowBg).borderRadius(14);
      }
    }.width('100%');
  }

  /** 插件包开关列表。 */
  @Builder
  private bundlesSection() {
    Column({ space: 10 }) {
      Text(`插件包（${this.bundles.length}）`).fontSize(15).fontColor(this.theme.muted).width('100%');
      if (this.bundles.length === 0) {
        Text('没有插件包信息。').fontSize(14).fontColor(this.theme.muted).width('100%')
          .padding(18).backgroundColor(this.theme.rowBg).borderRadius(14);
      } else {
        Column() {
          ForEach(this.bundles, (bundle: PluginBundle) => {
            Row({ space: 10 }) {
              Column({ space: 3 }) {
                Text(bundle.name).fontSize(15).fontColor(this.theme.ink).width('100%')
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                Text(`${bundleStatus(bundle)}${bundle.version !== undefined && bundle.version.length > 0 ? ` · v${bundle.version}` : ''}`)
                  .fontSize(11).fontColor(this.theme.muted).width('100%');
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Toggle({ type: ToggleType.Switch, isOn: bundle.enabled === true })
                .selectedColor(this.theme.brand)
                .enabled(canToggleBundle(bundle, this.writable) && !this.busy)
                .onChange((isOn: boolean) => this.onToggleBundle(bundle.name, isOn));
            }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 });
            Divider().color(this.theme.line).margin({ left: 16 });
          }, (bundle: PluginBundle) => `${bundle.name}#${bundle.enabled}#${bundle.readOnlyReason ?? ''}`);
        }.width('100%').backgroundColor(this.theme.rowBg).borderRadius(14);
      }
    }.width('100%');
  }

  /** 技能全文。 */
  @Builder
  private detailView() {
    Column({ space: 10 }) {
      if (this.detailLoading) {
        Row({ space: 10 }) {
          LoadingProgress().width(20).height(20).color(this.theme.brand);
          Text('读取中…').fontSize(13).fontColor(this.theme.muted);
        }.width('100%').padding(16);
      } else if (this.detail !== null) {
        if (this.detail.description !== undefined && this.detail.description.length > 0) {
          Text(this.detail.description).fontSize(13).fontColor(this.theme.muted).width('100%');
        }
        if (this.detail.truncated === true) {
          Text('内容过长，仅显示前一部分。').fontSize(12).fontColor('#B86A16').width('100%');
        }
        Text(this.detail.content ?? '').fontSize(13).fontColor(this.theme.ink).width('100%')
          .wordBreak(WordBreak.BREAK_WORD);
      }
    }
    .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14);
  }
}
