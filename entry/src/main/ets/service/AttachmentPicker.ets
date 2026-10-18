import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { PendingAttachment, attachmentProblem, baseName, isImageType, mediaTypeOf } from '../logic/Attachments';
import { avatarTypeProblem } from '../logic/Bots';
import { toBase64 } from './Base64';

/**
 * 原生附件选择（P3-1）。
 *
 * 全部走系统能力，不自绘选择器：
 * - 图片用 `photoAccessHelper.PhotoViewPicker`（相册，用户熟悉、自动处理权限）；
 * - 文件用 `picker.DocumentViewPicker`（文件管理器）。
 *
 * 选中后立刻读出字节并做**本地校验**（大小/类型），不合格的直接返回带 `error` 的条目，
 * 让界面显示原因，而不是等上传被主机拒绝。
 */
export class AttachmentPicker {
  /**
   * 选一张头像图，返回 mediaType 与 base64（P3-1 反馈）。
   *
   * 头像不需要上传到 `/uploads`：宿主直接把头像存成 data URL 放进 Bot 记录里，
   * 所以这里只取字节并转 base64。
   */
  static async pickAvatar(): Promise<AvatarPick> {
    // 用**文件选择器**而不是相册选择器：
    // `PhotoViewPicker` 返回的是 `file://media/Photo/...` 这类媒体 URI，
    // `fileIo.openSync` 直接打开会失败（2026-10-18 真机实测：头像选了没反应且无提示）。
    // 文件选择器同样能浏览相册里的图片，且给出的 uri 可以直接读。
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    const uris = await new picker.DocumentViewPicker().select(options);
    if (uris.length === 0) return { mediaType: '', base64: '', error: '' };
    const uri = uris[0];
    const name = baseName(uri);
    const mediaType = mediaTypeOf(name);
    const problem = avatarTypeProblem(mediaType);
    if (problem.length > 0) return { mediaType: mediaType, base64: '', error: problem };
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      try {
        const stat = fileIo.statSync(file.fd);
        const buffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buffer);
        return { mediaType: mediaType, base64: toBase64(buffer), error: '' };
      } finally {
        fileIo.closeSync(file);
      }
    } catch (error) {
      return { mediaType: mediaType, base64: '', error: `读取失败：${(error as Error).message}` };
    }
  }

  /** 选图片（可多选）。返回带本地预览字节的条目（未上传）。 */
  static async pickImages(max: number): Promise<PendingAttachment[]> {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = max;
    const result = await new photoAccessHelper.PhotoViewPicker().select(options);
    return AttachmentPicker.readAll(result.photoUris);
  }

  /** 选文件（可多选）。 */
  static async pickFiles(max: number): Promise<PendingAttachment[]> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = max;
    const result = await new picker.DocumentViewPicker().select(options);
    return AttachmentPicker.readAll(result);
  }

  /** 逐个读取 uri 的字节并做本地校验。 */
  private static readAll(uris: string[]): PendingAttachment[] {
    const result: PendingAttachment[] = [];
    for (let i = 0; i < uris.length; i++) {
      result.push(AttachmentPicker.readOne(uris[i], i));
    }
    return result;
  }

  private static readOne(uri: string, index: number): PendingAttachment {
    const name = baseName(uri);
    const mediaType = mediaTypeOf(name);
    const item: PendingAttachment = {
      key: `${Date.now()}-${index}`,
      name: name,
      mediaType: mediaType,
      size: 0
    };
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      try {
        const stat = fileIo.statSync(file.fd);
        item.size = stat.size;
        const problem = attachmentProblem(name, mediaType, stat.size);
        if (problem.length > 0) {
          item.error = problem;
          return item;
        }
        const buffer = new ArrayBuffer(stat.size);
        fileIo.readSync(file.fd, buffer);
        if (isImageType(mediaType)) item.preview = buffer;
      } finally {
        fileIo.closeSync(file);
      }
    } catch (error) {
      item.error = `读取失败：${(error as Error).message}`;
    }
    return item;
  }
}

/** 头像选择结果。 */
export interface AvatarPick {
  mediaType: string;
  base64: string;
  error: string;
}
