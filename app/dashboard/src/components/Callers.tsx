// "Who can call this?" — the active holders of a function's required role, rendered as labeled
// address chips. The data comes from ONE roles query per AM (fetchAllRoles already selects active
// members), never per-function queries.
import { AddressLabel } from "@/components/AddressLabel";
import { fmtDelay } from "@/lib/format";

export const PUBLIC_ROLE_ID = "18446744073709551615";

export interface Caller {
  address: string;
  delay: number;
}

// roleId → active holders map from a fetchAllRoles result.
export function holdersByRole(
  roles: { roleId: string; members: { account: { id: string }; executionDelay: string; active: boolean }[] }[],
): Map<string, Caller[]> {
  return new Map(
    roles.map((r) => [
      r.roleId,
      r.members.filter((m) => m.active).map((m) => ({ address: m.account.id, delay: Number(m.executionDelay) })),
    ]),
  );
}

export function Callers({
  chainId,
  slug,
  roleId,
  callers,
}: {
  chainId: number;
  slug: string;
  roleId: string;
  callers: Caller[] | undefined;
}) {
  if (roleId === PUBLIC_ROLE_ID) return <span className="text-xs text-ok">anyone</span>;
  if (!callers?.length) return <span className="text-xs text-muted">no active holders</span>;
  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
      {callers.map((c) => (
        <span key={c.address} className="inline-flex items-center gap-1 whitespace-nowrap">
          <AddressLabel chainId={chainId} slug={slug} address={c.address} className="text-[12.5px]" />
          {c.delay > 0 && <span className="font-mono text-[10.5px] text-muted">{fmtDelay(c.delay)}</span>}
        </span>
      ))}
    </div>
  );
}
