import { notificationManager } from '@kit.NotificationKit';
import { NotificationItem } from '../model/Models';
import { kindLabel } from '../logic/Notifications';

/**
 * 本地系统通知（P3-4）。
 *
 * 为什么是「本地」而不是推送：鸿蒙的系统推送需要 HMS Push 与 AGC 配置，
 * 本工程没有；而宿主 inbox 里的通知只要我们知道就能**在设备上自己弹一条**。
 * 所以这里用 `notificationManager.publish` 发本地通知，
 * 数据来源仍是主机的 `notifications-list`（App 在前台轮询时发现新通知就弹）。
 *
 * 通知 id 必须落在 [1, 2^31-1]，这里把主机上的递增 id 直接映射过去。
 */

/** 一条通知最多显示的正文长度（系统横幅会截断，先自己截避免奇怪换行）。 */
const MAX_BODY = 120;

export class LocalNotify {
  /** 是否已请求过权限（避免每次弹都请求）。 */
  private static requested: boolean = false;

  /**
   * 请求通知授权。
   *
   * 用户可能拒绝；拒绝后 publish 会失败但不抛到界面，所以这里只返回是否成功，
   * 由调用方决定是否提示。
   */
  static async requestPermission(): Promise<boolean> {
    if (LocalNotify.requested) return true;
    LocalNotify.requested = true;
    try {
      await notificationManager.requestEnableNotification();
      return true;
    } catch (_error) {
      return false;
    }
  }

  /** 弹一条本地通知。失败静默（通知不是关键路径）。 */
  static async publish(item: NotificationItem): Promise<void> {
    const body = item.body !== undefined && item.body.length > 0
      ? item.body.substring(0, MAX_BODY) : kindLabel(item.kind);
    try {
      await notificationManager.publish({
        id: item.id,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: item.title,
            text: body
          }
        }
      });
    } catch (_error) {
      // 通知被拒或系统限制：不影响主流程
    }
  }

  /** 撤销一条通知（已读后从通知栏消失）。 */
  static cancel(id: number): void {
    try {
      notificationManager.cancel(id);
    } catch (_error) {
      // 忽略
    }
  }
}
