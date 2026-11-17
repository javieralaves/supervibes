"use client";

import { ArrowDown01Icon, Moon02Icon, Sun03Icon, Tick02Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon, type IconSvgElement } from "@hugeicons/react";
import { useId, useState, useTransition } from "react";

import { formatTime, useClock } from "@/lib/clock";
import { awakeMinutes, TIME_STEP, type Clock, type Settings } from "@/lib/settings-schema";

import { saveSettingsAction } from "./actions";

type Section = "sleep" | "clock";

const TIMES = Array.from({ length: (24 * 60) / TIME_STEP }, (_, i) => i * TIME_STEP);

function hoursLabel(minutes: number) {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return m ? `${h} hr ${m} min` : `${h} hr`;
}

/** Settings save as soon as they change; each card shows its own "Saved". */
export function SettingsForm({ initial }: { initial: Settings }) {
  const [settings, setSettings] = useState(initial);
  const [saving, startSaving] = useTransition();
  const [status, setStatus] = useState<{ section: Section; error?: string } | null>(null);
  const clock = useClock(settings.clock);

  function update(section: Section, patch: Partial<Settings>) {
    const next = { ...settings, ...patch };
    setSettings(next);
    if (next.sleepStart === next.wakeTime) {
      setStatus({ section, error: "Bedtime and wake-up time can't be the same." });
      return;
    }
    setStatus(null);
    startSaving(async () => {
      const result = await saveSettingsAction(next);
      setStatus(result.ok ? { section } : { section, error: result.error });
    });
  }

  const statusFor = (section: Section) =>
    status?.section === section ? (
      status.error ? (
        <span role="alert" className="text-xs font-medium text-red-600 dark:text-red-400">
          {status.error}
        </span>
      ) : (
        <span className="flex items-center gap-1 text-xs font-medium text-muted" aria-live="polite">
          {saving ? (
            "Saving…"
          ) : (
            <>
              <HugeiconsIcon icon={Tick02Icon} size={13} />
              Saved
            </>
          )}
        </span>
      )
    ) : null;

  const awake = awakeMinutes(settings);

  return (
    <div className="grid gap-3">
      <Card
        title="Sleep schedule"
        description="Suggestions on your calendar only go in your awake hours."
        status={statusFor("sleep")}
      >
        <div className="grid gap-3 sm:grid-cols-2">
          <TimeSelect
            label="Bedtime"
            icon={Moon02Icon}
            value={settings.sleepStart}
            clock={clock}
            onChange={(sleepStart) => update("sleep", { sleepStart })}
          />
          <TimeSelect
            label="Wake up"
            icon={Sun03Icon}
            value={settings.wakeTime}
            clock={clock}
            onChange={(wakeTime) => update("sleep", { wakeTime })}
          />
        </div>
        {awake > 0 && (
          <p className="mt-3 text-sm text-muted">
            You&apos;re awake {hoursLabel(awake)} a day, from {formatTime(settings.wakeTime, clock)} to{" "}
            {formatTime(settings.sleepStart, clock)}.
          </p>
        )}
      </Card>

      <Card title="Clock" description="How times show across Supervibes." status={statusFor("clock")}>
        <div role="radiogroup" aria-label="Clock" className="inline-grid grid-cols-2 gap-1 rounded-xl bg-wash p-1">
          {(
            [
              ["12h", "12-hour", formatTime(14 * 60 + 30, "12h")],
              ["24h", "24-hour", formatTime(14 * 60 + 30, "24h")],
            ] as [Clock, string, string][]
          ).map(([value, label, example]) => {
            const selected = clock === value;
            return (
              <button
                key={value}
                type="button"
                role="radio"
                aria-checked={selected}
                onClick={() => update("clock", { clock: value })}
                className={`flex h-10 items-center justify-center gap-2 rounded-lg px-4 text-sm font-medium transition-colors ${
                  selected
                    ? "bg-card text-foreground shadow-[0_1px_2px_rgb(15_17_20/0.08)]"
                    : "text-muted hover:text-foreground"
                }`}
              >
                {label}
                <span className="tabular-nums text-muted">{example}</span>
              </button>
            );
          })}
        </div>
        {settings.clock === null && (
          <p className="mt-3 text-sm text-muted">Following your device for now.</p>
        )}
      </Card>
    </div>
  );
}

function Card({
  title,
  description,
  status,
  children,
}: {
  title: string;
  description: string;
  status: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section className="rounded-2xl border border-card-border bg-card p-5 sm:p-6">
      <div className="mb-5 flex items-start justify-between gap-4">
        <div>
          <h2 className="font-semibold tracking-[-0.01em] text-foreground">{title}</h2>
          <p className="mt-0.5 text-sm text-muted">{description}</p>
        </div>
        <div className="shrink-0 pt-0.5">{status}</div>
      </div>
      {children}
    </section>
  );
}

function TimeSelect({
  label,
  icon,
  value,
  clock,
  onChange,
}: {
  label: string;
  icon: IconSvgElement;
  value: number;
  clock: Clock;
  onChange: (minutes: number) => void;
}) {
  const id = useId();
  return (
    <div>
      <label htmlFor={id} className="mb-1.5 flex items-center gap-1.5 text-xs font-medium text-muted">
        <HugeiconsIcon icon={icon} size={14} />
        {label}
      </label>
      <div className="relative">
        <select
          id={id}
          value={value}
          onChange={(e) => onChange(Number(e.target.value))}
          className="h-11 w-full appearance-none rounded-xl border border-card-border bg-card pl-3.5 pr-10 text-[0.95rem] tabular-nums text-foreground shadow-[0_1px_2px_rgb(15_17_20/0.05)] outline-none transition-colors hover:border-line-strong focus-visible:border-line-strong focus-visible:shadow-[0_0_0_4px_color-mix(in_oklab,var(--foreground)_6%,transparent)]"
        >
          {TIMES.map((m) => (
            <option key={m} value={m}>
              {formatTime(m, clock)}
            </option>
          ))}
        </select>
        <HugeiconsIcon
          icon={ArrowDown01Icon}
          size={16}
          className="pointer-events-none absolute right-3.5 top-1/2 -translate-y-1/2 text-muted"
        />
      </div>
    </div>
  );
}
