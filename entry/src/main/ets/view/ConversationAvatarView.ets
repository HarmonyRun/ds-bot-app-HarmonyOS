import { Bot, Conversation, TeamState } from '../model/Models';
import { BotAvatar, AvatarSpec } from './BotAvatar';
import { BotAvatarView } from './BotAvatarView';
import {
  botOf, isMainAvatar, memberSlotCount, memberSlotOffset, memberSlotSize, roomMembersOf
} from '../logic/ConversationAvatar';

/**
 * 会话头像（单聊 = Bot 头像；群聊 = 最多 4 个成员叠加）。抽自 `Index.ets`。
 *
 * 为什么做成组件：会话头像在「手机首页 / 桌面会话列表 / 聊天标题」多处出现，
 * 之前 `conversationAvatar` 是 `Index` 的私有 Builder，抽页面时每个调用方都得自己实现一遍——
 * 而真机上已经因为「两份头像实现只改了一份」踩过一次坑（见 P1 报告 §8.3）。
 *
 * 本组件直接消费 `logic/ConversationAvatar.ets` 的纯函数（已有单测覆盖），
 * 因此叠加布局算法只有一处、且可测。
 */
@Component
export struct ConversationAvatar {
  @Prop item: Conversation = { id: '', kind: 'bot', name: '', sessionId: '' };
  @Prop team: TeamState = { bots: [], rooms: [], models: [] };
  /** 头像外框边长（vp）。 */
  @Prop avatarSize: number = 50;
  @Prop dark: boolean = false;

  private specFor(bot: Bot | undefined, fallbackName: string, main: boolean, live: boolean): AvatarSpec {
    return {
      shape: bot?.avatar?.shape ?? '',
      color: bot?.avatar?.color ?? bot?.color ?? '',
      image: '',
      main: main,
      live: live
    };
  }

  build() {
    if (this.item.kind === 'room') {
      this.roomStack();
    } else {
      BotAvatar({
        spec: this.specFor(
          botOf(this.team, this.item),
          this.item.name,
          isMainAvatar(this.team, this.item),
          this.item.waiting !== undefined && this.item.waiting.length > 0
        ),
        avatarSize: this.avatarSize,
        dark: this.dark
      });
    }
  }

  /** 群聊：底色圆 + 最多 4 个成员矢量头像叠加。 */
  @Builder
  private roomStack() {
    Stack() {
      Circle({ width: this.avatarSize, height: this.avatarSize })
        .fill(this.dark ? '#2B2E39' : '#F0F1F4');
      ForEach(roomMembersOf(this.team, this.item).slice(0, memberSlotCount(this.team, this.item)),
        (bot: Bot, index: number) => {
          BotAvatarView({
            shape: bot.avatar?.shape ?? '',
            color: bot.avatar?.color ?? bot.color ?? '',
            avatarSize: memberSlotSize(this.team, this.item, this.avatarSize),
            image: ''
          })
            .position({
              x: memberSlotOffset(this.team, this.item, index, this.avatarSize).x,
              y: memberSlotOffset(this.team, this.item, index, this.avatarSize).y
            });
        }, (bot: Bot) => `member:${bot.id}`);
    }
    .width(this.avatarSize).height(this.avatarSize);
  }
}
