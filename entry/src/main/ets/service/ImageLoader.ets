import { image } from '@kit.ImageKit';
import { MobileClient } from './MobileClient';
import { Attachment } from '../model/Models';

/**
 * 消息内图片的字节加载与解码（P3-1）。
 *
 * 为什么不能用 `Image(url)` 直接加载：
 * 附件下载接口需要 `Authorization` 头 + `conversationId/sessionId/seq` 查询参数，
 * 而 ArkUI 的 `Image` 只能直接吃 http url，无法带鉴权。
 * 所以这里先用带鉴权的 http 客户端取 **ArrayBuffer**，再交给 ImageKit 解码成 PixelMap。
 *
 * 缓存按 `attachmentId` 存 PixelMap：消息列表滚动/重绘很频繁，
 * 每次重建都重新下载解码会明显卡顿（一张 3MB 图解码约几十毫秒）。
 */
export class ImageLoader {
  private static cache: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private static failed: Set<string> = new Set<string>();
  private static MAX_CACHE = 40;

  /** 已缓存的图（没有则 undefined）。 */
  static cached(id: string): image.PixelMap | undefined {
    return ImageLoader.cache.get(id);
  }

  /** 是否已经失败过（避免反复重试刷屏）。 */
  static hasFailed(id: string): boolean {
    return ImageLoader.failed.has(id);
  }

  /** 清空缓存（切换会话/释放内存时用）。 */
  static clear(): void {
    ImageLoader.cache.clear();
    ImageLoader.failed.clear();
  }

  /**
   * 下载并解码一张图片。
   *
   * @param client 已配对的客户端
   * @param conversationId 会话 id（下载鉴权需要）
   * @param sessionId 该消息所属分段
   * @param attachment 附件引用（需要 `id`）
   * @param seq 消息序号（下载鉴权需要）
   */
  static async load(client: MobileClient, conversationId: string, sessionId: string,
    attachment: Attachment, seq: number): Promise<image.PixelMap | undefined> {
    const id = attachment.id ?? '';
    if (id.length === 0) return undefined;
    const hit = ImageLoader.cache.get(id);
    if (hit !== undefined) return hit;
    if (ImageLoader.failed.has(id)) return undefined;
    try {
      const bytes = await client.attachment(conversationId, sessionId, id, seq);
      const source = image.createImageSource(bytes as ArrayBuffer);
      const pixelMap = await source.createPixelMap();
      await source.release();
      // 简单容量控制：超了就丢掉最早的一半（Map 保持插入顺序）
      if (ImageLoader.cache.size >= ImageLoader.MAX_CACHE) {
        const keys = Array.from(ImageLoader.cache.keys()).slice(0, ImageLoader.MAX_CACHE / 2);
        for (let i = 0; i < keys.length; i++) ImageLoader.cache.delete(keys[i]);
      }
      ImageLoader.cache.set(id, pixelMap);
      return pixelMap;
    } catch (_error) {
      ImageLoader.failed.add(id);
      return undefined;
    }
  }
}
