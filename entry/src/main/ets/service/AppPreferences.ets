import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

const STORE_NAME = 'ds_bot_harmony_settings';
const LOG_DOMAIN = 0xD5B2;
const LOG_TAG = 'AppPreferences';

/**
 * 应用级偏好（P2-11）。
 *
 * ## 为什么要单独一层
 *
 * 之前 `dark` 只是 `Index` 里的一个 `@State`：**每次重启都回到浅色**。
 * 这类「用户显式设置过、期望保持」的状态必须落盘，否则每次启动都像丢了设置。
 *
 * ## 为什么不做成通用的键值包装
 *
 * ArkTS 对 `any` / 索引访问有限制，泛化包装会退化成一堆 `as` 断言。
 * 这里用**显式接口 + 显式字段**，新增偏好时改 `AppPreferences` 与两个函数即可，
 * 类型安全且可读。
 */
export interface AppPreferences {
  /** 深色模式 */
  dark: boolean;
}

/** 默认值：与首次安装的表现保持一致（浅色）。 */
export function defaultPreferences(): AppPreferences {
  return { dark: false };
}

/** 读取偏好；读不到或损坏时返回默认值（绝不因为偏好读失败而阻塞启动）。 */
export async function loadPreferences(context: common.UIAbilityContext): Promise<AppPreferences> {
  try {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    const dark = await store.get('dark', false) as boolean;
    return { dark: dark === true };
  } catch (error) {
    hilog.warn(LOG_DOMAIN, LOG_TAG, `读取偏好失败，使用默认值: ${JSON.stringify(error)}`);
    return defaultPreferences();
  }
}

/** 保存偏好（失败只记日志，不影响交互）。 */
export async function savePreferences(
  context: common.UIAbilityContext, value: AppPreferences): Promise<void> {
  try {
    const store = await preferences.getPreferences(context, { name: STORE_NAME });
    await store.put('dark', value.dark);
    await store.flush();
  } catch (error) {
    hilog.warn(LOG_DOMAIN, LOG_TAG, `保存偏好失败: ${JSON.stringify(error)}`);
  }
}
