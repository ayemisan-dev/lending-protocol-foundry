"use client";

import { useConnection } from "wagmi";
import { ConnectButton } from "@/components/ConnectButton";
import { PositionCard } from "@/components/PositionCard";
import { AssetConfigCard } from "@/components/AssetConfigCard";
import { RiskCard } from "@/components/RiskCard";
import { ActionForm } from "@/components/ActionForm";
import { usePosition } from "@/hooks/usePosition";
import { TransactionHistory } from "@/components/TransactionHistory";

export default function Home() {
    const { isConnected } = useConnection();
    const { allowance, refetch } = usePosition();

    return (
        <main className="mx-auto max-w-4xl px-6 py-10">
            <header className="mb-10 flex items-center justify-between">
                <h1 className="text-3xl font-bold tracking-tight text-white">
                    LendX
                </h1>
                <ConnectButton />
            </header>

            {!isConnected ? (
                <section className="rounded-2xl border border-neutral-800 bg-neutral-900 p-6">
                    <p className="text-neutral-400">
                        Connect a wallet to interact with the protocol.
                    </p>
                </section>
            ) : (
                <div className="space-y-6">
                    <PositionCard />
                    <RiskCard />

                    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                        <ActionForm action="deposit" allowance={allowance} onDone={refetch} />
                        <ActionForm action="withdraw" allowance={allowance} onDone={refetch} />
                        <ActionForm action="borrow" allowance={allowance} onDone={refetch} />
                        <ActionForm action="repay" allowance={allowance} onDone={refetch} />
                    </div>

                    <AssetConfigCard />
                    <TransactionHistory />
                </div>
            )}
        </main>
    );
}