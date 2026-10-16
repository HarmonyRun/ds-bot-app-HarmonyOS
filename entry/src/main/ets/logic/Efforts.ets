/**
 * `efforts` action 结果的防御性投影。
 *
 * 为什么需要这个模块：
 * 主机对 `efforts { ref }` 的应答形状不一定含 `efforts` 字段（不同模型、
 * 不同主机版本、或模型不支持推理档位时可能返回空对象）。如果直接把
 * `result.efforts` 写进 `@State effortOptions`，状态会变成 `undefined`，
 * 而渲染路径里 `this.effortOptions.length` 会在下一次重渲染时抛出
 * `TypeError: Cannot read property length of undefined`，**整个应用崩溃**。
 *
 * 这不是假设：2026-10-16 用受控模拟主机（返回 `{"ok":true}`）在 API 24 模拟器上
 * 复现了该崩溃，故障日志 `jscrash-app.dsbot.harmony-*.log` 精确指向
 * `Index.ets:2272`（`this.effortOptions.length`）。
 *
 * 约定：所有来自主机的动态对象都应经过一次「显式投影 + 类型校验」再进入 UI 状态，
 * 与 `logic/Questions.ets` 的 `toQuestions()`、`logic/GroupProgress.ets` 的
 * `toTeamWork()` 保持一致。
 */
import { EffortOption } from '../service/Wire';

/** `efforts` action 的原始应答（字段都可能缺失）。 */
export interface EffortResult {
  efforts?: object[];
  defaultEffort?: string;
}

/**
 * 把原始应答投影成强类型列表。
 * - 非字符串或空字符串的 `id` 会被丢弃（档位必须有 id 才能写回主机）
 * - `name` 缺失时回退到 id，保证 UI 一定有可读文案
 * - 任何异常形状（undefined / null / 非数组）都返回空数组，绝不返回 undefined
 */
export function toEffortOptions(value: object | undefined): EffortOption[] {
  if (value === undefined || value === null) return [];
  const source = value as Record<string, Object>;
  const raw = source['efforts'];
  if (!Array.isArray(raw)) return [];
  const items = raw as Object[];
  const result: EffortOption[] = [];
  for (const item of items) {
    if (item === null || item === undefined || typeof item !== 'object') continue;
    const entry = item as Record<string, Object>;
    const id = entry['id'];
    if (typeof id !== 'string' || id.length === 0) continue;
    const name = entry['name'];
    const description = entry['description'];
    const option: EffortOption = {
      id: id,
      name: typeof name === 'string' && name.length > 0 ? name : id
    };
    if (typeof description === 'string' && description.length > 0) option.description = description;
    result.push(option);
  }
  return result;
}

/** 应答里的默认档位（仅当是非空字符串时有效）。 */
export function toDefaultEffort(value: object | undefined): string {
  if (value === undefined || value === null) return '';
  const source = value as Record<string, Object>;
  const value0 = source['defaultEffort'];
  return typeof value0 === 'string' ? value0 : '';
}
