/**
 * ArrayBuffer → base64（P3-1 反馈：头像与 data URL）。
 *
 * ArkTS 的 `util.Base64Helper` 只吃 `Uint8Array`，这里做一层薄封装，
 * 顺便保证**不使用 `btoa`**（ArkTS 没有 Web 的 btoa/atob）。
 */
import { util } from '@kit.ArkTS';

/** 把 ArrayBuffer 编码成 base64 字符串。 */
export function toBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  const helper = new util.Base64Helper();
  return helper.encodeToStringSync(bytes);
}
