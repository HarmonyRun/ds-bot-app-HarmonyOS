import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Message } from '../model/Models';

/**
 * 本机消息缓存与草稿存储（P0-7）。
 *
 * 存储介质：`preferences`（键值 JSON）。
 * 之所以先不用 `relationalStore`（RDB）：P0 的目标是「冷启动立即有内容 + 草稿不丢」，
 * 单会话 200 条上限的 JSON 足够；等 P1 引入跨会话搜索与分页时再迁移到 RDB，
 * 迁移点集中在 `MessageCache` 内部，界面层不受影响（见 docs/translation-plan.md D3）。
 *
 * 键约定（按 serverId 分区，换主机互不污染）：
 * - `msg:<serverId>:<conversationId>`  → `Message[]`（最多 `MESSAGE_LIMIT` 条，按 seq 升序）
 * - `draft:<serverId>:<conversationId>` → `string`
 */
const STORE_NAME = 'ds_bot_harmony_cache';
const MESSAGE_LIMIT = 200;

export class MessageCache {
  private store?: preferences.Preferences;
  private readonly serverId: string;

  constructor(serverId: string) {
    this.serverId = serverId;
  }

  private async open(context: common.UIAbilityContext): Promise<preferences.Preferences> {
    if (this.store === undefined) {
      this.store = await preferences.getPreferences(context, { name: STORE_NAME });
    }
    return this.store;
  }

  private messageKey(conversationId: string): string {
    return `msg:${this.serverId}:${conversationId}`;
  }

  private draftKey(conversationId: string): string {
    return `draft:${this.serverId}:${conversationId}`;
  }

  /** 读取缓存消息；解析失败按空处理，不抛出。 */
  async messages(context: common.UIAbilityContext, conversationId: string): Promise<Message[]> {
    try {
      const store = await this.open(context);
      const raw = await store.get(this.messageKey(conversationId), '') as string;
      if (raw.length === 0) return [];
      const parsed = JSON.parse(raw) as Message[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (_error) {
      return [];
    }
  }

  /** 写入缓存消息；只保留最后 `MESSAGE_LIMIT` 条。 */
  async saveMessages(context: common.UIAbilityContext, conversationId: string, messages: Message[]): Promise<void> {
    try {
      const store = await this.open(context);
      const tail = messages.length > MESSAGE_LIMIT ? messages.slice(messages.length - MESSAGE_LIMIT) : messages;
      await store.put(this.messageKey(conversationId), JSON.stringify(tail));
      await store.flush();
    } catch (_error) {
      // 缓存失败不影响主流程。
    }
  }

  /** 读取草稿。 */
  async draft(context: common.UIAbilityContext, conversationId: string): Promise<string> {
    try {
      const store = await this.open(context);
      return await store.get(this.draftKey(conversationId), '') as string;
    } catch (_error) {
      return '';
    }
  }

  /** 写入草稿；空字符串表示清除。 */
  async saveDraft(context: common.UIAbilityContext, conversationId: string, text: string): Promise<void> {
    try {
      const store = await this.open(context);
      if (text.length === 0) {
        await store.delete(this.draftKey(conversationId));
      } else {
        await store.put(this.draftKey(conversationId), text);
      }
      await store.flush();
    } catch (_error) {
      // 草稿写失败不阻断发送。
    }
  }

  /** 清空本机的消息与草稿（登出时调用）。 */
  async clear(context: common.UIAbilityContext): Promise<void> {
    try {
      const store = await this.open(context);
      const all = await store.getAll();
      const keys = Object.keys(all);
      for (const key of keys) {
        if (key.startsWith('msg:') || key.startsWith('draft:')) {
          await store.delete(key);
        }
      }
      await store.flush();
    } catch (_error) {
      // 忽略。
    }
  }
}
