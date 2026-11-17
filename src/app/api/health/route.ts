import { sql } from "drizzle-orm";
import { connection } from "next/server";

import { db } from "@/db";

export async function GET() {
  await connection();

  try {
    await db.execute(sql`select 1`);
    return Response.json({ ok: true, database: "up" });
  } catch {
    return Response.json({ ok: false, database: "down" }, { status: 503 });
  }
}
