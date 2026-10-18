"use client";

import { useConnection, useReadContracts } from "wagmi";

import { CONTRACTS } from "@/config/contracts";
import { riskEngineAbi } from "@/abis/RiskEngine";

type RiskReadResult =
    | { status: "success"; result: bigint }
    | { status: "failure"; error: Error };

function firstError(items: readonly RiskReadResult[] | undefined): string | undefined {
    if (!items) return undefined;
    for (const item of items) {
        if (item.status === "failure") {
            const message = item.error?.message ?? "Unknown error";
            // viem errors often have a shortMessage that is friendlier.
            const short = (item.error as { shortMessage?: string })
                ?.shortMessage;
            return short ?? message;
        }
    }
    return undefined;
}

export function useRiskData() {
    const { address, isConnected } = useConnection();

    const { data, isPending } = useReadContracts({
        contracts: [
            {
                address: CONTRACTS.riskEngine,
                abi: riskEngineAbi,
                functionName: "getTotalCollateralValue",
                args: [address!],
            },
            {
                address: CONTRACTS.riskEngine,
                abi: riskEngineAbi,
                functionName: "getTotalDebtValue",
                args: [address!],
            },
            {
                address: CONTRACTS.riskEngine,
                abi: riskEngineAbi,
                functionName: "getMaxBorrowableValue",
                args: [address!],
            },
            {
                address: CONTRACTS.riskEngine,
                abi: riskEngineAbi,
                functionName: "getHealthFactor",
                args: [address!],
            },
        ],
        query: { enabled: !!address && isConnected },
    });

    const results = data as
        | readonly [
              RiskReadResult,
              RiskReadResult,
              RiskReadResult,
              RiskReadResult,
          ]
        | undefined;

    const readError = firstError(results);

    return {
        totalCollateral:
            results?.[0]?.status === "success"
                ? results[0].result
                : undefined,
        totalDebt:
            results?.[1]?.status === "success"
                ? results[1].result
                : undefined,
        maxBorrowable:
            results?.[2]?.status === "success"
                ? results[2].result
                : undefined,
        healthFactor:
            results?.[3]?.status === "success"
                ? results[3].result
                : undefined,
        isPending,
        error: readError,
    };
}