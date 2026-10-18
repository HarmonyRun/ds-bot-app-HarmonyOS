import { Bot, Room } from '../model/Models';
import { botNameOf, describeMode, RoomForm, validateRoomForm } from '../logic/Rooms';
import { SecondaryPageTheme } from './SecondaryPages';

/**
 * 群聊管理（P2-6）。
 *
 * 结构：群列表 → 选中一个进入编辑（名称 / 公告 / 模式 / 管理员 / 成员）→ 保存或删除。
 *
 * 设计取舍：
 * - **编辑在页面内切换，不弹新窗口**：群聊字段少，弹层反而多一次心智切换；
 * - 表单状态由父组件持有（与其它面板一致），保存成功后才刷新列表。
 */
@Component
export struct RoomManagePanel {
  @Prop theme: SecondaryPageTheme = {
    pageBg: '#F5F7FA', rowBg: '#FFFFFF', chipBg: '#FFFFFF', chipLine: '#E3E8F0',
    ink: '#172033', muted: '#657086', line: '#E3E8F0', brand: '#3F5EF5', brandSoft: '#EEF2FF', danger: '#C93F49', dangerBg: '#FFF0F1'
  };
  @Prop rooms: Room[] = [];
  @Prop bots: Bot[] = [];
  /** 正在编辑的群 id（空串表示列表态） */
  @Prop editingId: string = '';
  @Prop form: RoomForm = { id: '', name: '', notice: '', mode: 'admin', admin: '', members: [] };
  @Prop busy: boolean = false;
  @Prop error: string = '';
  /** 上一次保存的变更说明 */
  @Prop changes: string[] = [];
  @Prop readOnly: string = '';

  onClose: () => void = (): void => {};
  onRefresh: () => void = (): void => {};
  onOpenRoom: (roomId: string) => void = (): void => {};
  onBackToList: () => void = (): void => {};
  onFormChange: (form: RoomForm) => void = (): void => {};
  onSave: () => void = (): void => {};
  onDelete: (room: Room) => void = (): void => {};

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 14 }) {
          if (this.readOnly.length > 0) {
            Text(this.readOnly).fontSize(13).fontColor('#B86A16').width('100%')
              .padding(12).backgroundColor('#FFF6E8').borderRadius(12);
          }
          if (this.editingId.length === 0) {
            this.listView();
          } else {
            this.editorView();
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
      Button(this.editingId.length === 0 ? '‹' : '←')
        .width(40).height(40).borderRadius(20).fontSize(this.editingId.length === 0 ? 24 : 18)
        .backgroundColor(this.theme.rowBg).fontColor(this.theme.ink)
        .onClick(() => {
          if (this.editingId.length === 0) this.onClose();
          else this.onBackToList();
        });
      Text(this.editingId.length === 0 ? '群聊管理' : '编辑群聊')
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.theme.ink).layoutWeight(1);
      Button('刷新').height(34).borderRadius(17).fontSize(13)
        .backgroundColor(this.theme.rowBg).fontColor(this.theme.ink)
        .enabled(!this.busy)
        .onClick(() => this.onRefresh());
    }
    .width('100%').height(64).padding({ left: 16, right: 16 });
  }

  /** 群列表。 */
  @Builder
  private listView() {
    Column({ space: 10 }) {
      Text(`共 ${this.rooms.length} 个群聊`).fontSize(13).fontColor(this.theme.muted).width('100%');
      if (this.rooms.length === 0) {
        Text('还没有群聊。可在「Bot 与群聊」页创建。').fontSize(14)
          .fontColor(this.theme.muted).width('100%')
          .padding(18).backgroundColor(this.theme.rowBg).borderRadius(14);
      } else {
        ForEach(this.rooms, (room: Room) => {
          Row({ space: 10 }) {
            Column({ space: 4 }) {
              Text(room.name).fontSize(16).fontColor(this.theme.ink).width('100%')
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
              Text(`${(room.members ?? []).length} 名成员 · ${describeMode(room.mode)}`)
                .fontSize(12).fontColor(this.theme.muted).width('100%');
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
            Text('编辑').fontSize(13).fontColor(this.theme.brand);
          }
          .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14)
          .onClick(() => this.onOpenRoom(room.id));
        }, (room: Room) => `${room.id}#${room.name}#${(room.members ?? []).length}#${room.mode ?? ''}`);
      }
      if (this.changes.length > 0) {
        this.changesCard();
      }
    }.width('100%');
  }

  @Builder
  private changesCard() {
    Column({ space: 4 }) {
      Text('刚刚的修改').fontSize(12).fontColor(this.theme.muted).width('100%');
      ForEach(this.changes, (line: string) => {
        Text(`· ${line}`).fontSize(13).fontColor(this.theme.ink).width('100%');
      }, (line: string) => line);
    }.width('100%').padding(14).backgroundColor(this.theme.rowBg).borderRadius(12);
  }

  /** 编辑表单。 */
  @Builder
  private editorView() {
    Column({ space: 12 }) {
      Text('群名').fontSize(12).fontColor(this.theme.muted).width('100%');
      TextInput({ text: this.form.name }).height(44).width('100%')
        .backgroundColor(this.theme.chipBg).borderRadius(12)
        .fontColor(this.theme.ink).fontSize(14)
        .onChange((value: string) => this.patch({ name: value }));

      Text('公告').fontSize(12).fontColor(this.theme.muted).width('100%');
      TextArea({ text: this.form.notice }).height(72).width('100%')
        .backgroundColor(this.theme.chipBg).borderRadius(12)
        .fontColor(this.theme.ink).fontSize(14)
        .onChange((value: string) => this.patch({ notice: value }));

      Text('回答方式').fontSize(12).fontColor(this.theme.muted).width('100%');
      Row({ space: 8 }) {
        this.modeChip('admin', '管理员先回答');
        this.modeChip('everyone', '成员轮流回答');
      }.width('100%');

      Text('管理员').fontSize(12).fontColor(this.theme.muted).width('100%');
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.form.members, (id: string) => {
          Button(botNameOf(this.bots, id))
            .height(34).margin({ right: 8, bottom: 8 }).borderRadius(17).fontSize(13)
            .backgroundColor(this.form.admin === id ? this.theme.brand : this.theme.chipBg)
            .fontColor(this.form.admin === id ? '#FFFFFF' : this.theme.ink)
            .onClick(() => this.patch({ admin: this.form.admin === id ? '' : id }));
        }, (id: string) => `admin#${id}#${this.form.admin === id}`);
      }.width('100%');

      Text('成员').fontSize(12).fontColor(this.theme.muted).width('100%');
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.bots, (bot: Bot) => {
          Button(bot.name)
            .height(34).margin({ right: 8, bottom: 8 }).borderRadius(17).fontSize(13)
            .backgroundColor(this.form.members.includes(bot.id) ? this.theme.brandSoft : this.theme.chipBg)
            .fontColor(this.form.members.includes(bot.id) ? this.theme.brand : this.theme.muted)
            .onClick(() => this.toggleMember(bot.id));
        }, (bot: Bot) => `member#${bot.id}#${this.form.members.includes(bot.id)}`);
      }.width('100%');

      if (!this.validate().ok) {
        Text(this.validate().error).fontSize(12).fontColor(this.theme.muted).width('100%');
      }
      Button(this.busy ? '保存中…' : '保存修改')
        .width('100%').height(46).borderRadius(12).fontSize(15)
        .backgroundColor(this.theme.brand).fontColor('#FFFFFF')
        .enabled(!this.busy && this.validate().ok)
        .onClick(() => this.onSave());
      Button('删除这个群聊')
        .width('100%').height(44).borderRadius(12).fontSize(15)
        .backgroundColor(this.theme.chipBg).fontColor('#C93F49')
        .enabled(!this.busy)
        .onClick(() => this.onDeleteCurrent());
    }
    .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14);
  }

  @Builder
  private modeChip(mode: string, label: string) {
    Button(label)
      .layoutWeight(1).height(38).borderRadius(12).fontSize(13)
      .backgroundColor(this.form.mode === mode ? this.theme.brand : this.theme.chipBg)
      .fontColor(this.form.mode === mode ? '#FFFFFF' : this.theme.ink)
      .onClick(() => this.patch({ mode: mode === 'everyone' ? 'everyone' : 'admin' }));
  }

  private validate(): RoomFormValidation {
    return validateRoomForm(this.form);
  }

  /** 删除当前编辑的群（父组件负责确认与调用）。 */
  private onDeleteCurrent(): void {
    for (let i = 0; i < this.rooms.length; i++) {
      if (this.rooms[i].id === this.form.id) {
        this.onDelete(this.rooms[i]);
        return;
      }
    }
  }

  /** 表单局部更新（父组件持有表单）。 */
  private patch(change: RoomFormPatch): void {
    const next: RoomForm = {
      id: this.form.id,
      name: change.name ?? this.form.name,
      notice: change.notice ?? this.form.notice,
      mode: change.mode ?? this.form.mode,
      admin: change.admin ?? this.form.admin,
      members: change.members ?? this.form.members
    };
    this.onFormChange(next);
  }

  /** 勾选/取消成员；移除成员时如果他是管理员就一并清空管理员。 */
  private toggleMember(botId: string): void {
    const next: string[] = [];
    let removed = false;
    for (let i = 0; i < this.form.members.length; i++) {
      const current = this.form.members[i];
      if (current === botId) removed = true;
      else next.push(current);
    }
    if (!removed) next.push(botId);
    const admin = removed && this.form.admin === botId ? '' : this.form.admin;
    this.patch({ members: next, admin: admin });
  }
}

/** 表单校验结果（避免在组件里引用 logic 的接口名）。 */
interface RoomFormValidation {
  ok: boolean;
  error: string;
}

/** 表单局部更新。 */
interface RoomFormPatch {
  name?: string;
  notice?: string;
  mode?: 'admin' | 'everyone';
  admin?: string;
  members?: string[];
}
