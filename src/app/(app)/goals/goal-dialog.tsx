"use client";

import {
  Cancel01Icon,
  Delete02Icon,
  Search01Icon,
  Tick02Icon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";
import * as Dialog from "@radix-ui/react-dialog";
import { useMemo, useState } from "react";

import { GoalBadge } from "@/components/goal-badge";
import { GOAL_COLORS, GOAL_COLOR_KEYS, goalColorStyle, type GoalColor } from "@/lib/goal-colors";
import { GOAL_ICON_GROUPS, type GoalIconDef, type GoalIconName } from "@/lib/goal-icons";
import { goalInputSchema, MAX_GOAL_TITLE, type GoalInput } from "@/lib/goal-schema";

type Props = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  mode: "create" | "edit";
  initial: GoalInput;
  onSave: (input: GoalInput) => void;
  onDelete?: () => void;
};

export function GoalDialog({ open, onOpenChange, mode, initial, onSave, onDelete }: Props) {
  const [title, setTitle] = useState(initial.title);
  const [icon, setIcon] = useState<GoalIconName>(initial.icon);
  const [color, setColor] = useState<GoalColor>(initial.color);
  const [query, setQuery] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [confirmingDelete, setConfirmingDelete] = useState(false);

  const groups = useMemo(() => {
    const q = query.trim().toLowerCase();
    return GOAL_ICON_GROUPS.map((group) => ({
      label: group.label,
      icons: (Object.entries(group.icons) as [GoalIconName, GoalIconDef][]).filter(
        ([, def]) =>
          !q ||
          def.label.toLowerCase().includes(q) ||
          def.keywords.includes(q) ||
          group.label.toLowerCase().includes(q),
      ),
    })).filter((group) => group.icons.length > 0);
  }, [query]);

  function submit(event: React.FormEvent) {
    event.preventDefault();
    const parsed = goalInputSchema.safeParse({ title, icon, color });
    if (!parsed.success) {
      setError(parsed.error.issues[0]?.message ?? "Check the form.");
      return;
    }
    onSave(parsed.data);
  }

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-40 bg-black/40 data-[state=open]:animate-[fade-in_150ms_ease-out]" />
        <Dialog.Content
          aria-describedby={undefined}
          className="fixed inset-x-0 bottom-0 z-50 flex max-h-[92dvh] flex-col rounded-t-[28px] border border-card-border bg-background shadow-2xl outline-none data-[state=open]:animate-[sheet-in_220ms_cubic-bezier(0.2,0.7,0.2,1)] sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-1/2 sm:h-[min(640px,85dvh)] sm:max-h-none sm:w-[480px] sm:-translate-x-1/2 sm:-translate-y-1/2 sm:rounded-[20px] sm:data-[state=open]:animate-[pop-in_180ms_cubic-bezier(0.2,0.7,0.2,1)]"
        >
          <form onSubmit={submit} className="flex min-h-0 flex-1 flex-col">
            <div className="flex items-center justify-between px-6 pt-5">
              <Dialog.Title className="text-base font-semibold tracking-[-0.01em] text-foreground">
                {mode === "create" ? "New goal" : "Edit goal"}
              </Dialog.Title>
              <Dialog.Close
                aria-label="Close"
                className="-mr-2 flex h-9 w-9 items-center justify-center rounded-full text-muted transition-colors hover:bg-foreground/[.06] hover:text-foreground"
              >
                <HugeiconsIcon icon={Cancel01Icon} size={18} />
              </Dialog.Close>
            </div>

            {/* Live preview + title */}
            <div className="flex items-center gap-4 px-6 pb-5 pt-4">
              <GoalBadge icon={icon} color={color} size="lg" />
              <label className="min-w-0 flex-1">
                <span className="sr-only">Title</span>
                {/* Grows with the text; Enter saves instead of adding a new line. */}
                <textarea
                  autoFocus
                  rows={1}
                  value={title}
                  maxLength={MAX_GOAL_TITLE}
                  onChange={(e) => {
                    setTitle(e.target.value.replace(/\n/g, " "));
                    setError(null);
                  }}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && !e.nativeEvent.isComposing) {
                      e.preventDefault();
                      e.currentTarget.form?.requestSubmit();
                    }
                  }}
                  placeholder="What are you working toward?"
                  className="block max-h-32 w-full resize-none bg-transparent text-xl font-semibold leading-snug tracking-[-0.02em] text-foreground outline-none [field-sizing:content] placeholder:text-muted/70"
                />
              </label>
            </div>

            <div className="min-h-0 flex-1 overflow-y-auto border-t border-card-border px-6 py-5">
              {/* Colour */}
              <fieldset>
                <legend className="sr-only">
                  Color
                </legend>
                <div className="flex flex-wrap gap-2 sm:gap-2.5">
                  {GOAL_COLOR_KEYS.map((key) => (
                    <button
                      key={key}
                      type="button"
                      onClick={() => setColor(key)}
                      aria-label={GOAL_COLORS[key].label}
                      aria-pressed={color === key}
                      style={goalColorStyle(key)}
                      className="goal-solid relative flex h-7 w-7 items-center sm:h-8 sm:w-8 justify-center rounded-full text-white ring-offset-2 ring-offset-background transition-transform hover:scale-110 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-foreground/40 aria-pressed:ring-2 aria-pressed:ring-foreground/70"
                    >
                      {color === key && <HugeiconsIcon icon={Tick02Icon} size={16} strokeWidth={2.5} />}
                    </button>
                  ))}
                </div>
              </fieldset>

              {/* Icon */}
              <fieldset className="mt-6">
                <legend className="sr-only">
                  Icon
                </legend>
                <label className="relative block">
                  <span className="sr-only">Search icons</span>
                  <HugeiconsIcon
                    icon={Search01Icon}
                    size={16}
                    className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted"
                  />
                  <input
                    type="search"
                    value={query}
                    onChange={(e) => setQuery(e.target.value)}
                    placeholder="Search icons"
                    className="h-10 w-full rounded-xl border border-card-border bg-foreground/[.03] pl-9 pr-3 text-sm text-foreground outline-none transition-colors placeholder:text-muted focus:border-foreground/20"
                  />
                </label>

                <div className="mt-4 space-y-4">
                  {groups.map((group) => (
                    <div key={group.label}>
                      <p className="mb-2 text-xs font-medium text-muted">{group.label}</p>
                      <div className="grid grid-cols-[repeat(auto-fill,minmax(44px,1fr))] gap-1.5">
                        {group.icons.map(([name, def]) => {
                          const selected = name === icon;
                          return (
                            <button
                              key={name}
                              type="button"
                              title={def.label}
                              aria-label={def.label}
                              aria-pressed={selected}
                              onClick={() => setIcon(name)}
                              style={goalColorStyle(color)}
                              className={`flex aspect-square items-center justify-center rounded-xl transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-foreground/30 ${
                                selected
                                  ? "goal-tint ring-1 ring-current"
                                  : "text-foreground/70 hover:bg-foreground/[.06] hover:text-foreground"
                              }`}
                            >
                              <HugeiconsIcon icon={def.icon} size={22} strokeWidth={1.8} />
                            </button>
                          );
                        })}
                      </div>
                    </div>
                  ))}
                  {groups.length === 0 && (
                    <p className="py-6 text-center text-sm text-muted">No icons match “{query}”.</p>
                  )}
                </div>
              </fieldset>
            </div>

            {/* Footer */}
            <div className="border-t border-card-border px-6 py-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
              {error && (
                <p role="alert" className="mb-3 text-sm text-red-600 dark:text-red-400">
                  {error}
                </p>
              )}
              {confirmingDelete ? (
                <div className="flex items-center justify-between gap-3">
                  <p className="text-sm text-foreground">Delete this goal for good?</p>
                  <div className="flex gap-2">
                    <button
                      type="button"
                      onClick={() => setConfirmingDelete(false)}
                      className="h-10 rounded-xl px-4 text-sm font-medium text-foreground transition-colors hover:bg-foreground/[.06]"
                    >
                      Keep
                    </button>
                    <button
                      type="button"
                      onClick={onDelete}
                      className="h-10 rounded-xl bg-red-600 px-4 text-sm font-semibold text-white transition-colors hover:bg-red-700"
                    >
                      Delete
                    </button>
                  </div>
                </div>
              ) : (
                <div className="flex items-center gap-2">
                  {mode === "edit" && onDelete && (
                    <button
                      type="button"
                      onClick={() => setConfirmingDelete(true)}
                      className="-ml-2 flex h-10 items-center gap-1.5 rounded-xl px-3 text-sm font-medium text-red-600 transition-colors hover:bg-red-500/10 dark:text-red-400"
                    >
                      <HugeiconsIcon icon={Delete02Icon} size={16} />
                      Delete
                    </button>
                  )}
                  <div className="ml-auto flex gap-2">
                    <Dialog.Close className="h-10 rounded-xl px-4 text-sm font-medium text-foreground transition-colors hover:bg-foreground/[.06]">
                      Cancel
                    </Dialog.Close>
                    <button
                      type="submit"
                      className="h-10 rounded-xl bg-foreground px-5 text-sm font-semibold text-background transition-opacity hover:opacity-90"
                    >
                      {mode === "create" ? "Add goal" : "Save"}
                    </button>
                  </div>
                </div>
              )}
            </div>
          </form>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
