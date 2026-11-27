import { auth, DEV_PERSON_DOMAIN, devNewPersonEnabled } from "@/lib/auth";
import { NATIVE_USER_AGENT } from "@/lib/native-auth";

/**
 * Local development only: makes a brand-new person and signs the Debug Mac app in as them, so
 * first run can be tried again and again without a Google account each time. Answers 404 unless
 * `next dev` is running with DEV_NEW_PERSON=1 (see .env.development.local), and only to requests
 * made to this machine.
 *
 * Each person gets an address like new-1127-0932-k3@supervibes.test, which ALLOWED_EMAILS lets
 * through only while this is on. They live in whatever database local development points at,
 * which should be the Neon `dev` branch, not production.
 */

const FIRST_NAMES = ["Alex", "Sam", "Maya", "Leo", "Nora", "Iris", "Theo", "Ana"];

const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "[::1]"]);

export async function POST(request: Request) {
  if (!devNewPersonEnabled() || !LOCAL_HOSTS.has(new URL(request.url).hostname)) {
    return new Response("Not found", { status: 404 });
  }

  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  const stamp = `${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}`;
  const suffix = Math.random().toString(36).slice(2, 4);
  const email = `new-${stamp}-${suffix}@${DEV_PERSON_DOMAIN}`;
  const name = FIRST_NAMES[Math.floor(Math.random() * FIRST_NAMES.length)];

  try {
    const context = await auth.$context;
    const user = await context.internalAdapter.createUser({ email, name, emailVerified: true }, { method: "dev" });
    const session = await context.internalAdapter.createSession(user.id, false, { userAgent: NATIVE_USER_AGENT });
    console.info(`[dev] made ${email} (${name})`);
    return Response.json({ token: session.token, email, name }, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    console.error("[dev] couldn't make a new person", error);
    return Response.json({ error: { code: "failed", message: "Couldn't make a new person." } }, { status: 500 });
  }
}
