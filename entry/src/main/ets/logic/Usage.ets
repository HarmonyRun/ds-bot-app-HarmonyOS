import { UsagePage } from '../model/Models';

/**
 * 用量数据的**纯逻辑**还原与聚合（P2-2）。
 *
 * 主机把用量压成扁平行 `[hour, ownerIndex, modelIndex, kindIndex, input, cacheRead, cacheWrite, output, calls]`，
 * 这里负责按索引还原成可读结构，并按时间窗口聚合。
 *
 * 为什么单独抽出来：这些是可脱离设备验证的纯函数，
 * 而「主机返回的行格式」一旦理解错，面板上的数字就全错——必须有测试兜住。
 */

/** 一个归属者的用量汇总。 */
export interface UsageOwnerTotal {
  name: string;
  input: number;
  cacheRead: number;
  cacheWrite: number;
  output: number;
  calls: number;
  /** 输入+输出（不含缓存），用于排名与展示 */
  total: number;
}

/** 一个模型的用量汇总。 */
export interface UsageModelTotal {
  name: string;
  input: number;
  cacheRead: number;
  cacheWrite: number;
  output: number;
  calls: number;
  total: number;
}

/** 面板展示用的汇总结果。 */
export interface UsageSummary {
  input: number;
  cacheRead: number;
  cacheWrite: number;
  output: number;
  calls: number;
  /** input + output（不含缓存读/写），这是用户最关心的"花了多少" */
  total: number;
  /** 按输入+输出降序 */
  owners: UsageOwnerTotal[];
  /** 按输入+输出降序 */
  models: UsageModelTotal[];
  /** 是否有任何数据 */
  empty: boolean;
}

/** 时间窗口（小时）。`all` 表示不裁剪。 */
export type UsageWindow = '24h' | '7d' | '30d' | 'all';

/** 窗口对应的小时数。 */
export function windowHours(window: UsageWindow): number {
  if (window === '24h') return 24;
  if (window === '7d') return 24 * 7;
  if (window === '30d') return 24 * 30;
  return 0;
}

/** 取行里的第 index 个数字，缺失/非法时返回 0（防止主机返回残缺行导致 NaN 铺满 UI）。 */
function cell(row: number[], index: number): number {
  const value = row[index];
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

/** 取字典里的名字，缺失时给一个稳定占位（不要显示 `undefined`）。 */
function nameAt(names: string[], index: number, fallback: string): string {
  const value = names[index];
  return typeof value === 'string' && value.length > 0 ? value : fallback;
}

function emptySummary(): UsageSummary {
  return {
    input: 0, cacheRead: 0, cacheWrite: 0, output: 0, calls: 0, total: 0,
    owners: [], models: [], empty: true
  };
}

/**
 * 把 `UsagePage` 聚合成展示用汇总。
 *
 * @param page 主机返回的原始结构（字段可能缺失，全部按"没有数据"处理）
 * @param window 时间窗口；`all` 不裁剪
 */
export function summarizeUsage(page: UsagePage, window: UsageWindow): UsageSummary {
  const rows = page.rows;
  if (rows === undefined || rows.length === 0) return emptySummary();

  const ownerNames: string[] = [];
  const owners = page.owners ?? [];
  for (let i = 0; i < owners.length; i++) {
    const owner = owners[i];
    const name = owner.name !== undefined && owner.name.length > 0
      ? owner.name
      : (owner.owner !== undefined && owner.owner.length > 0 ? owner.owner : `#${i}`);
    ownerNames.push(name);
  }

  const modelNames: string[] = [];
  const models = page.models ?? [];
  for (let i = 0; i < models.length; i++) {
    const model = models[i];
    const name = model.name !== undefined && model.name.length > 0
      ? model.name
      : (model.model !== undefined && model.model.length > 0 ? model.model : `#${i}`);
    modelNames.push(name);
  }

  const nowHour = page.now;
  const hours = windowHours(window);
  const hasNow = typeof nowHour === 'number' && Number.isFinite(nowHour);
  // 没有 now 时无法裁剪时间窗口：保守地全部统计，而不是错误地清空
  const cutoff = hasNow && hours > 0 ? (nowHour as number) - hours : Number.NEGATIVE_INFINITY;

  let input = 0;
  let cacheRead = 0;
  let cacheWrite = 0;
  let output = 0;
  let calls = 0;
  const ownerTotals = new Map<string, UsageOwnerTotal>();
  const modelTotals = new Map<string, UsageModelTotal>();

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    if (row === undefined || row.length < 9) continue;
    const hour = cell(row, 0);
    if (hour < cutoff) continue;
    const ownerName = nameAt(ownerNames, cell(row, 1), '未归属');
    const modelName = nameAt(modelNames, cell(row, 2), '未知模型');
    const rowInput = cell(row, 4);
    const rowCacheRead = cell(row, 5);
    const rowCacheWrite = cell(row, 6);
    const rowOutput = cell(row, 7);
    const rowCalls = cell(row, 8);

    input += rowInput;
    cacheRead += rowCacheRead;
    cacheWrite += rowCacheWrite;
    output += rowOutput;
    calls += rowCalls;

    const owner = ownerTotals.get(ownerName) ?? {
      name: ownerName, input: 0, cacheRead: 0, cacheWrite: 0, output: 0, calls: 0, total: 0
    };
    owner.input += rowInput;
    owner.cacheRead += rowCacheRead;
    owner.cacheWrite += rowCacheWrite;
    owner.output += rowOutput;
    owner.calls += rowCalls;
    owner.total = owner.input + owner.output;
    ownerTotals.set(ownerName, owner);

    const model = modelTotals.get(modelName) ?? {
      name: modelName, input: 0, cacheRead: 0, cacheWrite: 0, output: 0, calls: 0, total: 0
    };
    model.input += rowInput;
    model.cacheRead += rowCacheRead;
    model.cacheWrite += rowCacheWrite;
    model.output += rowOutput;
    model.calls += rowCalls;
    model.total = model.input + model.output;
    modelTotals.set(modelName, model);
  }

  const ownerList: UsageOwnerTotal[] = [];
  ownerTotals.forEach((value: UsageOwnerTotal) => {
    ownerList.push(value);
  });
  ownerList.sort((a: UsageOwnerTotal, b: UsageOwnerTotal): number => b.total - a.total);

  const modelList: UsageModelTotal[] = [];
  modelTotals.forEach((value: UsageModelTotal) => {
    modelList.push(value);
  });
  modelList.sort((a: UsageModelTotal, b: UsageModelTotal): number => b.total - a.total);

  return {
    input: input, cacheRead: cacheRead, cacheWrite: cacheWrite, output: output,
    calls: calls, total: input + output,
    owners: ownerList, models: modelList,
    empty: calls === 0 && input === 0 && output === 0
  };
}

/** 把 token 数格式化成紧凑文本（1.2k / 3.4M）。 */
export function formatTokens(value: number): string {
  if (!Number.isFinite(value) || value <= 0) return '0';
  if (value >= 1000000) return `${(value / 1000000).toFixed(1)}M`;
  if (value >= 1000) return `${(value / 1000).toFixed(1)}k`;
  return `${Math.round(value)}`;
}

/** 条形图占比（0~1），用于排行里的横条宽度。 */
export function barRatio(value: number, max: number): number {
  if (!Number.isFinite(value) || !Number.isFinite(max) || max <= 0) return 0;
  const ratio = value / max;
  return ratio > 1 ? 1 : ratio;
}
