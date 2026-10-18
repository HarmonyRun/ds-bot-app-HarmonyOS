import { Bot } from '../model/Models';
import { EffortOption } from '../service/Wire';
import { BotForm, describeBotSummary, isMainBot, validateBotForm } from '../logic/Bots';
import { ModelOption } from '../model/Models';
import { SecondaryPageTheme } from './SecondaryPages';

/**
 * Bot 管理（P2-5）。
 *
 * 结构：Bot 列表（含主 Bot 标记）→ 选中进入编辑（名字 / 角色 / 指令 / 模型 / 思考档位）
 * → 保存、设为主 Bot、复制、删除。
 *
 * 设计取舍：
 * - **头像与工作目录本轮不做**：都需要系统选择器（相册 / 文件），
 *   在手机上做完整链路成本高且不是核心；协议字段保留在服务层，后续接。
 * - 思考档位随所选模型变化（宿主 `efforts {ref}` 按模型返回），
 *   所以切换模型时由父组件重新拉一次档位列表。
 */
@Component
export struct BotManagePanel {
  @Prop theme: SecondaryPageTheme = {
    pageBg: '#F5F7FA', rowBg: '#FFFFFF', chipBg: '#FFFFFF', chipLine: '#E3E8F0',
    ink: '#172033', muted: '#657086', line: '#E3E8F0', brand: '#3F5EF5', brandSoft: '#EEF2FF', danger: '#C93F49', dangerBg: '#FFF0F1'
  };
  @Prop bots: Bot[] = [];
  @Prop mainBotIds: string[] = [];
  @Prop models: ModelOption[] = [];
  @Prop efforts: EffortOption[] = [];
  /** 档位 id → 显示名（列表用；编辑区用当前模型的 `efforts`） */
  @Prop effortNames: Record<string, string> = {};
  @Prop effortLoading: boolean = false;
  /** 正在编辑的 Bot id（空串表示列表态） */
  @Prop editingId: string = '';
  @Prop form: BotForm = { id: '', name: '', role: '', instructions: '', model: '', effort: '', avatarImage: '' };
  @Prop busy: boolean = false;
  @Prop error: string = '';
  @Prop notice: string = '';

  onClose: () => void = (): void => {};
  onRefresh: () => void = (): void => {};
  onOpenBot: (botId: string) => void = (): void => {};
  onBackToList: () => void = (): void => {};
  onFormChange: (form: BotForm) => void = (): void => {};
  onSave: () => void = (): void => {};
  onDuplicate: (botId: string) => void = (): void => {};
  onDelete: (bot: Bot) => void = (): void => {};
  onToggleMain: (botId: string, main: boolean) => void = (): void => {};
  /** 从相册选择新头像（父组件读字节并转 data URL） */
  onPickAvatar: () => void = (): void => {};
  /** 清除头像（回到矢量头像） */
  onClearAvatar: () => void = (): void => {};

  private validate(): BotFormValidation {
    const others: Bot[] = [];
    for (let i = 0; i < this.bots.length; i++) {
      if (this.bots[i].id !== this.form.id) others.push(this.bots[i]);
    }
    return validateBotForm(this.form, others);
  }

  private editingBot(): Bot | undefined {
    for (let i = 0; i < this.bots.length; i++) {
      if (this.bots[i].id === this.editingId) return this.bots[i];
    }
    return undefined;
  }

  private modelName(ref: string): string {
    for (let i = 0; i < this.models.length; i++) {
      if (this.models[i].ref === ref) return this.models[i].name;
    }
    return ref;
  }

  /** 档位显示名：优先用名字表（列表态），回退到当前候选（编辑态），最后回退原始 id。 */
  private effortName(id: string): string {
    for (let i = 0; i < this.efforts.length; i++) {
      if (this.efforts[i].id === id) return this.efforts[i].name;
    }
    const keys = Object.keys(this.effortNames);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i] === id) return this.effortNames[keys[i]];
    }
    return id;
  }

  build() {
    Column() {
      this.header();
      if (this.editingId.length === 0) {
        Scroll() {
          Column({ space: 12 }) {
            this.listView();
            this.messageBar();
          }.width('100%').padding({ left: 18, right: 18, top: 4, bottom: 28 });
        }
        .layoutWeight(1).width('100%').scrollBar(BarState.Off);
      } else {
        // 编辑态：内容可滚动，**保存条固定在底部**（表单长，翻到底才能保存很反直觉）
        Scroll() {
          Column({ space: 14 }) {
            this.heroCard();
            this.identityCard();
            this.personaCard();
            this.modelCard();
            this.actionsCard();
            this.dangerCard();
          // 底部留出保存条的高度，否则最后一张卡片会被固定条盖住
          }.width('100%').padding({ left: 18, right: 18, top: 4, bottom: 110 });
        }
        .layoutWeight(1).width('100%').scrollBar(BarState.Off);
        this.saveBar();
      }
    }
    .width('100%').height('100%').backgroundColor(this.theme.pageBg);
  }

  @Builder
  private header() {
    Row({ space: 12 }) {
      Button(this.editingId.length === 0 ? '‹' : '←')
        .width(40).height(40).borderRadius(20).fontSize(this.editingId.length === 0 ? 24 : 18)
        .backgroundColor(this.theme.rowBg).fontColor(this.theme.ink)
        .onClick(() => {
          if (this.editingId.length === 0) this.onClose();
          else this.onBackToList();
        });
      Column({ space: 1 }) {
        Text(this.editingId.length === 0 ? 'Bot 管理' : '编辑 Bot')
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.theme.ink);
        if (this.editingId.length > 0) {
          Text(this.form.name.length > 0 ? this.form.name : '未命名')
            .fontSize(12).fontColor(this.theme.muted).maxLines(1);
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Button('刷新').height(34).borderRadius(17).fontSize(13)
        .backgroundColor(this.theme.rowBg).fontColor(this.theme.ink)
        .enabled(!this.busy)
        .onClick(() => this.onRefresh());
    }
    .width('100%').height(64).padding({ left: 16, right: 16 });
  }

  /** Bot 列表。 */
  @Builder
  private listView() {
    Column({ space: 10 }) {
      Text(`共 ${this.bots.length} 个 Bot`).fontSize(13).fontColor(this.theme.muted).width('100%');
      ForEach(this.bots, (bot: Bot) => {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text(bot.name).fontSize(16).fontColor(this.theme.ink).layoutWeight(1)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
            if (isMainBot(bot.id, this.mainBotIds)) {
              Text('主 Bot').fontSize(11).fontColor(this.theme.brand);
            }
            Text('编辑').fontSize(13).fontColor(this.theme.brand);
          }.width('100%');
          Text(describeBotSummary(bot, this.modelName(bot.model ?? ''), this.effortName(bot.effort ?? '')))
            .fontSize(12).fontColor(this.theme.muted).width('100%')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14)
        .onClick(() => this.onOpenBot(bot.id));
      }, (bot: Bot) => `${bot.id}#${bot.name}#${bot.model ?? ''}#${bot.effort ?? ''}#${isMainBot(bot.id, this.mainBotIds)}`);
    }.width('100%');
  }

  // ---------------------------------------------------------------- 编辑态分区

  /** 顶部主视觉：大头像 + 名字 + 角色 + 主 Bot 徽标。 */
  @Builder
  private heroCard() {
    Row({ space: 14 }) {
      // 头像（点一下就能换，符合"看到什么点什么的"直觉）
      Stack({ alignContent: Alignment.BottomEnd }) {
        if (this.form.avatarImage.length > 0) {
          Image(this.form.avatarImage).width(72).height(72).borderRadius(22)
            .objectFit(ImageFit.Cover);
        } else {
          Stack() {
            Circle({ width: 72, height: 72 }).fill(this.theme.brandSoft);
            Text(this.form.name.length > 0 ? this.form.name.substring(0, 1) : '默')
              .fontSize(24).fontWeight(FontWeight.Medium).fontColor(this.theme.brand);
          }.width(72).height(72);
        }
        Row() {
          Text('换').fontSize(11).fontColor('#FFFFFF');
        }
        .width(24).height(24).borderRadius(12)
        .backgroundColor(this.theme.brand)
        .justifyContent(FlexAlign.Center)
        .margin({ right: 2, bottom: 2 });
      }
      .width(72).height(72)
      .onClick(() => this.onPickAvatar());

      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(this.form.name.length > 0 ? this.form.name : '未命名 Bot')
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.theme.ink)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          if (isMainBot(this.editingId, this.mainBotIds)) {
            Text('主 Bot').fontSize(10).fontColor('#FFFFFF')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(this.theme.brand).borderRadius(8);
          }
        }.width('100%');
        Text(this.form.role.length > 0 ? this.form.role : '还没设置角色')
          .fontSize(13).fontColor(this.theme.muted).width('100%')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Row({ space: 8 }) {
          Text('更换头像').fontSize(12).fontColor(this.theme.brand)
            .onClick(() => this.onPickAvatar());
          if (this.form.avatarImage.length > 0) {
            Text('清除').fontSize(12).fontColor(this.theme.muted)
              .onClick(() => this.onClearAvatar());
          }
        }.width('100%');
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%').padding(18)
    .backgroundColor(this.theme.rowBg).borderRadius(18);
  }

  /** 基本资料：名字 + 角色。 */
  @Builder
  private identityCard() {
    Column({ space: 14 }) {
      this.sectionTitle('基本资料', '显示在会话列表与团队页');
      Column({ space: 6 }) {
        Text('名字').fontSize(12).fontColor(this.theme.muted).width('100%');
        TextInput({ text: this.form.name })
          .height(46).width('100%')
          .backgroundColor(this.theme.pageBg).borderRadius(12)
          .fontColor(this.theme.ink).fontSize(15).padding({ left: 14, right: 14 })
          .onChange((value: string) => this.patch({ name: value }));
        Text('最多 40 字，不能与其它 Bot 重名').fontSize(11)
          .fontColor(this.theme.muted).width('100%');
      }.width('100%');

      Column({ space: 6 }) {
        Text('角色').fontSize(12).fontColor(this.theme.muted).width('100%');
        TextInput({ text: this.form.role })
          .height(46).width('100%')
          .backgroundColor(this.theme.pageBg).borderRadius(12)
          .fontColor(this.theme.ink).fontSize(15).padding({ left: 14, right: 14 })
          .onChange((value: string) => this.patch({ role: value }));
        Text('一句话说明它负责什么，例如「团队总管」「搜索」').fontSize(11)
          .fontColor(this.theme.muted).width('100%');
      }.width('100%');
    }
    .width('100%').padding(18).backgroundColor(this.theme.rowBg).borderRadius(18);
  }

  /** 人设提示词。 */
  @Builder
  private personaCard() {
    Column({ space: 10 }) {
      this.sectionTitle('人设提示词', '决定它说话的方式、边界与习惯');
      TextArea({ text: this.form.instructions })
        .height(160).width('100%')
        .backgroundColor(this.theme.pageBg).borderRadius(12)
        .fontColor(this.theme.ink).fontSize(14)
        .padding(14)
        .onChange((value: string) => this.patch({ instructions: value }));
      Row() {
        Text('写得越具体，它的回答越贴近你要的风格').fontSize(11)
          .fontColor(this.theme.muted).layoutWeight(1);
        Text(`${this.form.instructions.length} 字`).fontSize(11).fontColor(this.theme.muted);
      }.width('100%');
    }
    .width('100%').padding(18).backgroundColor(this.theme.rowBg).borderRadius(18);
  }

  /** 模型与思考档位。 */
  @Builder
  private modelCard() {
    Column({ space: 12 }) {
      this.sectionTitle('模型与思考档位', '决定它用哪个大脑、想得多深');
      Text('模型').fontSize(12).fontColor(this.theme.muted).width('100%');
      // 用原生下拉而不是 chips：主机模型列表可能很长（二三十个），
      // chips 会把页面撑成好几屏，而且看不出"当前选的是哪个"
      Select(this.modelOptions())
        .selected(this.modelSelectedIndex())
        .value(this.modelOptions()[this.modelSelectedIndex()].value)
        .width('100%').height(46)
        .font({ size: 15 }).fontColor(this.theme.ink)
        .selectedOptionBgColor(this.theme.brandSoft)
        .selectedOptionFontColor(this.theme.brand)
        .backgroundColor(this.theme.pageBg)
        .borderRadius(12)
        .onSelect((index: number, _value: string) => {
          // 索引 0 是「跟随默认」，其余对应 models[index - 1]
          const ref = index === 0 ? '' : (this.models[index - 1]?.ref ?? '');
          this.patch({ model: ref, effort: '' });
        });
      Text(`${this.models.length} 个可选模型`).fontSize(11)
        .fontColor(this.theme.muted).width('100%');

      Text('思考档位').fontSize(12).fontColor(this.theme.muted).width('100%');
      if (this.effortLoading) {
        Row({ space: 8 }) {
          LoadingProgress().width(16).height(16).color(this.theme.brand);
          Text('读取档位…').fontSize(12).fontColor(this.theme.muted);
        }.width('100%');
      } else if (this.efforts.length === 0) {
        Text(this.form.model.length === 0
          ? '先选一个具体模型，才能设置思考档位'
          : '这个模型没有可调档位')
          .fontSize(12).fontColor(this.theme.muted).width('100%');
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          this.effortChip('', '不设置');
          ForEach(this.efforts, (effort: EffortOption) => {
            this.effortChip(effort.id, effort.name);
          }, (effort: EffortOption) => `e:${effort.id}:${this.form.effort === effort.id}`);
        }.width('100%');
      }
    }
    .width('100%').padding(18).backgroundColor(this.theme.rowBg).borderRadius(18);
  }

  /** 次要操作：设主 / 复制。 */
  @Builder
  private actionsCard() {
    Column({ space: 12 }) {
      this.sectionTitle('其它操作', '');
      Row({ space: 10 }) {
        Button(isMainBot(this.editingId, this.mainBotIds) ? '取消主 Bot' : '设为主 Bot')
          .layoutWeight(1).height(44).borderRadius(12).fontSize(14)
          .backgroundColor(this.theme.pageBg).fontColor(this.theme.ink)
          .enabled(!this.busy)
          .onClick(() => this.onToggleMain(this.editingId, !isMainBot(this.editingId, this.mainBotIds)));
        Button('复制一个')
          .layoutWeight(1).height(44).borderRadius(12).fontSize(14)
          .backgroundColor(this.theme.pageBg).fontColor(this.theme.ink)
          .enabled(!this.busy)
          .onClick(() => this.onDuplicate(this.editingId));
      }.width('100%');
    }
    .width('100%').padding(18).backgroundColor(this.theme.rowBg).borderRadius(18);
  }

  /** 危险操作：删除。 */
  @Builder
  private dangerCard() {
    Column({ space: 10 }) {
      this.sectionTitle('危险操作', '删除后它与你的聊天记录会一起移除，无法恢复');
      Button('删除这个 Bot')
        .width('100%').height(44).borderRadius(12).fontSize(15)
        .backgroundColor(this.theme.dangerBg).fontColor(this.theme.danger)
        .enabled(!this.busy)
        .onClick(() => this.onDeleteCurrent());
    }
    .width('100%').padding(18).backgroundColor(this.theme.rowBg).borderRadius(18);
  }

  /** 底部固定保存条：表单很长时也能随时保存。 */
  @Builder
  private saveBar() {
    Column({ space: 8 }) {
      if (!this.validate().ok) {
        Text(this.validate().error).fontSize(12).fontColor(this.theme.danger).width('100%');
      }
      Button(this.busy ? '保存中…' : '保存修改')
        .width('100%').height(48).borderRadius(14).fontSize(16)
        .backgroundColor(this.theme.brand).fontColor('#FFFFFF')
        .enabled(!this.busy && this.validate().ok)
        .onClick(() => this.onSave());
    }
    .width('100%').padding({ left: 18, right: 18, top: 10, bottom: 18 })
    .backgroundColor(this.theme.rowBg)
    .border({ width: { top: 1 }, color: this.theme.line });
  }

  /** 区块标题 + 说明（说明为空时不占位）。 */
  @Builder
  private sectionTitle(title: string, hint: string) {
    Column({ space: 3 }) {
      Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.ink).width('100%');
      if (hint.length > 0) {
        Text(hint).fontSize(11).fontColor(this.theme.muted).width('100%');
      }
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  /** 档位选项。 */
  @Builder
  private effortChip(id: string, label: string) {
    Button(label)
      .height(38).margin({ right: 8, bottom: 8 }).borderRadius(19).fontSize(13)
      .backgroundColor(this.form.effort === id ? this.theme.brand : this.theme.pageBg)
      .fontColor(this.form.effort === id ? '#FFFFFF' : this.theme.ink)
      .onClick(() => this.patch({ effort: id }));
  }

  /** 列表态的消息条（notice / error）。 */
  @Builder
  private messageBar() {
    if (this.notice.length > 0) {
      Text(this.notice).fontSize(13).fontColor(this.theme.brand).width('100%')
        .padding(14).backgroundColor(this.theme.brandSoft).borderRadius(12);
    }
    if (this.error.length > 0) {
      Text(this.error).fontSize(13).fontColor(this.theme.danger).width('100%')
        .padding(14).backgroundColor(this.theme.dangerBg).borderRadius(12);
    }
  }

  /** 删除当前编辑的 Bot（父组件负责确认与请求）。 */
  private onDeleteCurrent(): void {
    const bot = this.editingBot();
    if (bot !== undefined) this.onDelete(bot);
  }

  /** 模型下拉的候选：「跟随默认」+ 主机全部模型。 */
  private modelOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '跟随默认' }];
    for (let i = 0; i < this.models.length; i++) {
      options.push({ value: this.models[i].name });
    }
    return options;
  }

  /** 当前选中项下标（依赖 `form.model` 与 `models` 的顺序）。 */
  private modelSelectedIndex(): number {
    if (this.form.model.length === 0) return 0;
    for (let i = 0; i < this.models.length; i++) {
      if (this.models[i].ref === this.form.model) return i + 1;
    }
    return 0;
  }

  /** 表单局部更新。 */
  private patch(change: BotFormPatch): void {
    const next: BotForm = {
      id: this.form.id,
      name: change.name ?? this.form.name,
      role: change.role ?? this.form.role,
      instructions: change.instructions ?? this.form.instructions,
      model: change.model ?? this.form.model,
      effort: change.effort ?? this.form.effort,
      avatarImage: change.avatarImage ?? this.form.avatarImage
    };
    this.onFormChange(next);
  }
}

/** 表单校验（组件内只关心 ok/error）。 */
interface BotFormValidation {
  ok: boolean;
  error: string;
}

/** 表单局部更新。 */
interface BotFormPatch {
  name?: string;
  role?: string;
  instructions?: string;
  model?: string;
  effort?: string;
  avatarImage?: string;
}
