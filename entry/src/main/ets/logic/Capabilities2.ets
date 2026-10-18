import { PluginBundle, PluginEntry, SkillItem, SkillsPage } from '../model/Models';

/**
 * 工具与技能的**纯逻辑**（P2-8）。
 *
 * 处理三件容易出错的判断：
 * 1. 技能是否**可被用户查看全文**（宿主只允许 `userInvocable`）；
 * 2. 技能/插件的可读摘要与状态文案；
 * 3. 插件开关是否可操作（只读主机 / 宿主标记 readOnlyReason 的要禁用）。
 *
 * 抽出来的原因：这些是"点了报错"或"开关置灰判断错"的地方，必须能脱离设备验证。
 */

/** 技能按来源分组（同来源排在一起更易读）。 */
export interface SkillGroup {
  source: string;
  skills: SkillItem[];
}

/** 来源展示名（未收录的原样显示）。 */
export function sourceLabel(source: string | undefined): string {
  if (source === undefined || source.length === 0) return '其它';
  if (source === 'runtime') return '运行时';
  if (source === 'workspace') return '工作区';
  if (source === 'user') return '用户';
  if (source === 'bundled') return '内置';
  return source;
}

/** 按 source 分组，保持原顺序。 */
export function groupSkills(skills: SkillItem[] | undefined): SkillGroup[] {
  const groups: SkillGroup[] = [];
  if (skills === undefined) return groups;
  for (let i = 0; i < skills.length; i++) {
    const skill = skills[i];
    const source = sourceLabel(skill.source);
    let target: SkillGroup | undefined;
    for (let j = 0; j < groups.length; j++) {
      if (groups[j].source === source) {
        target = groups[j];
        break;
      }
    }
    if (target === undefined) {
      const created: SkillGroup = { source: source, skills: [] };
      groups.push(created);
      target = created;
    }
    target.skills.push(skill);
  }
  return groups;
}

/** 技能能否被用户查看全文（宿主 `skills-get` 的硬条件）。 */
export function canOpenSkill(skill: SkillItem): boolean {
  const invocation = skill.invocation;
  if (invocation === undefined) return false;
  return invocation.userInvocable === true;
}

/** 调用方式文案：模型可调 / 仅用户点名 / 两者都可。 */
export function describeInvocation(skill: SkillItem): string {
  const invocation = skill.invocation;
  const model = invocation !== undefined && invocation.modelInvocable === true;
  const user = invocation !== undefined && invocation.userInvocable === true;
  if (model && user) return '模型与用户都可调用';
  if (model) return '仅模型可调用';
  if (user) return '仅用户点名';
  return '不可调用';
}

/** 技能是否需要在界面上提示「不可查看」。 */
export function describeSkillBadge(skill: SkillItem): string {
  if (canOpenSkill(skill)) return '';
  return '不可查看';
}

/** 主机没装技能服务时的空态文案。 */
export function skillsEmptyText(page: SkillsPage): string {
  if (page.available === false) return '主机未启用技能服务。';
  return '没有可用的技能。';
}

/** 插件是否可切换（只读主机 / 宿主锁定 / 必需插件都不能动）。 */
export function canTogglePlugin(entry: PluginEntry, writable: boolean): boolean {
  if (!writable) return false;
  return entry.readOnlyReason === undefined || entry.readOnlyReason.length === 0;
}

/** 插件包是否可切换（额外要求已安装）。 */
export function canToggleBundle(bundle: PluginBundle, writable: boolean): boolean {
  if (!writable) return false;
  if (bundle.installed === false) return false;
  return bundle.readOnlyReason === undefined || bundle.readOnlyReason.length === 0;
}

/** 插件行的显示名：优先模块名，回退 entryId。 */
export function pluginLabel(entry: PluginEntry): string {
  if (entry.moduleName !== undefined && entry.moduleName.length > 0) return entry.moduleName;
  return entry.entryId;
}

/** 插件状态文案。 */
export function pluginStatus(entry: PluginEntry): string {
  if (entry.readOnlyReason !== undefined && entry.readOnlyReason.length > 0) {
    return entry.readOnlyReason === 'mobile-required' ? '手机连接必需，不可修改' : '主机保护，不可修改';
  }
  if (entry.enabled === true) return '已启用';
  return '已停用';
}

/** 插件包状态文案。 */
export function bundleStatus(bundle: PluginBundle): string {
  if (bundle.readOnlyReason !== undefined && bundle.readOnlyReason.length > 0) {
    return '主机保护，不可修改';
  }
  if (bundle.installed === false) return '未安装';
  if (bundle.enabled === true) return '已启用';
  return '已停用';
}

/** 只读主机提示。 */
export function readOnlyNotice(writable: boolean | undefined): string {
  return writable === false ? '主机处于只读状态，插件不能修改。' : '';
}
