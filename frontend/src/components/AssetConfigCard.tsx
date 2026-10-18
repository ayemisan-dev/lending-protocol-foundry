"use client";

import { usePosition } from "@/hooks/usePosition";

/** Convert basis points to a percentage string. */
function bpsToPercent(bps: bigint | undefined): string {
    if (bps === undefined) return "—";
    const percent = Number(bps) / 100;
    return `${percent}%`;
}

export function AssetConfigCard() {
    const { assetConfig, isPending, error, asset } = usePosition();

    return (
        <section className="rounded-2xl border border-neutral-800 bg-neutral-900 p-6">
            <h2 className="mb-4 text-lg font-semibold text-white">
                {asset.symbol} parameters
            </h2>

            {
                isPending ? (
                    <p className="text-sm text-neutral-500">Loading…</p>
                ) : error ? (
                    <p className="text-sm text-red-400">
                        Failed to read config: {error.message}
                    </p>
                ) : !assetConfig?.enabled ? (
                    <p className="text-sm text-amber-400">
                        This asset is currently disabled.
                    </p>
                ) : (
                    <dl className="grid grid-cols-1 gap-4 sm:grid-cols-3">
                        <Stat 
                            label="LTV" 
                            value={bpsToPercent(assetConfig.ltvBps)} />
                        <Stat
                            label="Liquidation threshold"
                            value={bpsToPercent(assetConfig.liquidationThresholdBps)}
                        />
                        <Stat
                            label="Liquidation bonus"
                            value={bpsToPercent(assetConfig.liquidationBonusBps)}
                        />
                    </dl>
                )
            }
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