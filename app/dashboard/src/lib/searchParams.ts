export type SearchParams = Record<string, string | string[] | undefined>;

export function param(sp: SearchParams, key: string): string {
  const v = sp[key];
  return (Array.isArray(v) ? v[0] : v) ?? "";
}
export function boolParam(sp: SearchParams, key: string): boolean {
  return param(sp, key) === "1" || param(sp, key) === "true";
}
export function includesCI(haystack: string, needle: string): boolean {
  return haystack.toLowerCase().includes(needle.trim().toLowerCase());
}
