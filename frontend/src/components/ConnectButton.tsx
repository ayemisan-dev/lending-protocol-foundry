"use client";

import { useEffect, useState } from "react";
import {
    useConnection,
    useConnect,
    useConnectors,
    useDisconnect,
    useSwitchChain,
} from "wagmi";
import { sepolia } from "wagmi/chains";

export function ConnectButton() {
    const [mounted, setMounted] = useState(false);
    useEffect(() => {
        setMounted(true);
    }, []);

    const { address, isConnected, chainId } = useConnection();
    const connect = useConnect();
    const connectors = useConnectors();
    const disconnect = useDisconnect();
    const switchChain = useSwitchChain();

    if (!mounted) {
        return (
            <div className="rounded-lg bg-neutral-800 px-4 py-2 text-sm text-neutral-500">
                Loading…
            </div>
        );
    }

    if (!isConnected) {
        return (
            <div className="flex flex-col items-end gap-2">
                <div className="flex gap-2">
                    {connectors.map((connector) => (
                        <button
                            key={connector.uid}
                            onClick={() => connect.mutate({ connector })}
                            disabled={connect.isPending}
                            className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-blue-500 disabled:cursor-not-allowed disabled:opacity-50"
                        >
                            {connect.isPending
                                ? "Connecting…"
                                : `Connect ${connector.name}`}
                        </button>
                    ))}
                </div>

                {connect.error && (
                    <p className="max-w-xs text-right text-xs text-red-400">
                        {connect.error.message}
                    </p>
                )}
            </div>
        );
    }

    const wrongChain = chainId !== sepolia.id;

    return (
        <div className="flex items-center gap-3">
            <span className="rounded-lg bg-neutral-800 px-3 py-1.5 font-mono text-sm text-neutral-200">
                {address?.slice(0, 6)}…{address?.slice(-4)}
            </span>

            {wrongChain && (
                <button
                    onClick={() => switchChain.mutate({ chainId: sepolia.id })}
                    disabled={switchChain.isPending}
                    className="rounded-lg bg-amber-600 px-3 py-1.5 text-sm font-medium text-white transition-colors hover:bg-amber-500 disabled:cursor-not-allowed disabled:opacity-50"
                >
                    {switchChain.isPending ? "Switching…" : "Switch to Sepolia"}
                </button>
            )}

            <button
                onClick={() => disconnect.mutate()}
                disabled={disconnect.isPending}
                className="rounded-lg bg-neutral-800 px-3 py-1.5 text-sm font-medium text-neutral-200 transition-colors hover:bg-neutral-700 disabled:cursor-not-allowed disabled:opacity-50"
            >
                Disconnect
            </button>
        </div>
    );
}