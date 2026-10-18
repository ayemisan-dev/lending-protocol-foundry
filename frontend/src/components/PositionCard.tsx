"use client";

import { usePosition } from "@/hooks/usePosition";
import { formatToken } from "@/lib/format";

export function PositionCard() {
    const { position, walletBalance, allowance, isPending, error, asset } =
        usePosition();

    if (isPending) {
        return (
            <Panel title="Your position">
                <p className="text-sm text-neutral-500">Loading…</p>
            </Panel>
        );
    }

    if (error) {
        return (
            <Panel title="Your position">
                <p className="text-sm text-red-400">
                    Failed to read position: {error.message}
                </p>
            </Panel>
        );
    }

    return (
        <Panel title="Your position">
            <dl className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <Stat
                    label="Supplied"
                    value={`${formatToken(position?.supplied, asset.decimals)} ${asset.symbol}`}
                />
                <Stat
                    label="Borrowed"
                    value={`${formatToken(position?.borrowed, asset.decimals)} ${asset.symbol}`}
                />
                <Stat
                    label="Wallet balance"
                    value={`${formatToken(walletBalance, asset.decimals)} ${asset.symbol}`}
                />
                <Stat
                    label="Allowance to pool"
                    value={`${formatToken(allowance, asset.decimals)} ${asset.symbol}`}
                />
            </dl>
        </Panel>
    );
}

function Panel({title, children,}:{title: string; children: React.ReactNode;}){
    return (
        <section className="rounded-2xl border border-neutral-800 bg-neutral-900 p-6">
            <h2 className="mb-4 text-lg font-semibold text-white">{title}</h2>
            {children}
        </section>
    );
}

function Stat({ label, value }: { label: string; value: string }) {
    return (
        <div className="rounded-xl border border-neutral-800 bg-neutral-950/50 p-4">
            <dt className="text-xs uppercase tracking-wider text-neutral-500">
                {label}
            </dt>
            <dd className="mt-2 font-mono text-lg text-neutral-100">{value}</dd>
        </div>
    );
}