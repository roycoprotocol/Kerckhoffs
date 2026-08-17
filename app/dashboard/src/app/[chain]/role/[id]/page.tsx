import { redirect } from "next/navigation";

// Legacy pre-dual-AM URL — every historical role link was a Dawn AM role.
export default async function LegacyRoleRedirect({ params }: { params: Promise<{ chain: string; id: string }> }) {
  const { chain, id } = await params;
  redirect(`/${chain}/am/dawn/role/${id}`);
}
