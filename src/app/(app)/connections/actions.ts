"use server";

import { refresh } from "next/cache";

import { deleteConnection } from "@/lib/connections";
import { isProvider } from "@/lib/providers";
import { requireUser } from "@/lib/session";

export async function disconnectAction(provider: unknown) {
  const user = await requireUser();
  if (typeof provider !== "string" || !isProvider(provider)) return;
  await deleteConnection(user.id, provider);
  refresh();
}
