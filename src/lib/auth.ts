import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { APIError } from "better-auth/api";
import { nextCookies } from "better-auth/next-js";
import { bearer } from "better-auth/plugins/bearer";
import { oneTimeToken } from "better-auth/plugins/one-time-token";

import { db } from "@/db";
import * as schema from "@/db/schema";

/**
 * Comma-separated list of emails allowed to sign up, from ALLOWED_EMAILS.
 * Empty or unset means nobody can create an account (fail closed).
 */
function allowedEmails(): Set<string> {
  return new Set(
    (process.env.ALLOWED_EMAILS ?? "")
      .split(",")
      .map((email) => email.trim().toLowerCase())
      .filter(Boolean),
  );
}

export function isEmailAllowed(email: string | null | undefined): boolean {
  return !!email && allowedEmails().has(email.toLowerCase());
}

// BETTER_AUTH_SECRET and BETTER_AUTH_URL are read from the environment.
export const auth = betterAuth({
  database: drizzleAdapter(db, { provider: "pg", schema }),
  socialProviders: {
    google: {
      clientId: process.env.GOOGLE_CLIENT_ID as string,
      clientSecret: process.env.GOOGLE_CLIENT_SECRET as string,
      prompt: "select_account",
    },
  },
  databaseHooks: {
    user: {
      create: {
        before: async (user) => {
          if (!isEmailAllowed(user.email)) {
            throw new APIError("FORBIDDEN", {
              message: "This account isn't on the access list.",
            });
          }
          return { data: user };
        },
      },
    },
  },
  // Long enough that the Mac app rarely asks to sign in again; each use pushes it out by a day.
  session: {
    expiresIn: 60 * 60 * 24 * 60,
    updateAge: 60 * 60 * 24,
  },
  plugins: [
    // The Mac app sends its session as `Authorization: Bearer <token>`.
    bearer(),
    // Short-lived, single-use tokens that hand a session from the browser to the Mac app
    // (see /api/native/*). Stored hashed, so a database read can't replay one.
    oneTimeToken({ storeToken: "hashed" }),
    // Must stay last so cookies set in server actions reach the browser.
    nextCookies(),
  ],
});

export type Session = typeof auth.$Infer.Session;
