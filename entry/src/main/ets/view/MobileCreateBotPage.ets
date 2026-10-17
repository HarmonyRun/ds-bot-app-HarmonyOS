import { BotAvatarView } from './BotAvatarView';

/**
 * 手机端「创建新 Bot」整页（抽自 `Index.ets` 的 `mobileCreateBotPage`）。
 *
 * 结构：顶部标题栏（关闭 + 居中标题）+ 头像预览 + 名称输入 + 形状网格 + 色板网格 + 提交。
 *
 * 设计要点：
 * - **形状与色板网格直接渲染矢量预览**（`BotAvatarView`），颜色随当前选择实时变化，
 *   替代了旧版 13 张固定配色 PNG 的做法；
 * - 形状/颜色候选由父组件给出（`shapes` / `colors`），组件不认识头像表；
 * - 头像预览（126vp 那层）仍由父组件传入，因为它是 Index 的 `botAvatarPreview` 构建器。
 */
@Component
export struct MobileCreateBotPage {
  @Prop ink: string = '#172033';
  @Prop muted: string = '#657086';
  /** 页面底色（搜索页/创建页略不同于聊天页） */
  @Prop pageBg: string = '#FAFAFA';
  @Prop fieldBg: string = '#EFEFEF';
  @Prop cardBg: string = '#FFFFFF';
  /** 描边色。**不能叫 `border`**：那是 ArkUI 内置属性名，会与 `CustomComponent` 冲突 */
  @Prop edgeColor: string = '#E5E5E5';
  @Prop brand: string = '#3F5EF5';

  @Prop title: string = '创建新 Bot';
  @Prop namePlaceholder: string = '为 Bot 取个名字';
  @Prop name: string = '';
  @Prop shape: string = '';
  @Prop color: string = '';
  /** 可选形状（父组件给出） */
  @Prop shapes: string[] = [];
  /** 可选颜色（父组件给出） */
  @Prop colors: string[] = [];
  @Prop busy: boolean = false;
  @Prop online: boolean = false;
  @Prop submitLabel: string = '创建 Bot';
  @Prop busyLabel: string = '正在创建…';

  onClose: () => void = (): void => {};
  onNameChange: (value: string) => void = (): void => {};
  onShapeChange: (value: string) => void = (): void => {};
  onColorChange: (value: string) => void = (): void => {};
  onSubmit: () => void = (): void => {};
  /** 头像预览（父组件的 `botAvatarPreview(size)`） */
  @BuilderParam preview: () => void;

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 24 }) {
          this.preview();
          TextInput({ placeholder: this.namePlaceholder, text: this.name })
            .width('100%').height(56).fontSize(18).fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center).fontColor(this.ink).backgroundColor(this.fieldBg)
            .borderRadius(12).border({ width: 1, color: this.edgeColor })
            .onChange((value: string) => this.onNameChange(value));

          Text('选择形状').fontSize(14).fontColor(this.muted).width('100%');
          this.shapeGrid();

          Text('选择颜色').fontSize(14).fontColor(this.muted).width('100%');
          this.colorGrid();

          Button(this.busy ? this.busyLabel : this.submitLabel)
            .width('100%').height(48).borderRadius(12)
            .margin({ top: 12, bottom: 18 }).backgroundColor(this.brand).fontSize(17)
            .enabled(!this.busy && this.online && this.name.trim().length > 0)
            .onClick(() => this.onSubmit());
        }.width('100%').padding({ left: 24, right: 24, top: 32, bottom: 30 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }.width('100%').height('100%').backgroundColor(this.pageBg);
  }

  @Builder
  private header() {
    Row() {
      Button() {
        Image($r('app.media.ic_close')).width(22).height(22);
      }
      .width(44).height(44).borderRadius(12).backgroundColor(this.cardBg)
      .border({ width: 1, color: this.edgeColor })
      .onClick(() => this.onClose());
      Text(this.title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink)
        .layoutWeight(1).textAlign(TextAlign.Center);
      Blank().width(44);
    }.width('100%').height(68).padding({ left: 20, right: 20, top: 10, bottom: 12 })
      .backgroundColor(this.cardBg).border({ width: { bottom: 1 }, color: this.edgeColor });
  }

  /** 形状网格：矢量预览，颜色随当前选择实时变化（旧版是 13 张固定配色 PNG）。 */
  @Builder
  private shapeGrid() {
    Grid() {
      ForEach(this.shapes, (shape: string) => {
        GridItem() {
          Stack() {
            BotAvatarView({ shape: shape, color: this.color, avatarSize: 40, image: '' });
          }
          .width(56).height(52)
          .borderRadius(12)
          .border({ width: this.shape === shape ? 2 : 0, color: this.brand })
          .onClick(() => this.onShapeChange(shape));
        }
      }, (shape: string) => shape);
    }
    .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
    .columnsGap(6).rowsGap(6).width('100%').height(240);
  }

  /** 色板：颜色取自矢量头像的 inks 表（12 色，含上游的 aurora）。 */
  @Builder
  private colorGrid() {
    Grid() {
      ForEach(this.colors, (color: string) => {
        GridItem() {
          Column({ space: 2 }) {
            Stack() {
              BotAvatarView({ shape: this.shape, color: color, avatarSize: 34, image: '' });
            }
            .width(48).height(40)
            .borderRadius(10)
            .border({ width: this.color === color ? 2 : 0, color: this.brand });
            Text(color).fontSize(9).fontColor(this.muted).maxLines(1);
          }
          .onClick(() => this.onColorChange(color));
        }
      }, (color: string) => color);
    }
    .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
    .columnsGap(4).rowsGap(6).width('100%').height(150);
  }
}
