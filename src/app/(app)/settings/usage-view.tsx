"use client";

import { useMemo, useState, useSyncExternalStore } from "react";

import type { AiCallView, AiFeature, AiTrigger } from "@/lib/ai-usage";

/*
 * What Supervibes' Claude calls cost over the last 30 days: totals, spend per
 * day by feature, a table per feature and trigger, per goal, and recent calls.
 * Costs are estimates from token counts and the prices in src/lib/ai-pricing.ts.
 */

// Classes, not inline var() colors: Tailwind only keeps the --viz-* variables a utility uses.
const FEATURES: { key: AiFeature; label: string; color: string }[] = [
  { key: "progress_read", label: "Progress reads", color: "bg-viz-1" },
  { key: "recap", label: "Session recaps", color: "bg-viz-2" },
  { key: "agenda", label: "Agendas", color: "bg-viz-3" },
];
const FEATURE_LABEL = Object.fromEntries(FEATURES.map((f) => [f.key, f.label])) as Record<AiFeature, string>;

const TRIGGER_LABEL: Record<AiTrigger, string> = {
  manual: "Update status",
  note: "After a note",
  recap: "After a recap",
  cron: "Daily read",
  draft: "First draft",
  redraft: "Drafted again",
  auto: "After a session",
};

const DAYS = 30;

function money(n: number | null) {
  if (n === null) return "–";
  if (n === 0) return "$0";
  if (n < 0.01) return `$${n.toFixed(4)}`;
  if (n < 1) return `$${n.toFixed(3)}`;
  return `$${n.toFixed(2)}`;
}

function tokens(n: number) {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
  return String(Math.round(n));
}

function seconds(ms: number) {
  return `${(ms / 1000).toFixed(ms < 10_000 ? 1 : 0)}s`;
}

const sum = (xs: number[]) => xs.reduce((a, b) => a + b, 0);
const costOf = (calls: AiCallView[]) => sum(calls.map((c) => c.cost ?? 0));

/** A local calendar day, "YYYY-MM-DD". */
function dayKey(d: Date) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/* Days and times are the viewer's local ones, which the server can't know, so they wait for the browser. */
const noop = () => () => {};
const useToday = () => useSyncExternalStore(noop, () => dayKey(new Date()), () => null);

export function UsageView({ calls }: { calls: AiCallView[] }) {
  const today = useToday();
  const total = costOf(calls);
  const unpriced = calls.filter((c) => c.cost === null).length;

  if (calls.length === 0) {
    return (
      <Card>
        <p className="text-sm leading-relaxed text-muted">
          No Claude calls recorded yet. They appear here after the next progress read, session recap or agenda.
        </p>
      </Card>
    );
  }

  return (
    <div className="grid gap-3">
      <Card>
        <div className="grid grid-cols-2 gap-x-4 gap-y-5 sm:grid-cols-4">
          <Stat label="Spent" value={money(total)} hint={`last ${DAYS} days`} />
          <Stat label="Calls" value={String(calls.length)} />
          <Stat label="Average call" value={money(total / calls.length)} />
          <Stat
            label="Tokens"
            value={`${tokens(sum(calls.map((c) => c.inputTokens)))} in`}
            hint={`${tokens(sum(calls.map((c) => c.outputTokens)))} out`}
          />
        </div>
        {unpriced > 0 && (
          <p className="mt-4 text-xs text-muted">
            {unpriced} call{unpriced === 1 ? "" : "s"} used a model without a known price and aren&rsquo;t in the totals.
          </p>
        )}
        <div className="mt-6">{today ? <DailyChart calls={calls} today={today} /> : <div className="h-[188px]" />}</div>
      </Card>

      <ByFeature calls={calls} />
      <ByGoal calls={calls} />
      <RecentCalls calls={calls} ready={today !== null} />
    </div>
  );
}

function Card({ title, children }: { title?: string; children: React.ReactNode }) {
  return (
    // min-w-0: as a grid item it would otherwise grow to its widest table instead of scrolling it.
    <section className="min-w-0 rounded-2xl border border-card-border bg-card p-5 sm:p-6">
      {title && <h3 className="mb-3 text-sm font-semibold text-foreground">{title}</h3>}
      {children}
    </section>
  );
}

function Stat({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div>
      <p className="text-xs text-muted">{label}</p>
      <p className="mt-1 text-xl font-semibold tabular-nums tracking-[-0.02em] text-foreground">{value}</p>
      {hint && <p className="text-xs tabular-nums text-muted">{hint}</p>}
    </div>
  );
}

const CHART_H = 160;

/** Spend per day, stacked by feature in fixed order (reads at the base). */
function DailyChart({ calls, today }: { calls: AiCallView[]; today: string }) {
  const [hovered, setHovered] = useState<number | null>(null);

  const days = useMemo(() => {
    const [y, m, d] = today.split("-").map(Number);
    const list = Array.from({ length: DAYS }, (_, i) => {
      const date = new Date(y, m - 1, d - (DAYS - 1 - i));
      return { key: dayKey(date), date, byFeature: new Map<AiFeature, { cost: number; calls: number }>() };
    });
    const index = new Map(list.map((day, i) => [day.key, i]));
    for (const call of calls) {
      const i = index.get(dayKey(new Date(call.createdAt)));
      if (i === undefined) continue;
      const slot = list[i].byFeature.get(call.feature) ?? { cost: 0, calls: 0 };
      slot.cost += call.cost ?? 0;
      slot.calls += 1;
      list[i].byFeature.set(call.feature, slot);
    }
    return list;
  }, [calls, today]);

  const totals = days.map((day) => sum([...day.byFeature.values()].map((s) => s.cost)));
  const max = Math.max(...totals, 0.0001);
  // A round top for the scale, so gridlines land on readable values.
  const step = niceStep(max / 3);
  const top = Math.max(step * Math.ceil(max / step), step);
  const lines = [0, 1, 2, 3].map((i) => (top / 3) * i).filter((v) => v <= top + 1e-9);
  const dayLabel = (date: Date) => date.toLocaleDateString("en-US", { month: "short", day: "numeric" });
  const shown = hovered ?? null;

  return (
    <figure>
      <figcaption className="mb-3 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted">
        <span className="font-medium text-foreground">Spend per day</span>
        {FEATURES.map((f) => (
          <span key={f.key} className="flex items-center gap-1.5">
            <span aria-hidden="true" className={`h-2.5 w-2.5 rounded-[3px] ${f.color}`} />
            {f.label}
          </span>
        ))}
      </figcaption>

      <div className="relative flex gap-2">
        {/* Y axis: recessive gridline labels */}
        <div className="relative w-12 shrink-0" style={{ height: CHART_H }} aria-hidden="true">
          {lines.map((v) => (
            <span
              key={v}
              className="absolute right-0 -translate-y-1/2 text-[10px] tabular-nums text-muted"
              style={{ top: CHART_H - (v / top) * CHART_H }}
            >
              {money(v)}
            </span>
          ))}
        </div>

        <div className="relative min-w-0 flex-1" style={{ height: CHART_H }}>
          {lines.map((v) => (
            <div
              key={v}
              aria-hidden="true"
              className={`absolute inset-x-0 border-t ${v === 0 ? "border-line-strong" : "border-card-border"}`}
              style={{ top: CHART_H - (v / top) * CHART_H }}
            />
          ))}

          <ol className="absolute inset-0 flex items-end gap-[3px]" onMouseLeave={() => setHovered(null)}>
            {days.map((day, i) => {
              const parts = FEATURES.map((f) => ({ ...f, ...(day.byFeature.get(f.key) ?? { cost: 0, calls: 0 }) })).filter(
                (p) => p.cost > 0,
              );
              const label = `${dayLabel(day.date)}: ${money(totals[i])}${parts.length ? ` (${parts.map((p) => `${p.label} ${money(p.cost)}`).join(", ")})` : ""}`;
              return (
                // The whole column is the hit target, taller than the bar.
                <li
                  key={day.key}
                  tabIndex={0}
                  aria-label={label}
                  onMouseEnter={() => setHovered(i)}
                  onFocus={() => setHovered(i)}
                  onBlur={() => setHovered(null)}
                  className={`flex h-full min-w-0 flex-1 cursor-default flex-col-reverse rounded-[3px] outline-none focus-visible:ring-2 focus-visible:ring-foreground/30 ${
                    shown === i ? "bg-wash" : ""
                  }`}
                >
                  {/* Segments bottom-up in fixed order, 2px surface gaps between, only the top end rounded. */}
                  <div className="flex flex-col-reverse gap-[2px]" style={{ height: (totals[i] / top) * CHART_H }}>
                    {parts.map((p, j) => (
                      <div
                        key={p.key}
                        // Shares of the day's total: flex-grow values summing below 1 would leave the bar part-filled.
                        style={{ flexGrow: p.cost / totals[i], flexBasis: 0, minHeight: 1 }}
                        className={`${p.color} ${j === parts.length - 1 ? "rounded-t-[4px]" : ""}`}
                      />
                    ))}
                  </div>
                </li>
              );
            })}
          </ol>

          {shown !== null && (
            <Tooltip
              left={`${((shown + 0.5) / DAYS) * 100}%`}
              flip={shown > DAYS * 0.6}
              title={dayLabel(days[shown].date)}
              total={totals[shown]}
              rows={FEATURES.map((f) => ({ ...f, ...(days[shown].byFeature.get(f.key) ?? { cost: 0, calls: 0 }) }))}
            />
          )}
        </div>
      </div>

      <div className="mt-1.5 flex justify-between pl-14 text-[10px] tabular-nums text-muted" aria-hidden="true">
        <span>{dayLabel(days[0].date)}</span>
        <span>{dayLabel(days[Math.floor(DAYS / 2)].date)}</span>
        <span>Today</span>
      </div>
    </figure>
  );
}

function Tooltip({
  left,
  flip,
  title,
  total,
  rows,
}: {
  left: string;
  flip: boolean;
  title: string;
  total: number;
  rows: { key: string; label: string; color: string; cost: number; calls: number }[];
}) {
  return (
    <div
      role="status"
      className={`pointer-events-none absolute top-0 z-10 w-48 rounded-xl border border-card-border bg-card p-3 text-xs shadow-[0_8px_24px_rgb(15_17_20/0.12)] ${
        flip ? "-translate-x-[calc(100%+8px)]" : "translate-x-2"
      }`}
      style={{ left }}
    >
      <div className="flex items-baseline justify-between gap-2">
        <span className="font-semibold text-foreground">{title}</span>
        <span className="tabular-nums font-semibold text-foreground">{money(total)}</span>
      </div>
      <ul className="mt-2 space-y-1">
        {rows.map((r) => (
          <li key={r.key} className="flex items-center gap-1.5 text-muted">
            <span aria-hidden="true" className={`h-2 w-2 shrink-0 rounded-[2px] ${r.color}`} />
            <span className="min-w-0 flex-1 truncate">{r.label}</span>
            <span className="tabular-nums">
              {r.calls > 0 ? `${r.calls} · ${money(r.cost)}` : "–"}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}

/** 1, 2 or 5 times a power of ten, at or above `x`. */
function niceStep(x: number) {
  const power = 10 ** Math.floor(Math.log10(x));
  const n = x / power;
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * power;
}

const th = "py-2 pr-4 text-left text-xs font-medium text-muted last:pr-0";
const thNum = "py-2 pr-4 text-right text-xs font-medium text-muted last:pr-0";
const td = "py-2 pr-4 text-[13px] text-foreground last:pr-0";
const tdNum = "py-2 pr-4 text-right text-[13px] tabular-nums text-foreground last:pr-0";

/** Per feature and trigger: how often, how big, how much. Doubles as the chart's table view. */
function ByFeature({ calls }: { calls: AiCallView[] }) {
  const rows = FEATURES.flatMap((f) => {
    const mine = calls.filter((c) => c.feature === f.key);
    const triggers = [...new Set(mine.map((c) => c.trigger))];
    return triggers
      .map((t) => {
        const group = mine.filter((c) => c.trigger === t);
        const n = group.length;
        return {
          key: `${f.key}:${t}`,
          feature: f,
          trigger: TRIGGER_LABEL[t] ?? t,
          calls: n,
          avgIn: sum(group.map((c) => c.inputTokens)) / n,
          avgOut: sum(group.map((c) => c.outputTokens)) / n,
          avgTools: sum(group.map((c) => c.toolCalls)) / n,
          avgTime: sum(group.map((c) => c.durationMs)) / n,
          avgCost: costOf(group) / n,
          total: costOf(group),
        };
      })
      .sort((a, b) => b.total - a.total);
  });

  return (
    <Card title="By feature">
      <div className="-mx-1 overflow-x-auto px-1">
        <table className="w-full min-w-[620px] border-collapse">
          <thead>
            <tr className="border-b border-card-border">
              <th className={th}>Feature</th>
              <th className={thNum}>Calls</th>
              <th className={thNum}>Avg in</th>
              <th className={thNum}>Avg out</th>
              <th className={thNum}>Avg tools</th>
              <th className={thNum}>Avg time</th>
              <th className={thNum}>Avg cost</th>
              <th className={thNum}>Total</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.key} className="border-b border-card-border last:border-0">
                <td className={td}>
                  <span className="flex items-center gap-2">
                    <span aria-hidden="true" className={`h-2.5 w-2.5 shrink-0 rounded-[3px] ${r.feature.color}`} />
                    <span>
                      {r.feature.label}
                      <span className="text-muted"> · {r.trigger}</span>
                    </span>
                  </span>
                </td>
                <td className={tdNum}>{r.calls}</td>
                <td className={tdNum}>{tokens(r.avgIn)}</td>
                <td className={tdNum}>{tokens(r.avgOut)}</td>
                <td className={tdNum}>{r.avgTools.toFixed(1)}</td>
                <td className={tdNum}>{seconds(r.avgTime)}</td>
                <td className={tdNum}>{money(r.avgCost)}</td>
                <td className={`${tdNum} font-medium`}>{money(r.total)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  );
}

function ByGoal({ calls }: { calls: AiCallView[] }) {
  const groups = new Map<string, AiCallView[]>();
  for (const c of calls) {
    const key = c.goalTitle ?? "Deleted goals";
    groups.set(key, [...(groups.get(key) ?? []), c]);
  }
  const rows = [...groups.entries()]
    .map(([goal, group]) => ({ goal, calls: group.length, total: costOf(group) }))
    .sort((a, b) => b.total - a.total);

  return (
    <Card title="By goal">
      <table className="w-full border-collapse">
        <thead>
          <tr className="border-b border-card-border">
            <th className={th}>Goal</th>
            <th className={thNum}>Calls</th>
            <th className={thNum}>Total</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.goal} className="border-b border-card-border last:border-0">
              <td className={`${td} max-w-0 truncate`}>{r.goal}</td>
              <td className={`${tdNum} w-16`}>{r.calls}</td>
              <td className={`${tdNum} w-20 font-medium`}>{money(r.total)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </Card>
  );
}

function RecentCalls({ calls, ready }: { calls: AiCallView[]; ready: boolean }) {
  const recent = calls.slice(0, 25);
  const when = (iso: string) =>
    new Date(iso).toLocaleString("en-US", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });

  return (
    <Card title="Recent calls">
      <div className="-mx-1 overflow-x-auto px-1">
        <table className="w-full min-w-[680px] border-collapse">
          <thead>
            <tr className="border-b border-card-border">
              <th className={th}>When</th>
              <th className={th}>What</th>
              <th className={th}>Goal</th>
              <th className={thNum}>In</th>
              <th className={thNum}>Out</th>
              <th className={thNum}>Tools</th>
              <th className={thNum}>Time</th>
              <th className={thNum}>Cost</th>
            </tr>
          </thead>
          <tbody>
            {recent.map((c) => (
              <tr key={c.id} className="border-b border-card-border last:border-0">
                <td className={`${td} whitespace-nowrap tabular-nums text-muted`}>{ready ? when(c.createdAt) : ""}</td>
                <td className={`${td} whitespace-nowrap`}>
                  {FEATURE_LABEL[c.feature] ?? c.feature}
                  <span className="text-muted"> · {TRIGGER_LABEL[c.trigger] ?? c.trigger}</span>
                  {c.outcome !== "end_turn" && <span className="ml-1.5 text-xs text-muted">({c.outcome.replace(/_/g, " ")})</span>}
                </td>
                <td className={`${td} max-w-40 truncate text-muted`}>{c.goalTitle ?? "–"}</td>
                <td className={tdNum}>{tokens(c.inputTokens)}</td>
                <td className={tdNum}>{tokens(c.outputTokens)}</td>
                <td className={tdNum}>{c.toolCalls}</td>
                <td className={tdNum}>{seconds(c.durationMs)}</td>
                <td className={`${tdNum} font-medium`}>{money(c.cost)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  );
}
