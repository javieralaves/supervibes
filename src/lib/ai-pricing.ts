/*
 * Claude API prices, in dollars per million tokens, for the models Supervibes
 * calls or can fall back to. Cache writes are the 5-minute TTL rate (1.25x
 * input); Supervibes doesn't set a longer TTL. Check these against
 * https://platform.claude.com/docs/en/about-claude/pricing when models or prices
 * change: costs are worked out when a call is recorded, from the raw token
 * counts, which are kept so they can be recomputed.
 * Last checked: 2026-11-18.
 */

type Rates = { input: number; output: number; cacheRead: number; cacheWrite: number };

const PRICES: Record<string, Rates> = {
  // The model every feature uses.
  "claude-sonnet-5-5": { input: 2, output: 10, cacheRead: 0.1, cacheWrite: 2.5 },
  // Where "fallbacks: default" can send a declined Sonnet 5.5 request. Cache reads are 0.1x input.
  "claude-sonnet-5": { input: 2, output: 10, cacheRead: 0.2, cacheWrite: 2.5 },
  "claude-opus-5-5": { input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5 },
};

export type TokenCounts = { input: number; output: number; cacheRead: number; cacheWrite: number };

/** Cost in millionths of a dollar, or null for a model without a known price. */
export function costMicros(model: string, tokens: TokenCounts): number | null {
  const rates = PRICES[model];
  if (!rates) return null;
  // Rates are per million tokens, so dollars-per-MTok × tokens = micro-dollars.
  return Math.round(
    tokens.input * rates.input +
      tokens.output * rates.output +
      tokens.cacheRead * rates.cacheRead +
      tokens.cacheWrite * rates.cacheWrite,
  );
}
