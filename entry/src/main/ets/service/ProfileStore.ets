import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ClientProfile, Session } from '../model/Models';
import { isEncryptedPayload, isLegacyPlaintext } from '../logic/CredentialCodec';
import { decryptCredential, encryptCredential, deleteCredentialKey } from './CredentialCipher';

const STORE_NAME = 'ds_bot_harmony_profile';

const LOG_DOMAIN = 0xD5B0;
const LOG_TAG = 'ProfileStore';

/** 加密载荷的键（新格式）。 */
const KEY_PROFILE_ENC = 'profile_enc';
/** 旧版明文键。**只读不写**：仅用于一次性迁移，迁移后立即删除。 */
const KEY_PROFILE_LEGACY = 'profile';

/**
 * 配对凭据的持久化。
 *
 * ## 存储方式（P0-10）
 *
 * 凭据（含 `accessToken` / `refreshToken`）经 HUKS AES-256-GCM 加密后
 * 以 `profile_enc` 存储；密钥材料在 TEE 内不可导出。
 *
 * ## 旧数据迁移
 *
 * 早期版本把 profile **明文**写在 `profile` 键下。升级后首次 `load()` 会：
 * 1. 先读加密键；
 * 2. 读不到时回退读旧明文键，识别为明文后**加密重存**，然后删除明文键。
 *
 * 这样用户不需要重新配对，且明文不会一直留在设备上。
 */
export class ProfileStore {
  static async load(context: common.UIAbilityContext): Promise<ClientProfile | undefined> {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });

    const encrypted = await store.get(KEY_PROFILE_ENC, '') as string;
    if (encrypted.length > 0 && isEncryptedPayload(encrypted)) {
      const plain = await decryptCredential(encrypted);
      // 解不开（密钥被清、设备迁移等）→ 当作未配对，引导重新配对
      if (plain === undefined) return undefined;
      return ProfileStore.parse(plain);
    }

    // 回退：旧版明文 → 迁移
    const legacy = await store.get(KEY_PROFILE_LEGACY, '') as string;
    if (legacy.length > 0 && isLegacyPlaintext(legacy)) {
      const profile = ProfileStore.parse(legacy);
      if (profile !== undefined) {
        // 迁移失败不应影响本次启动：能读到就先用，下次再试
        try {
          await ProfileStore.write(store, profile);
          hilog.info(LOG_DOMAIN, LOG_TAG, '旧明文凭据已迁移为 HUKS 密文并删除明文');
        } catch (error) {
          // 迁移失败不影响本次启动，但必须留痕：否则会像之前一样「以为加密了，其实还是明文」
          hilog.error(LOG_DOMAIN, LOG_TAG, `旧明文凭据迁移失败: ${JSON.stringify(error)}`);
        }
      }
      return profile;
    }

    return undefined;
  }

  static async save(context: common.UIAbilityContext, profile: ClientProfile): Promise<void> {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    await ProfileStore.write(store, profile);
  }

  static async updateSession(context: common.UIAbilityContext, session: Session): Promise<void> {
    const current = await ProfileStore.load(context);
    if (current === undefined) return;
    current.session = session;
    await ProfileStore.save(context, current);
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    await store.clear();
    await store.flush();
    // 一并删掉 HUKS 密钥：旧密文即使残留也无法再解
    await deleteCredentialKey();
  }

  /** 解析并校验 profile 结构；不合法返回 undefined。 */
  private static parse(raw: string): ClientProfile | undefined {
    try {
      const value = JSON.parse(raw) as ClientProfile;
      if (value.serverUrl.length === 0 || value.session.accessToken.length === 0) return undefined;
      return value;
    } catch (_error) {
      return undefined;
    }
  }

  /** 加密写入并清掉旧明文键。 */
  private static async write(store: preferences.Preferences, profile: ClientProfile): Promise<void> {
    const encrypted = await encryptCredential(JSON.stringify(profile));
    // 写前自校验：确认落盘的就是密文（防「以为加密了、实际仍写明文」的回归）
    if (!isEncryptedPayload(encrypted)) {
      throw new Error('凭据加密结果格式非法，已中止写入');
    }
    await store.put(KEY_PROFILE_ENC, encrypted);
    // 迁移场景：删掉明文，避免它一直留在设备上
    await store.delete(KEY_PROFILE_LEGACY);
    await store.flush();
    // 回读校验：确认存储里确实没有明文残留
    const readBack = await store.get(KEY_PROFILE_ENC, '') as string;
    const legacyLeft = await store.get(KEY_PROFILE_LEGACY, '') as string;
    if (legacyLeft.length > 0) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '写入后仍有旧明文键残留');
    }
    hilog.info(LOG_DOMAIN, LOG_TAG,
      `凭据已加密写入（${readBack.length} 字符），明文残留=${legacyLeft.length > 0}`);
  }
}
