import { image } from '@kit.ImageKit';
import { Attachment } from '../model/Models';
import { fitImageSize, formatSize, imagesOf, filesOf } from '../logic/Attachments';
import { ImageLoader } from '../service/ImageLoader';

/**
 * 消息内附件（P3-1）。
 *
 * 图片：按原始宽高比占位 → 加载完成后显示真实图片（点按放大到全屏）。
 * 文件：只显示名字与体积（主机不提供内联预览）。
 *
 * 布局约束：宽度必须由外部传入**确定数值**（`maxWidth`）。
 * 这个工程里 `width('100%')` 在气泡内会溢出，之前为表格/代码块踩过很多次。
 */
@Component
export struct MessageAttachments {
  @Prop attachments: Attachment[] = [];
  /** 可用宽度（由气泡算好后传入） */
  @Prop maxWidth: number = 240;
  @Prop dark: boolean = false;
  /** 加载图片字节的注入点（父组件持有已配对的客户端与上下文） */
  loadImage: (attachment: Attachment) => Promise<image.PixelMap | undefined> =
    (attachment: Attachment): Promise<image.PixelMap | undefined> =>
      Promise.resolve(undefined);
  onOpen: (attachment: Attachment) => void = (): void => {};

  @State private reloadToken: number = 0;

  build() {
    Column({ space: 8 }) {
      ForEach(imagesOf(this.attachments), (item: Attachment) => {
        this.imageTile(item);
      }, (item: Attachment) => `img:${item.id ?? item.name}:${this.reloadToken}`);

      ForEach(filesOf(this.attachments), (item: Attachment) => {
        Row({ space: 8 }) {
          Text('📄').fontSize(16);
          Column({ space: 2 }) {
            Text(item.name).fontSize(13)
              .fontColor(this.dark ? '#E8ECF4' : '#172033')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
            if (item.size !== undefined) {
              Text(formatSize(item.size)).fontSize(11)
                .fontColor(this.dark ? '#9AA3B5' : '#657086');
            }
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        }
        .width(this.maxWidth).padding(10)
        .backgroundColor(this.dark ? '#2A2F3D' : '#F2F4F8').borderRadius(10)
        .onClick(() => this.onOpen(item));
      }, (item: Attachment) => `file:${item.id ?? item.name}`);
    }
    .width(this.maxWidth)
    .alignItems(HorizontalAlign.Start);
  }

  /** 一张图片：先按比例占位，加载好后显示。 */
  @Builder
  private imageTile(item: Attachment) {
    ImageTile({
      attachment: item,
      maxWidth: this.maxWidth,
      dark: this.dark,
      loadImage: this.loadImage,
      onOpen: this.onOpen,
      onRetry: (): void => { this.reloadToken += 1; }
    });
  }
}

/**
 * 单张图片。单独抽出来是因为每张图都有自己的加载状态，
 * 放在父组件的数组里会让状态互相干扰。
 */
@Component
struct ImageTile {
  @Prop attachment: Attachment = { name: '' };
  @Prop maxWidth: number = 240;
  @Prop dark: boolean = false;
  loadImage: (attachment: Attachment) => Promise<image.PixelMap | undefined> =
    (attachment: Attachment): Promise<image.PixelMap | undefined> =>
      Promise.resolve(undefined);
  onOpen: (attachment: Attachment) => void = (): void => {};
  onRetry: () => void = (): void => {};

  @State private pixelMap: image.PixelMap | undefined = undefined;
  @State private loading: boolean = true;
  @State private failed: boolean = false;

  // 不能叫 `size()`：与 ArkUI CustomComponent 的内建属性同名会编译失败
  private tileSize(): DisplaySizeBox {
    return fitImageSize(this.attachment.width, this.attachment.height, this.maxWidth, 320);
  }

  aboutToAppear(): void {
    this.start();
  }

  private async start(): Promise<void> {
    const cached = this.attachment.id === undefined
      ? undefined
      : ImageLoader.cached(this.attachment.id);
    if (cached !== undefined) {
      this.pixelMap = cached;
      this.loading = false;
      return;
    }
    this.loading = true;
    this.failed = false;
    const result = await this.loadImage(this.attachment);
    if (result === undefined) {
      this.failed = true;
    } else {
      this.pixelMap = result;
    }
    this.loading = false;
  }

  build() {
    Stack() {
      if (this.pixelMap !== undefined) {
        Image(this.pixelMap)
          .width(this.tileSize().width > 0 ? this.tileSize().width : this.maxWidth)
          .height(this.tileSize().height > 0 ? this.tileSize().height : this.maxWidth * 0.75)
          .objectFit(ImageFit.Cover)
          .borderRadius(12);
      } else {
        Column({ space: 6 }) {
          if (this.failed) {
            Text('图片加载失败').fontSize(12).fontColor('#C93F49');
            Button('重试').height(28).fontSize(12).borderRadius(14)
              .backgroundColor(this.dark ? '#2A2F3D' : '#F2F4F8')
              .fontColor(this.dark ? '#E8ECF4' : '#172033')
              .onClick(() => this.onRetry());
          } else {
            LoadingProgress().width(22).height(22).color('#6F758B');
          }
        }
        .width(this.tileSize().width > 0 ? this.tileSize().width : this.maxWidth)
        .height(this.tileSize().height > 0 ? this.tileSize().height : this.maxWidth * 0.75)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.dark ? '#2A2F3D' : '#F2F4F8')
        .borderRadius(12);
      }
    }
    .borderRadius(12)
    .onClick(() => {
      if (this.pixelMap !== undefined) this.onOpen(this.attachment);
    });
  }
}

/** 展示尺寸（避免在 build 里直接用 logic 的接口名）。 */
interface DisplaySizeBox {
  width: number;
  height: number;
}
