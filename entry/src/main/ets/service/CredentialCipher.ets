import { huks } from '@kit.UniversalKeystoreKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { packCipher, unpackCipher } from '../logic/CredentialCodec';

/**
 * 用 **HUKS（鸿蒙密钥库）** 加密配对凭据。
 *
 * ## 为什么需要它（P0-10）
 *
 * 配对成功后，`ClientProfile` 里的 `accessToken` / `refreshToken` 是访问主机的凭证。
 * 早期实现把整个 profile 以 `JSON.stringify` **明文**存进 `preferences`——
 * 凡是能读到应用沙箱的进程/备份都能拿到令牌。改为：
 *
 * - 在 HUKS 里生成**不可导出的 AES-256-GCM 密钥**（`huks.generateKeyItem`），
 *   私钥材料永不出 TEE；
 * - 凭据用该密钥加密后只存密文（格式见 `logic/CredentialCodec.ets`）；
 * - 每次加密使用**随机 IV**（GCM 要求 nonce 唯一，复用会致命）。
 *
 * ## 为什么用会话式 API
 *
 * 当前 SDK 的 HUKS 只提供 `initSession` → `finishSession`（没有 `encryptItem`）。
 * GCM 的 nonce 通过 `HUKS_TAG_NONCE` 在 session 参数里传入。
 */

/** HUKS 中保存凭据加密密钥的别名。 */
const KEY_ALIAS = 'ds_bot_harmony_profile_key_v1';

const LOG_DOMAIN = 0xD5B0;
const LOG_TAG = 'CredentialCipher';

/** AES-GCM 推荐 IV 长度（字节）。 */
const IV_LENGTH = 12;
/** AES-GCM 认证标签长度（字节）。加密输出末尾即该标签。 */
const AE_TAG_LENGTH = 16;

/** 构造生成密钥用的参数：AES-256，允许加解密。 */
function generateOptions(): huks.HuksOptions {
  const properties: huks.HuksParam[] = [
    { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
    { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
    {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
    },
    { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
    { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE }
  ];
  return { properties: properties };
}

/**
 * 构造一次加/解密会话的参数。
 *
 * **必须有 `HUKS_TAG_PURPOSE`**：生成密钥时它只声明「密钥允许哪些用途」，
 * 每次会话仍要显式指明本次是加密还是解密。缺失时 HUKS 返回
 * `401 Invalid parameters`（2026-10-17 真机踩到）。
 * GCM 还需要 `HUKS_TAG_ASSOCIATED_DATA`（可为空）。
 */
function sessionOptions(iv: Uint8Array, purpose: number): huks.HuksOptions {
  const properties: huks.HuksParam[] = [
    { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
    { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
    { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
    { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
    { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
    { tag: huks.HuksTag.HUKS_TAG_NONCE, value: iv }
  ];
  return { properties: properties };
}

/**
 * 生成随机 IV。
 *
 * 用系统密码学随机数（`cryptoFramework.createRandom()`），
 * 不用 `Math.random()`——后者不是 CSPRNG，用来做 GCM nonce 会严重削弱安全性。
 */
function randomIv(): Uint8Array {
  const blob = cryptoFramework.createRandom().generateRandomSync(IV_LENGTH);
  return new Uint8Array(blob.data);
}

function base64(bytes: Uint8Array): string {
  return new util.Base64Helper().encodeToStringSync(bytes, util.Type.BASIC);
}

function fromBase64(text: string): Uint8Array {
  return new util.Base64Helper().decodeSync(text, util.Type.BASIC);
}

/**
 * 确保 HUKS 里存在本工程的凭据密钥（幂等）。
 *
 * 注意：部分 SDK 版本的 `isKeyItemExist` 在**密钥不存在**时**抛 12000011
 * （HUKS_ERROR_NOT_EXIST）而不是返回 false**（2026-10-17 真机实测）。
 * 因此这里不能直接 `if (!exists) generate`，必须把异常也当成「不存在」处理。
 */
async function ensureKey(): Promise<void> {
  let exists = false;
  try {
    exists = await huks.isKeyItemExist(KEY_ALIAS, generateOptions());
    hilog.info(LOG_DOMAIN, LOG_TAG, `isKeyItemExist = ${exists}`);
  } catch (error) {
    const code = (error as BusinessError).code;
    hilog.warn(LOG_DOMAIN, LOG_TAG, `isKeyItemExist 抛异常 code=${code}，按「不存在」处理`);
    exists = false;
  }
  if (exists) return;
  try {
    await huks.generateKeyItem(KEY_ALIAS, generateOptions());
    hilog.info(LOG_DOMAIN, LOG_TAG, 'HUKS 密钥已生成');
  } catch (error) {
    const code = (error as BusinessError).code;
    // 12000011：并发下已被其它调用生成，视为成功
    if (code === 12000011) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'HUKS 密钥已由并发调用生成');
      return;
    }
    hilog.error(LOG_DOMAIN, LOG_TAG, `generateKeyItem 失败 code=${code}`);
    throw error as Error;
  }
}

/**
 * 加密一段明文，返回可直接存入 preferences 的字符串。
 */
export async function encryptCredential(plain: string): Promise<string> {
  try {
    await ensureKey();
  } catch (error) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `生成 HUKS 密钥失败: ${JSON.stringify(error)}`);
    throw error as Error;
  }
  const iv = randomIv();
  const sessionOptionsValue = sessionOptions(iv, huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT);
  let session: huks.HuksSessionHandle;
  try {
    session = await huks.initSession(KEY_ALIAS, sessionOptionsValue);
  } catch (error) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `initSession(加密) 失败: ${JSON.stringify(error)}`);
    throw error as Error;
  }
  try {
    // **数据必须放 `options.inData`**：`finishSession` 的第三个参数是「精炼密钥访问控制」
    // 的鉴权 token，不是待处理数据。放错会得到 `401 Invalid parameters`
    // （2026-10-17 真机踩到）。
    const plainBytes = new Uint8Array(new util.TextEncoder().encodeInto(plain));
    const options: huks.HuksOptions = {
      properties: sessionOptionsValue.properties,
      inData: plainBytes
    };
    let result: huks.HuksReturnResult;
    try {
      result = await huks.finishSession(session.handle, options);
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, `finishSession(加密) 失败: ${JSON.stringify(error)}`);
      throw error as Error;
    }
    const outData = result.outData;
    if (outData === undefined || outData.length === 0) {
      throw new Error('HUKS 加密未返回数据');
    }
    return packCipher(base64(iv), base64(new Uint8Array(outData)));
  } finally {
    // 会话无论成功失败都要收尾，避免 HUKS 资源泄漏
    try {
      await huks.abortSession(session.handle, sessionOptionsValue);
    } catch (_error) {
      // 正常完成时 abort 可能报错，忽略即可
    }
  }
}

/**
 * 解密。返回 `undefined` 表示**无法解密**（格式不对或密钥已失效），
 * 调用方应引导用户重新配对，而不是崩溃。
 */
export async function decryptCredential(payload: string): Promise<string | undefined> {
  const unpacked = unpackCipher(payload);
  if (unpacked === undefined) return undefined;
  try {
    const exists = await huks.isKeyItemExist(KEY_ALIAS, generateOptions());
    if (!exists) return undefined;
    const iv = fromBase64(unpacked.ivBase64);
    const sessionOptionsValue = sessionOptions(iv, huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT);
    // GCM 解密：加密输出的**最后 16 字节是认证标签（AE tag）**，
    // 必须单独通过 `HUKS_TAG_AE_TAG` 传入，`inData` 只放去掉标签的密文。
    // 否则 initSession 报 `401 The parameter does not exist`（2026-10-17 真机踩到）。
    const allBytes = fromBase64(unpacked.dataBase64);
    if (allBytes.length <= AE_TAG_LENGTH) {
      hilog.error(LOG_DOMAIN, LOG_TAG, `密文过短（${allBytes.length} 字节），无法拆出 AE tag`);
      return undefined;
    }
    const cipherBytes = allBytes.subarray(0, allBytes.length - AE_TAG_LENGTH);
    const tagBytes = allBytes.subarray(allBytes.length - AE_TAG_LENGTH);
    const decryptProperties: huks.HuksParam[] = sessionOptionsValue.properties ?? [];
    decryptProperties.push({ tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: tagBytes });
    const session = await huks.initSession(KEY_ALIAS, sessionOptionsValue);
    try {
      const options: huks.HuksOptions = {
        properties: decryptProperties,
        inData: cipherBytes
      };
      const result = await huks.finishSession(session.handle, options);
      const outData = result.outData;
      if (outData === undefined || outData.length === 0) return undefined;
      return new util.TextDecoder().decodeToString(new Uint8Array(outData));
    } finally {
      try {
        await huks.abortSession(session.handle, sessionOptionsValue);
      } catch (_error) {
        // 同上
      }
    }
  } catch (error) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `解密失败: ${JSON.stringify(error)}`);
    return undefined;
  }
}

/** 删除凭据密钥（退出配对时调用，确保旧密文无法再解）。 */
export async function deleteCredentialKey(): Promise<void> {
  try {
    await huks.deleteKeyItem(KEY_ALIAS, generateOptions());
  } catch (_error) {
    // 密钥本就不存在时忽略
  }
}

/**
 * **自检**：用真实 HUKS 跑一次加密→解密往返，并确认密文与明文不同。
 *
 * 为什么需要它：HUKS 的参数错误（缺 `PURPOSE`、数据放到鉴权 token 而非 `inData` 等）
 * 在编译期完全看不出来，只有真机运行才暴露。这个自检让「加密是否真的工作」
 * 变成一次可观测的日志，而不是等用户升级后发现凭据读不出来。
 *
 * 返回 `true` 表示加解密链路正常。
 */
export async function selfTestCredentialCipher(): Promise<boolean> {
  const sample = '{"probe":"凭据加密自检","n":42}';
  try {
    const encrypted = await encryptCredential(sample);
    if (encrypted === sample) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '自检失败：密文与明文相同');
      return false;
    }
    const decrypted = await decryptCredential(encrypted);
    if (decrypted !== sample) {
      hilog.error(LOG_DOMAIN, LOG_TAG, `自检失败：解密结果与原文不一致 (${decrypted ?? 'undefined'})`);
      return false;
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, `自检通过：密文长度 ${encrypted.length}，往返一致`);
    return true;
  } catch (error) {
    hilog.error(LOG_DOMAIN, LOG_TAG, `自检异常: ${JSON.stringify(error)}`);
    return false;
  }
}
