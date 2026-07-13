import { redirect } from "next/navigation";

// Unified into /[chain]/address/[addr]; keep this path working.
export default async function AccountRedirect({ params }: { params: Promise<{ chain: string; address: string }> }) {
  const { chain, address } = await params;
  redirect(`/${chain}/address/${address}`);
}
