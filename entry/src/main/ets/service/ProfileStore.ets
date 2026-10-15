import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ClientProfile, Session } from '../model/Models';

const STORE_NAME = 'ds_bot_harmony_profile';

export class ProfileStore {
  static async load(context: common.UIAbilityContext): Promise<ClientProfile | undefined> {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    const raw = await store.get('profile', '') as string;
    if (raw.length === 0) return undefined;
    try {
      const value = JSON.parse(raw) as ClientProfile;
      if (value.serverUrl.length === 0 || value.session.accessToken.length === 0) return undefined;
      return value;
    } catch (_error) {
      return undefined;
    }
  }

  static async save(context: common.UIAbilityContext, profile: ClientProfile): Promise<void> {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    await store.put('profile', JSON.stringify(profile));
    await store.flush();
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
  }
}
