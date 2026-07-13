import { redirect } from "next/navigation";
import { DEFAULT_CHAIN } from "@/config/chains";

export default function Home() {
  redirect(`/${DEFAULT_CHAIN.slug}`);
}
