"use client";

import { useState, type SubmitEvent } from "react";
import { parseUnits } from "viem";
import { useConnection } from "wagmi";
import { useTransaction } from "@/hooks/useTransaction";
import { useTransactionHistory } from "@/context/TransactionProvider";
import { useToast } from "@/components/Toast";
import { CONTRACTS, SUPPORTED_ASSETS } from "@/config/contracts";
import { lendingPoolAbi } from "@/abis/LendingPool";
import { erc20Abi } from "@/abis/ERC20";
import { parseError } from "@/lib/errors";

type Action = "deposit" | "withdraw" | "borrow" | "repay";

const LABELS: Record<Action, { title: string; button: string; needsApproval: boolean }> = {
    deposit: { title: "Deposit", button: "Deposit", needsApproval: true },
    withdraw: { title: "Withdraw", button: "Withdraw", needsApproval: false },
    borrow: { title: "Borrow", button: "Borrow", needsApproval: false },
    repay: { title: "Repay", button: "Repay", needsApproval: true },
};

interface Props {
    action: Action;
    allowance: bigint | undefined;
    onDone?: () => void;
}

export function ActionForm({ action, allowance, onDone }: Props) {
    const asset = SUPPORTED_ASSETS[0];
    const { address, chainId } = useConnection();
    const { addToast } = useToast();
    const [amount, setAmount] = useState("");

    const tx = useTransaction();
    const approveTx = useTransaction();
    const { addTransaction } = useTransactionHistory();

    const label = LABELS[action];
    const decimals = asset.decimals;

    const parsed = (() => {
        try {
            return amount ? parseUnits(amount, decimals) : undefined;
        } catch {
            return undefined;
        }
    })();

    const needsApproval =
        label.needsApproval &&
        parsed !== undefined &&
        (allowance === undefined || allowance < parsed);

    async function handleApprove() {
        if (!parsed || !address || !chainId) return;

        try {
            const hash = await approveTx.write({
                address: asset.address,
                abi: erc20Abi,
                functionName: "approve",
                args: [CONTRACTS.lendingPool, parsed],
            });

            addTransaction({
                hash,
                chainId,
                from: address,
                action: "approve",
                summary: `Approve ${amount} ${asset.symbol}`,
                status: "pending",
                timestamp: Date.now(),
            });
            addToast("Approval submitted", "info");
        } catch (err) {
            addToast(parseError(err) || "Approval failed", "error");
        }
    }

    async function handleSubmit(e: SubmitEvent<HTMLFormElement>) {
        e.preventDefault();
        if (!parsed || !address || !chainId) return;

        try {
            const hash = await tx.write({
                address: CONTRACTS.lendingPool,
                abi: lendingPoolAbi,
                functionName: action,
                args: [asset.address, parsed],
            });

            addTransaction({
                hash,
                chainId,
                from: address,
                action,
                summary: `${label.title} ${amount} ${asset.symbol}`,
                status: "pending",
                timestamp: Date.now(),
            });

            addToast(`${label.title} submitted`, "info");
            setAmount("");
            onDone?.();
        } catch (err) {
            addToast(parseError(err) || "Transaction failed", "error");
        }
    }

    return (
        <form
            onSubmit={handleSubmit}
            className="rounded-2xl border border-neutral-800 bg-neutral-900 p-6"
        >
            <h3 className="mb-4 text-lg font-semibold text-white">
                {label.title}
            </h3>

            <div className="mb-4">
                <label className="mb-1 block text-xs uppercase tracking-wider text-neutral-500">
                    Amount ({asset.symbol})
                </label>
                <input
                    type="number"
                    min="0"
                    step="any"
                    value={amount}
                    onChange={(e) => setAmount(e.target.value)}
                    placeholder="0.0"
                    className="w-full rounded-lg border border-neutral-800 bg-neutral-950 px-3 py-2 font-mono text-neutral-100 placeholder:text-neutral-600 focus:border-blue-500 focus:outline-none"
                />
            </div>

            {needsApproval ? (
                <button
                    type="button"
                    onClick={handleApprove}
                    disabled={
                        approveTx.status === "signing" ||
                        approveTx.status === "pending"
                    }
                    className="w-full rounded-lg bg-amber-600 px-4 py-2 text-sm font-medium text-white hover:bg-amber-500 disabled:opacity-50"
                >
                    {approveTx.status === "signing"
                        ? "Confirm in wallet…"
                        : approveTx.status === "pending"
                          ? "Approving…"
                          : `Approve ${asset.symbol}`}
                </button>
            ) : (
                <button
                    type="submit"
                    disabled={
                        !parsed ||
                        tx.status === "signing" ||
                        tx.status === "pending"
                    }
                    className="w-full rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-500 disabled:opacity-50"
                >
                    {tx.status === "signing"
                        ? "Confirm in wallet…"
                        : tx.status === "pending"
                          ? "Confirming…"
                          : label.button}
                </button>
            )}
        </form>
    );
}