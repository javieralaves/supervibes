"use client";

import { Refresh01Icon, Unlink04Icon } from "@hugeicons/core-free-icons";
import { useState, useTransition } from "react";

import { ConfirmDialog } from "@/components/confirm-dialog";
import { MoreMenu, MoreMenuItem } from "@/components/more-menu";
import type { ProviderKey } from "@/lib/providers";

import { disconnectAction } from "./actions";

/** More-options menu for a connected app: reconnect, or disconnect after confirming. */
export function ConnectionMenu({ provider, label }: { provider: ProviderKey; label: string }) {
  const [confirming, setConfirming] = useState(false);
  const [pending, startTransition] = useTransition();

  return (
    <>
      <MoreMenu label={`${label} options`}>
        <MoreMenuItem icon={Refresh01Icon} href={`/api/connections/${provider}/start`}>
          Reconnect
        </MoreMenuItem>
        <MoreMenuItem icon={Unlink04Icon} destructive onSelect={() => setConfirming(true)}>
          Disconnect
        </MoreMenuItem>
      </MoreMenu>

      <ConfirmDialog
        open={confirming}
        onOpenChange={setConfirming}
        title={`Disconnect ${label}?`}
        description={`Supervibes will stop reading from ${label}. Goal sources that use it will be removed, so progress reads won't look there anymore. You can connect it again anytime.`}
        confirmLabel="Disconnect"
        pendingLabel="Disconnecting…"
        pending={pending}
        onConfirm={() =>
          startTransition(async () => {
            await disconnectAction(provider);
            setConfirming(false);
          })
        }
      />
    </>
  );
}
