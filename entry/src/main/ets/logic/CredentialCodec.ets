/**
 * 凭据密文的打包格式（纯逻辑，可单测）。
 *
 * HUKS 只负责加解密，**存储格式**单独放在这里，原因：
 * - 格式一旦写进用户设备就改不动，需要有版本前缀；
 * - 打包/解包与「是否加密」的判定是纯字符串运算，可以脱离设备做单元测试
 *   （HUKS 只能在真机/模拟器上跑，测试成本高）。
 *
 * 格式：`v1:<iv 的 base64>:<密文的 base64>`
 * - `v1` 为版本前缀，便于将来换算法或换 IV 长度；
 * - 用 `:` 分隔（base64 字母表不含 `:`，因此不会歧义）。
 */

/** 当前密文格式版本。 */
export const CIPHER_VERSION = 'v1';

/** 版本前缀（含分隔符） */
const PREFIX = `${CIPHER_VERSION}:`;

/** 打包：把 IV 与密文的 base64 拼成一条可存 preferences 的字符串。 */
export function packCipher(ivBase64: string, dataBase64: string): string {
  if (ivBase64.length === 0 || dataBase64.length === 0) {
    throw new Error('密文打包失败：IV 或密文为空');
  }
  return `${PREFIX}${ivBase64}:${dataBase64}`;
}

/**
 * 判断一条存储值是否是本工程的加密载荷。
 *
 * 用于 `ProfileStore` 的**旧数据迁移**：早期版本存的是明文 JSON（以 `{` 开头），
 * 升级后首次读取要能识别出来并转成密文。
 */
export function isEncryptedPayload(text: string): boolean {
  if (!text.startsWith(PREFIX)) return false;
  const parts = text.substring(PREFIX.length).split(':');
  return parts.length === 2 && parts[0].length > 0 && parts[1].length > 0;
}

/** 解包结果（IV 与密文的 base64）。 */
export interface UnpackedCipher {
  ivBase64: string;
  dataBase64: string;
}

/**
 * 解包。格式不合法返回 `undefined`（调用方应视为「无法解密」并引导重新配对，
 * 不要抛异常把上层流程打断）。
 */
export function unpackCipher(text: string): UnpackedCipher | undefined {
  if (!isEncryptedPayload(text)) return undefined;
  const parts = text.substring(PREFIX.length).split(':');
  return { ivBase64: parts[0], dataBase64: parts[1] };
}

/**
 * 判断一条存储值是否是**旧版明文**凭据。
 *
 * 旧版直接把 `JSON.stringify(profile)` 写进 preferences，因此以 `{` 开头。
 * 迁移时需要识别它，读出来加密后再删掉明文。
 */
export function isLegacyPlaintext(text: string): boolean {
  const trimmed = text.trim();
  return trimmed.startsWith('{') && !isEncryptedPayload(trimmed);
}
