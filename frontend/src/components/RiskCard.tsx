"use client";

import { useRiskData } from "@/hooks/useRiskData";
import { formatUsd, formatHealthFactor } from "@/lib/format";

export function RiskCard() {
    const {
        totalCollateral,
        totalDebt,
        maxBorrowable,
        healthFactor,
        isPending,
        error,
    } = useRiskData();

    if (isPending) {
        return (
            <Panel title="Risk overview">
                <p className="text-sm text-neutral-500">Loading…</p>
            </Panel>
        );
    }

    if (error) {
        return (
            <Panel title="Risk overview">
                <p className="text-sm text-red-400">
                    Failed to read risk data: {error}
                </p>
                <p className="mt-2 text-xs text-neutral-500">
                    If the price feed is stale, refresh the MockAggregatorV3
                    timestamp on Sepolia.
                </p>
            </Panel>
        );
    }

    const hfValue = healthFactor;
    let hfColor = "text-neutral-500";
    if (hfValue !== undefined) {
        if (hfValue <= 1n * 10n ** 18n) {
            hfColor = "text-red-400";
        } else if (hfValue < 2n * 10n ** 18n) {
            hfColor = "text-amber-400";
        } else {
            hfColor = "text-emerald-400";
        }
    }

    return (
        <Panel title="Risk overview">
            <dl className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <Stat label="Total collateral" value={formatUsd(totalCollateral)} />
                <Stat label="Total debt" value={formatUsd(totalDebt)} />
                <Stat label="Borrowing power" value={formatUsd(maxBorrowable)} />
                <div className="rounded-xl border border-neutral-800 bg-neutral-950/50 p-4">
                    <dt className="text-xs uppercase tracking-wider text-neutral-500">
                        Health factor
                    </dt>
                    <dd className={`mt-2 font-mono text-2xl font-semibold ${hfColor}`}>
                        {formatHealthFactor(healthFactor)}
                    </dd>
                </div>
            </dl>
        </Panel>
    );
}

function Panel({title, children,}: {title: string; children: React.ReactNode;}){
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