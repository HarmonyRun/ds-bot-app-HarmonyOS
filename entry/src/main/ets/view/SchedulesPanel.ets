import { ScheduleTask } from '../model/Models';
import {
  describeSchedule, describeTarget, isExpired, localDateTime, ScheduleForm, ScheduleKind,
  ScheduleValidation, validateScheduleForm
} from '../logic/Schedules';
import { SecondaryPageTheme } from './SecondaryPages';

/**
 * 定时任务面板（P2-3）。
 *
 * 结构：任务列表（可删除）+ 新建表单（目标 / 名称 / 内容 / 时间形态）。
 * 时间形态与宿主 `selectorOf` 一一对应：一次性 / 每天 / 每周 / 间隔。
 *
 * 设计取舍：
 * - 时间输入用**纯文本 + 校验**而不是原生 DatePicker：原生日期选择器在
 *   手机上要多层弹窗，而这里只需要「某天某时」，`YYYY-MM-DDTHH:mm` 文本更直接；
 * - 表单状态由父组件持有（`form` 传进来），因为提交后要保留/清空由父组件决定。
 */
@Component
export struct SchedulesPanel {
  @Prop theme: SecondaryPageTheme = {
    pageBg: '#F5F7FA', rowBg: '#FFFFFF', chipBg: '#FFFFFF', chipLine: '#E3E8F0',
    ink: '#172033', muted: '#657086', line: '#E3E8F0', brand: '#3F5EF5', brandSoft: '#EEF2FF', danger: '#C93F49', dangerBg: '#FFF0F1'
  };
  @Prop tasks: ScheduleTask[] = [];
  /** 主机是否开启自动化任务服务 */
  @Prop available: boolean = true;
  @Prop loading: boolean = false;
  @Prop error: string = '';
  /** Bot / 群聊候选（id + 显示名），用于目标选择 */
  @Prop targets: ScheduleTarget[] = [];
  @Prop botNames: Map<string, string> = new Map<string, string>();
  @Prop roomNames: Map<string, string> = new Map<string, string>();
  /** 表单（父组件持有） */
  @Prop form: ScheduleForm = {
    target: '', title: '', prompt: '', kind: 'daily',
    atLocal: '', time: '09:00', weekdays: [], minutes: 60, timeZone: 'UTC'
  };
  /** 表单错误（父组件在提交失败时写入） */
  @Prop formError: string = '';
  @Prop creating: boolean = false;

  onClose: () => void = (): void => {};
  onRefresh: () => void = (): void => {};
  onDelete: (task: ScheduleTask) => void = (): void => {};
  onFormChange: (form: ScheduleForm) => void = (): void => {};
  onCreate: (validation: ScheduleValidation) => void = (): void => {};

  /** 当前时间 + 校验（提交前预览错误，避免用户点了才发现） */
  private validate(): ScheduleValidation {
    return validateScheduleForm(this.form, Date.now());
  }

  /** 目标候选里是否已有选中项 */
  private targetLabel(): string {
    for (let i = 0; i < this.targets.length; i++) {
      if (this.targets[i].id === this.form.target) return this.targets[i].name;
    }
    return '选择目标';
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 14 }) {
          if (!this.available) {
            Text('主机未开启「自动化任务」，无法使用定时任务。')
              .fontSize(14).fontColor(this.theme.muted).width('100%')
              .padding(18).backgroundColor(this.theme.rowBg).borderRadius(14);
          } else {
            this.formCard();
            this.listCard();
          }
          if (this.error.length > 0) {
            Text(this.error).fontSize(13).fontColor('#C93F49').width('100%')
              .padding(14).backgroundColor(this.theme.rowBg).borderRadius(12);
          }
        }
        .width('100%').padding({ left: 18, right: 18, top: 4, bottom: 28 });
      }
      .layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }
    .width('100%').height('100%').backgroundColor(this.theme.pageBg);
  }

  @Builder
  private header() {
    Row({ space: 12 }) {
      Button('‹').width(40).height(40).borderRadius(20).fontSize(24)
        .backgroundColor(this.theme.rowBg).fontColor(this.theme.ink)
        .onClick(() => this.onClose());
      Text('定时任务').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.theme.ink)
        .layoutWeight(1);
      Button(this.loading ? '读取中' : '刷新')
        .height(34).borderRadius(17).fontSize(13)
        .backgroundColor(this.theme.rowBg).fontColor(this.theme.ink)
        .enabled(!this.loading)
        .onClick(() => this.onRefresh());
    }
    .width('100%').height(64).padding({ left: 16, right: 16 });
  }

  /** 新建表单。 */
  @Builder
  private formCard() {
    Column({ space: 12 }) {
      Text('新建任务').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.ink)
        .width('100%');

      // 目标：Bot / 群聊横排胶囊
      Text('目标').fontSize(12).fontColor(this.theme.muted).width('100%');
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.targets, (target: ScheduleTarget) => {
          Button(target.name)
            .height(34).margin({ right: 8, bottom: 8 }).borderRadius(17).fontSize(13)
            .backgroundColor(this.form.target === target.id ? this.theme.brand : this.theme.chipBg)
            .fontColor(this.form.target === target.id ? '#FFFFFF' : this.theme.ink)
            .onClick(() => this.patch({ target: target.id }));
        }, (target: ScheduleTarget) => `${target.id}#${this.form.target === target.id}`);
      }.width('100%');

      TextInput({ placeholder: '任务名称', text: this.form.title })
        .height(44).width('100%').backgroundColor(this.theme.chipBg).borderRadius(12)
        .fontColor(this.theme.ink).fontSize(14)
        .onChange((value: string) => this.patch({ title: value }));
      TextInput({ placeholder: '让 Bot 做什么（会作为消息发出）', text: this.form.prompt })
        .height(44).width('100%').backgroundColor(this.theme.chipBg).borderRadius(12)
        .fontColor(this.theme.ink).fontSize(14)
        .onChange((value: string) => this.patch({ prompt: value }));

      // 时间形态
      Text('执行时间').fontSize(12).fontColor(this.theme.muted).width('100%');
      Row({ space: 8 }) {
        this.kindChip('at', '一次性');
        this.kindChip('daily', '每天');
        this.kindChip('weekly', '每周');
        this.kindChip('every', '间隔');
      }.width('100%');

      if (this.form.kind === 'at') {
        TextInput({ placeholder: '2026-10-20T09:00', text: this.form.atLocal })
          .height(44).width('100%').backgroundColor(this.theme.chipBg).borderRadius(12)
          .fontColor(this.theme.ink).fontSize(14)
          .onChange((value: string) => this.patch({ atLocal: value }));
        Text('格式：YYYY-MM-DDTHH:mm（本地时间）').fontSize(11)
          .fontColor(this.theme.muted).width('100%');
      } else if (this.form.kind === 'daily' || this.form.kind === 'weekly') {
        TextInput({ placeholder: '09:00', text: this.form.time })
          .height(44).width('100%').backgroundColor(this.theme.chipBg).borderRadius(12)
          .fontColor(this.theme.ink).fontSize(14)
          .onChange((value: string) => this.patch({ time: value }));
        if (this.form.kind === 'weekly') {
          Row({ space: 6 }) {
            ForEach([1, 2, 3, 4, 5, 6, 7], (day: number) => {
              Button(['一', '二', '三', '四', '五', '六', '日'][day - 1])
                .layoutWeight(1).height(34).borderRadius(10).fontSize(13)
                .backgroundColor(this.form.weekdays.includes(day) ? this.theme.brand : this.theme.chipBg)
                .fontColor(this.form.weekdays.includes(day) ? '#FFFFFF' : this.theme.ink)
                .onClick(() => this.toggleWeekday(day));
            }, (day: number) => `${day}#${this.form.weekdays.includes(day)}`);
          }.width('100%');
        }
      } else {
        TextInput({ placeholder: '间隔分钟数，例如 60', text: `${this.form.minutes}` })
          .height(44).width('100%').backgroundColor(this.theme.chipBg).borderRadius(12)
          .fontColor(this.theme.ink).fontSize(14)
          .type(InputType.Number)
          .onChange((value: string) => {
            const parsed = Number.parseInt(value, 10);
            this.patch({ minutes: Number.isNaN(parsed) ? 0 : parsed });
          });
        Text('可填 1 分钟 ~ 7 天（10080 分钟）').fontSize(11)
          .fontColor(this.theme.muted).width('100%');
      }

      if (this.formError.length > 0) {
        Text(this.formError).fontSize(12).fontColor('#C93F49').width('100%');
      } else {
        // 实时预览：让用户在提交前就知道规则是否满足
        if (!this.validate().ok) {
          Text(this.validate().error).fontSize(12).fontColor(this.theme.muted).width('100%');
        }
      }

      Button(this.creating ? '正在创建…' : '创建任务')
        .width('100%').height(46).borderRadius(12).fontSize(15)
        .backgroundColor(this.theme.brand).fontColor('#FFFFFF')
        .enabled(!this.creating && this.validate().ok)
        .onClick(() => this.onCreate(this.validate()));
    }
    .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14);
  }

  @Builder
  private kindChip(kind: string, label: string) {
    Button(label)
      .layoutWeight(1).height(34).borderRadius(10).fontSize(13)
      .backgroundColor(this.form.kind === kind ? this.theme.brand : this.theme.chipBg)
      .fontColor(this.form.kind === kind ? '#FFFFFF' : this.theme.ink)
      .onClick(() => this.patch({ kind: kind as ScheduleKind }));
  }

  /** 任务列表。 */
  @Builder
  private listCard() {
    Column({ space: 10 }) {
      Text(`已有任务（${this.tasks.length}）`).fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor(this.theme.ink).width('100%');
      if (this.tasks.length === 0) {
        Text('还没有定时任务。').fontSize(13).fontColor(this.theme.muted).width('100%');
      } else {
        ForEach(this.tasks, (task: ScheduleTask) => {
          Column({ space: 4 }) {
            Row({ space: 8 }) {
              Text(task.title).fontSize(15).fontColor(this.theme.ink).layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
              if (isExpired(task, Date.now())) {
                Text('已过期').fontSize(11).fontColor(this.theme.muted);
              }
              Button('删除')
                .height(30).borderRadius(15).fontSize(12)
                .backgroundColor(this.theme.chipBg).fontColor('#C93F49')
                .onClick(() => this.onDelete(task));
            }.width('100%');
            Text(`${describeTarget(task, this.botNames, this.roomNames)} · ${describeSchedule(task)}`)
              .fontSize(12).fontColor(this.theme.muted).width('100%')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .width('100%').padding({ top: 8, bottom: 8 });
          Divider().color(this.theme.line);
        }, (task: ScheduleTask) => `${task.id}#${task.title}`);
      }
    }
    .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14);
  }

  /** 合并式表单更新（父组件持有表单，这里发出变更）。 */
  private patch(change: ScheduleFormPatch): void {
    const next: ScheduleForm = {
      target: change.target ?? this.form.target,
      title: change.title ?? this.form.title,
      prompt: change.prompt ?? this.form.prompt,
      kind: change.kind ?? this.form.kind,
      atLocal: change.atLocal ?? this.form.atLocal,
      time: change.time ?? this.form.time,
      weekdays: change.weekdays ?? this.form.weekdays,
      minutes: change.minutes ?? this.form.minutes,
      timeZone: change.timeZone ?? this.form.timeZone
    };
    this.onFormChange(next);
  }

  private toggleWeekday(day: number): void {
    const next: number[] = [];
    const had = this.form.weekdays.includes(day);
    for (let i = 0; i < this.form.weekdays.length; i++) {
      const current = this.form.weekdays[i];
      if (current !== day) next.push(current);
    }
    if (!had) next.push(day);
    next.sort();
    this.patch({ weekdays: next });
  }
}

/** 目标候选（Bot 或群聊）。 */
export interface ScheduleTarget {
  id: string;
  name: string;
}

/** 表单局部更新（未提供的字段保持原值）。 */
export interface ScheduleFormPatch {
  target?: string;
  title?: string;
  prompt?: string;
  kind?: ScheduleKind;
  atLocal?: string;
  time?: string;
  weekdays?: number[];
  minutes?: number;
  timeZone?: string;
}
