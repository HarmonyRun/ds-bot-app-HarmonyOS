import { Connector } from '../model/Models';

/**
 * 连接器的**纯逻辑**（工具与技能）。
 *
 * 宿主只有 GitHub 一个连接器（`connectors.js`），状态机是：
 * `off → connecting → ready`，失败进入 `error`（带 `error` 文案）；
 * `connector-connect` 需要一个 **token**（个人访问令牌），`disconnect` 会删掉保存的密钥。
 *
 * 抽出来的原因：状态文案与"能不能点"的判断错了，用户会看到空白徽标或点了没反应的按钮。
 */

/** 状态展示文案。 */
export function stateLabel(connector: Connector): string {
  const state = connector.state;
  if (state === 'ready') {
    return connector.account !== undefined && connector.account !== null && connector.account.length > 0
      ? `已连接 · ${connector.account}` : '已连接';
  }
  if (state === 'connecting') return '连接中…';
  if (state === 'error') return '连接失败';
  return '未连接';
}

/** 状态色（成功/警示/次要）。 */
export function stateColor(connector: Connector, tokens: ConnectorColors): string {
  if (connector.state === 'ready') return tokens.success;
  if (connector.state === 'error') return tokens.danger;
  if (connector.state === 'connecting') return tokens.warning;
  return tokens.muted;
}

/** 是否已连接。 */
export function isConnected(connector: Connector): boolean {
  return connector.state === 'ready';
}

/** 连接中不允许重复操作。 */
export function isBusy(connector: Connector): boolean {
  return connector.state === 'connecting';
}

/** 主操作按钮文案：未连接→连接，失败→重试，已连接→断开。 */
export function actionLabel(connector: Connector): string {
  if (connector.state === 'ready') return '断开';
  if (connector.state === 'error') return '重试';
  if (connector.state === 'connecting') return '连接中';
  return '连接';
}

/** 主操作需要 token 吗（只有"未连接/失败"且要新建连接时才需要）。 */
export function needsToken(connector: Connector): boolean {
  return connector.state === 'off';
}

/** token 校验：空/过长都不提交。 */
export function tokenProblem(token: string): string {
  const trimmed = token.trim();
  if (trimmed.length === 0) return '请粘贴访问令牌';
  if (trimmed.length > 512) return '令牌过长，请检查是否粘贴错了内容';
  return '';
}

/** 依赖注入的三色（避免逻辑层硬编码十六进制）。 */
export interface ConnectorColors {
  success: string;
  danger: string;
  warning: string;
  muted: string;
}
