export interface SkillLike {
  name?: string;
  description?: string;
  origin?: string;
  dir?: string;
  version?: string;
  source?: string;
}

export interface SkillCategory<T extends SkillLike = SkillLike> {
  name?: string;
  skills?: T[];
}

export function filterCategories<T extends SkillLike>(
  categories: SkillCategory<T>[] | null | undefined,
  query: unknown,
): Array<{ name?: string; skills: T[] }> {
  const cats = Array.isArray(categories) ? categories : [];
  const needle = String(query == null ? "" : query).trim().toLowerCase();
  if (!needle) return cats.slice() as Array<{ name?: string; skills: T[] }>;
  const result: Array<{ name?: string; skills: T[] }> = [];
  for (const category of cats) {
    const skills = (category.skills || []).filter((skill) => {
      const haystack = `${skill.name || ""} ${skill.description || ""}`.toLowerCase();
      return haystack.includes(needle);
    });
    if (skills.length) result.push({ name: category.name, skills });
  }
  return result;
}

export function groupByOrigin<T extends SkillLike>(skills: T[] | null | undefined): Array<{ name: string; skills: T[] }> {
  const grouped: Record<string, T[]> = {};
  for (const skill of skills || []) {
    const origin = skill.origin || "agent";
    (grouped[origin] ||= []).push(skill);
  }
  return Object.keys(grouped).sort().map((name) => ({ name, skills: grouped[name]! }));
}
