import { connection } from "next/server";

import { api } from "@/lib/api/app";

/** Every /api/v1 request goes to the Hono app in lib/api/app.ts. Never prerendered. */
async function handle(request: Request): Promise<Response> {
  await connection();
  return api.fetch(request);
}

export { handle as GET, handle as POST, handle as PUT, handle as PATCH, handle as DELETE };
