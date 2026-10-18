"use client";

import { useConnection, useReadContracts, useBlockNumber } from "wagmi";
import { useEffect } from "react";
import { useQueryClient } from "@tanstack/react-query";

import { CONTRACTS, SUPPORTED_ASSETS } from "@/config/contracts";
import { lendingPoolAbi } from "@/abis/LendingPool";
import { protocolConfigAbi } from "@/abis/ProtocolConfig";
import { erc20Abi } from "@/abis/ERC20";

/**
 * Reads the user's position across all supported assets plus
 * wallet balance, allowance, and asset configuration.
 *
 * Uses useReadContracts to batch all reads into a single Multicall3
 * request, which reduces RPC round-trips.
 *
 * Refetches automatically on every new block via useBlockNumber + query
 * invalidation, so the dashboard stays in sync after any transaction.
 */
export function usePosition() {
    const { address, isConnected } = useConnection();
    const { data: blockNumber } = useBlockNumber({ watch: true });
    const queryClient = useQueryClient();

    const asset = SUPPORTED_ASSETS[0];

    const { data, isPending, error, refetch, queryKey, } = useReadContracts({
        contracts: [
            // 0: user position in LendingPool
            {
                address: CONTRACTS.lendingPool,
                abi: lendingPoolAbi,
                functionName: "getUserPosition",
                args: [address!, asset.address],
            },
            // 1: asset config from ProtocolConfig
            {
                address: CONTRACTS.protocolConfig,
                abi: protocolConfigAbi,
                functionName: "getAssetConfig",
                args: [asset.address],
            },
            // 2: user's wallet token balance
            {
                address: asset.address,
                abi: erc20Abi,
                functionName: "balanceOf",
                args: [address!],
            },
            // 3: allowance granted to LendingPool
            {
                address: asset.address,
                abi: erc20Abi,
                functionName: "allowance",
                args: [address!, CONTRACTS.lendingPool],
            },
        ],
        query: { enabled: !!address && isConnected },
    });

    // Invalidate cached reads whenever a new block arrives so the
    // dashboard reflects on-chain state changes without a manual refresh.
    useEffect(() => {
        if (blockNumber !== undefined) {
            queryClient.invalidateQueries({ queryKey });
        }
    }, [blockNumber, queryClient, queryKey]);

    return {
        position: data?.[0]?.result as
            | { supplied: bigint; borrowed: bigint }
            | undefined,
        assetConfig: data?.[1]?.result as
            | {
                  enabled: boolean;
                  ltvBps: bigint;
                  liquidationThresholdBps: bigint;
                  liquidationBonusBps: bigint;
              }
            | undefined,
        walletBalance: data?.[2]?.result as bigint | undefined,
        allowance: data?.[3]?.result as bigint | undefined,
        isPending,
        error,
        refetch,
        asset,
    };
}