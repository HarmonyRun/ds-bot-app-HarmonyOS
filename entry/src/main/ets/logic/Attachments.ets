import { Attachment } from '../model/Models';

/**
 * 附件的**纯逻辑**（P3-1）。
 *
 * 宿主对附件的限制（`src/mobile/adapter.js`）：
 * - 图片 ≤ **10 MiB**，其它文件 ≤ **20 MiB**；
 * - 只接受 `image/png|jpeg|webp|gif` 作为图片，且**字节必须与声明类型一致**；
 * - 一条消息最多 **8** 个附件；
 * - 文件名会被截到 255 字符。
 *
 * 这些限制错了会在主机侧被拒（413/415），而且用户很难看懂原因，
 * 所以必须在选择文件时就拦下并给清楚提示。
 */

/** 图片上限 10 MiB。 */
export const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
/** 其它文件上限 20 MiB。 */
export const MAX_FILE_BYTES = 20 * 1024 * 1024;
/** 单条消息最多 8 个附件。 */
export const MAX_ATTACHMENTS = 8;
/** 图片类型白名单（与宿主一致）。 */
const IMAGE_TYPES: string[] = ['image/png', 'image/jpeg', 'image/webp', 'image/gif'];

/** 已选附件（本地态，上传成功后带 receiptId）。 */
export interface PendingAttachment {
  /** 本地唯一键（用完即弃） */
  key: string;
  name: string;
  mediaType: string;
  size: number;
  /** 上传成功后由主机返回；为空表示尚未上传 */
  receiptId?: string;
  /** 上传失败原因（用于展示与阻止发送） */
  error?: string;
  /** 本地预览字节（图片用；非图片可空） */
  preview?: ArrayBuffer;
}

/** 是否是宿主认可的图片类型。 */
export function isImageType(mediaType: string): boolean {
  return IMAGE_TYPES.includes(mediaType.toLowerCase());
}

/** 该类型的体积上限。 */
export function limitFor(mediaType: string): number {
  return isImageType(mediaType) ? MAX_IMAGE_BYTES : MAX_FILE_BYTES;
}

/** 人类可读的体积。 */
export function formatSize(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B';
  if (bytes >= 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  if (bytes >= 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${bytes} B`;
}

/** 体积上限文案（用于提示）。 */
export function limitLabel(mediaType: string): string {
  return isImageType(mediaType) ? '10 MB' : '20 MB';
}

/**
 * 校验一个待上传附件。
 *
 * 返回空串表示可以上传；否则是给用户看的一句话。
 */
export function attachmentProblem(name: string, mediaType: string, size: number): string {
  if (name.trim().length === 0) return '文件名不能为空';
  if (!Number.isFinite(size) || size <= 0) return '文件是空的';
  const limit = limitFor(mediaType);
  if (size > limit) {
    return `${isImageType(mediaType) ? '图片' : '文件'}最大 ${limitLabel(mediaType)}，当前 ${formatSize(size)}`;
  }
  return '';
}

/** 还能不能再加附件。 */
export function canAddMore(existing: PendingAttachment[]): boolean {
  return existing.length < MAX_ATTACHMENTS;
}

/** 加不进去时的说明。 */
export function addBlockedReason(existing: PendingAttachment[]): string {
  if (canAddMore(existing)) return '';
  return `一条消息最多 ${MAX_ATTACHMENTS} 个附件`;
}

/** 全部附件都上传成功后才能发送。 */
export function allUploaded(list: PendingAttachment[]): boolean {
  for (let i = 0; i < list.length; i++) {
    if (list[i].receiptId === undefined || list[i].receiptId === '') return false;
    if (list[i].error !== undefined && list[i].error !== '') return false;
  }
  return true;
}

/** 正在上传的数量（用于禁用发送）。 */
export function uploadingCount(list: PendingAttachment[]): number {
  let count = 0;
  for (let i = 0; i < list.length; i++) {
    if (list[i].receiptId === undefined || list[i].receiptId === '') count += 1;
  }
  return count;
}

/** 从文件名推断 mediaType（宿主只认白名单里的图片类型，其它一律按二进制文件）。 */
export function mediaTypeOf(fileName: string): string {
  const lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.txt') || lower.endsWith('.md')) return 'text/plain';
  if (lower.endsWith('.json')) return 'application/json';
  return 'application/octet-stream';
}

/** 去掉路径，只留文件名（相册/文件选择器给的是完整 uri）。 */
export function baseName(path: string): string {
  const cleaned = path.split('?')[0];
  const index = Math.max(cleaned.lastIndexOf('/'), cleaned.lastIndexOf('\\'));
  const name = index >= 0 ? cleaned.substring(index + 1) : cleaned;
  return name.length === 0 ? 'file' : name;
}


// ---------------------------------------------------------------- 消息内附件

/** 取消息里的图片引用（保持原顺序）。 */
export function imagesOf(attachments: Attachment[] | undefined): Attachment[] {
  const images: Attachment[] = [];
  if (attachments === undefined) return images;
  for (let i = 0; i < attachments.length; i++) {
    if (attachments[i].type === 'image') images.push(attachments[i]);
  }
  return images;
}

/** 取消息里的文件引用（图片之外的都算文件）。 */
export function filesOf(attachments: Attachment[] | undefined): Attachment[] {
  const files: Attachment[] = [];
  if (attachments === undefined) return files;
  for (let i = 0; i < attachments.length; i++) {
    if (attachments[i].type !== 'image') files.push(attachments[i]);
  }
  return files;
}

/**
 * 图片展示尺寸：按**原始宽高比**缩放到给定宽度内，并限制最大高度。
 *
 * 为什么需要：占位框如果在图片加载完之前是 0 高，图片出现时会把整个消息列表
 * 顶得跳一下；预先算出尺寸就能稳定布局。
 * 没有宽高信息时按 4:3 兜底（相册照片最常见）。
 */
export interface DisplaySize {
  width: number;
  height: number;
}

export function fitImageSize(width: number | undefined, height: number | undefined,
  maxWidth: number, maxHeight: number): DisplaySize {
  const w = typeof width === 'number' && Number.isFinite(width) && width > 0 ? width : 0;
  const h = typeof height === 'number' && Number.isFinite(height) && height > 0 ? height : 0;
  // 没有尺寸信息：按 4:3 占位
  if (w === 0 || h === 0) {
    const fallback = maxWidth > 0 ? maxWidth : 200;
    return { width: fallback, height: Math.round(fallback * 0.75) };
  }
  const scale = Math.min(maxWidth / w, maxHeight / h, 1);
  return { width: Math.max(1, Math.round(w * scale)), height: Math.max(1, Math.round(h * scale)) };
}
