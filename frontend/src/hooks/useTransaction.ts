"use client";

import { useState } from "react";
import { useWriteContract, useWaitForTransactionReceipt, usePublicClient, useConnection} from "wagmi";
import type { Abi, Address } from "viem";
import { parseError } from "@/lib/errors";

interface WriteParams {
    address: Address;
    abi: Abi;
    functionName: string;
    args?: readonly unknown[];
}

export function useTransaction() {
    const publicClient = usePublicClient();
    const { address } = useConnection(); 
    const [simulationError, setSimulationError] = useState<Error | null>(null);

    const {
        mutateAsync: writeContractAsync,
        data: hash,
        isPending: isSigning,
        error: writeError,
        reset: resetWrite,
    } = useWriteContract();

    const {
        isLoading: isConfirming,
        isSuccess: isConfirmed,
        error: receiptError,
    } = useWaitForTransactionReceipt({ hash });

    let status: "idle" | "signing" | "pending" | "confirmed" | "failed" =
        "idle";
    if (isSigning) status = "signing";
    else if (writeError) status = "failed";
    else if (isConfirming) status = "pending";
    else if (isConfirmed) status = "confirmed";
    else if (receiptError) status = "failed";

    const error = simulationError ?? writeError ?? receiptError;
    
    async function write(params: WriteParams) {
        resetWrite();

        try {
            // 1. Pre-flight simulation
            //    This catches reverts in the RPC layer before the wallet
            //    prompt, and viem decodes the custom error using the ABI.
            if (publicClient) {
                await publicClient.simulateContract({
                    address: params.address,
                    abi: params.abi,
                    functionName: params.functionName,
                    args: params.args,
                    account: address, 
                });
            }

            // 2. Actual write
            return await writeContractAsync({
                address: params.address,
                abi: params.abi,
                functionName: params.functionName,
                args: params.args,
            });
        } catch (e) {
            // If simulation or write fails, throw a wrapped error so
            // status becomes "failed" and errorMessage is populated.
            setSimulationError(e as Error);
            throw e;
        }
    }

    return {
        write,
        hash,
        status,
        errorMessage: parseError(error),
        reset: () => {
            resetWrite();
            setSimulationError(null);
        }
    }
}