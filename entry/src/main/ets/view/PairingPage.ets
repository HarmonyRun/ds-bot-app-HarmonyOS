/**
 * 配对页（抽自 `Index.ets` 的 `pairingPage`）。
 *
 * 首次启动、尚未配对时显示：品牌标记 + **扫码连接** + 配对 JSON 输入 + 设备名 + 连接按钮。
 *
 * 扫码优先：电脑端显示的配对 JSON 可生成二维码，手机直接扫即可，
 * 省掉在手机上粘贴长 JSON 的步骤（过去用 `uitest inputText` 连测试都会被引号搅乱）。
 *
 * 设计：**自持表单状态**。
 * `pairingJson` / `deviceName` 只服务于这一页，搬进组件后 `Index` 少两个 `@State`；
 * 错误文案与忙碌态由父组件传入（它们来自配对流程，不在页面内产生）。
 * 品牌标记（`appMark`）由父组件经 `@BuilderParam` 注入，保证全工程只有一处实现。
 */
export interface PairingTheme {
  pageBg: string;
  surface: string;
  ink: string;
  muted: string;
  brand: string;
  error: string;
}

@Component
export struct PairingPage {
  @Prop theme: PairingTheme = {
    pageBg: '#F5F7FA', surface: '#FFFFFF', ink: '#172033', muted: '#657086',
    brand: '#3F5EF5', error: '#C93F49'
  };
  /** 外层页面底色（略深于卡片） */
  @Prop outerBg: string = '#FFFFFF';
  @Prop title: string = 'DS Bot';
  @Prop subtitle: string = '把你的 Bot 团队带到鸿蒙设备上';
  @Prop cardTitle: string = '连接主机';
  @Prop cardHint: string = '在电脑端打开 DS Bot 设置 → 移动设备，启用手机连接，然后粘贴完整配对 JSON 并在电脑端批准。';
  @Prop jsonPlaceholder: string = '{"url":"https://…","code":"…","serverId":"…"}';
  @Prop devicePlaceholder: string = '设备名称';
  @Prop submitLabel: string = '连接我的主机';
  @Prop busyLabel: string = '等待电脑批准…';
  @Prop footer: string = '连接信息和会话凭据仅保存在本机应用沙箱中。';
  /** 扫码按钮文案 */
  @Prop scanLabel: string = '扫码连接主机';
  @Prop scanHint: string = '在电脑端打开 DS Bot 设置 → 移动设备，用手机扫描屏幕上的二维码';
  /** 是否支持扫码（无相机/低版本设备可关闭） */
  @Prop scanEnabled: boolean = true;

  /** 初始值（父组件可能预填） */
  @Prop initialJson: string = '';
  @Prop initialDeviceName: string = '';
  /** 错误文案（空串不显示） */
  @Prop error: string = '';
  @Prop busy: boolean = false;

  /** 提交：把这一页的两个输入交回父组件 */
  onSubmit: (json: string, deviceName: string) => void = (): void => {};
  /** 点击扫码：由父组件调用原生 ScanKit（组件不直接依赖 HMS，便于测试与降级） */
  onScan: () => void = (): void => {};

  @State private json: string = '';
  @State private deviceName: string = '';
  @State private seeded: boolean = false;

  aboutToAppear(): void {
    // 只灌一次：之后以用户输入为准，避免父组件重渲染把输入冲掉
    if (!this.seeded) {
      this.json = this.initialJson;
      this.deviceName = this.initialDeviceName;
      this.seeded = true;
    }
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        this.mark();
        Text(this.title).fontSize(32).fontWeight(FontWeight.Bold).fontColor(this.theme.ink);
        Text(this.subtitle).fontSize(16).fontColor(this.theme.muted).textAlign(TextAlign.Center);
        this.connectCard();
        Text(this.footer).fontSize(12).fontColor(this.theme.muted).textAlign(TextAlign.Center);
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
      .padding({ left: 20, right: 20, top: 40, bottom: 40 });
    }.width('100%').height('100%').backgroundColor(this.outerBg);
  }

  /** 品牌标记（父组件注入，全工程一处实现） */
  @BuilderParam mark: () => void;

  @Builder
  private connectCard() {
    Column({ space: 14 }) {
      Text(this.cardTitle).fontSize(21).fontWeight(FontWeight.Medium)
        .fontColor(this.theme.ink).width('100%');
      Text(this.cardHint).fontSize(14).lineHeight(21).fontColor(this.theme.muted);
      if (this.scanEnabled) {
        Button() {
          Row({ space: 8 }) {
            Image($r('app.media.ic_scan')).width(20).height(20);
            Text(this.scanLabel).fontSize(16).fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF');
          }
        }
        .width('100%').height(50).borderRadius(14).backgroundColor(this.theme.brand)
        .enabled(!this.busy)
        .onClick(() => this.onScan());
        Text(this.scanHint).fontSize(12).lineHeight(18)
          .fontColor(this.theme.muted).textAlign(TextAlign.Center).width('100%');
        Row({ space: 10 }) {
          Divider().color(this.theme.pageBg).layoutWeight(1);
          Text('或手动粘贴').fontSize(12).fontColor(this.theme.muted);
          Divider().color(this.theme.pageBg).layoutWeight(1);
        }.width('100%').alignItems(VerticalAlign.Center);
      }
      TextArea({ placeholder: this.jsonPlaceholder, text: this.json })
        .height(120).fontSize(14).fontColor(this.theme.ink).backgroundColor(this.theme.pageBg)
        .borderRadius(10).padding(12).border({ width: 1, color: this.theme.pageBg })
        .onChange((value: string) => this.json = value);
      TextInput({ placeholder: this.devicePlaceholder, text: this.deviceName })
        .height(48).fontSize(15).fontColor(this.theme.ink).backgroundColor(this.theme.pageBg)
        .borderRadius(10).padding({ left: 14, right: 14 }).border({ width: 1, color: this.theme.pageBg })
        .onChange((value: string) => this.deviceName = value);
      if (this.error.length > 0) {
        Text(this.error).fontSize(13).fontColor(this.theme.error).width('100%');
      }
      Button(this.busy ? this.busyLabel : this.submitLabel)
        .width('100%').height(48).borderRadius(12).backgroundColor(this.theme.brand)
        .fontSize(17)
        .enabled(!this.busy && this.json.trim().length > 0 && this.deviceName.trim().length > 0)
        .onClick(() => this.onSubmit(this.json, this.deviceName));
    }
    .width('100%').constraintSize({ maxWidth: 560 }).padding(22)
    .backgroundColor(this.theme.surface).borderRadius(16)
    .border({ width: 1, color: this.theme.pageBg });
  }
}
