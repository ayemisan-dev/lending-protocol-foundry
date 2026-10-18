"use client";

import { http, createConfig } from "wagmi";
import { sepolia } from "wagmi/chains";
import { injected } from "wagmi/connectors";

/**
 * Wagmi configuration for LendX.
 *
 * Reads (getUserPosition, getAssetConfig) go through the configured RPC.
 * Writes (deposit, borrow) are always signed by the user's wallet, so the
 * RPC only matters for read throughput and reliability.
 */
export const wagmiConfig = createConfig({
    chains: [sepolia],
    connectors: [injected({target: 'metaMask', })],
    transports: {
        [sepolia.id]: http(process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL),
    },
    ssr: true,
    multiInjectedProviderDiscovery: false,
});