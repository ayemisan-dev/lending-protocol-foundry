"use client";

import { createContext, useContext, useEffect, useState } from "react";
import { useConnection, useBlockNumber, usePublicClient } from "wagmi";
import type { Hash } from "viem";
import type { StoredTransaction } from "@/lib/txTypes";
import { useToast } from "@/components/Toast";

interface TxContextType {
    transactions: StoredTransaction[];
    addTransaction: (tx: StoredTransaction) => void;
    updateStatus: (hash: Hash, status: StoredTransaction["status"]) => void;
    clearHistory: () => void;
}

const TxContext = createContext<TxContextType | undefined>(undefined);
const STORAGE_KEY_PREFIX = "lendx-txs-";

export function TransactionProvider({ children }: { children: React.ReactNode }) {
    const { address, chainId } = useConnection();
    const publicClient = usePublicClient();
    const { data: blockNumber } = useBlockNumber({ watch: true });
    const { addToast } = useToast();

    const [transactions, setTransactions] = useState<StoredTransaction[]>([]);
    const [mounted, setMounted] = useState(false);

    useEffect(() => {
        setMounted(true);
    }, []);

    useEffect(() => {
        if (!mounted || !address || !chainId) {
            setTransactions([]);
            return;
        }
        const key = `${STORAGE_KEY_PREFIX}${address}-${chainId}`;
        const stored = localStorage.getItem(key);
        if (stored) {
            try {
                setTransactions(JSON.parse(stored));
            } catch {
                setTransactions([]);
            }
        } else {
            setTransactions([]);
        }
    }, [mounted, address, chainId]);

    useEffect(() => {
        if (!mounted || !address || !chainId) return;
        const key = `${STORAGE_KEY_PREFIX}${address}-${chainId}`;
        localStorage.setItem(key, JSON.stringify(transactions));
    }, [transactions, mounted, address, chainId]);

    useEffect(() => {
        if (!mounted || !publicClient || !blockNumber) return;

        const pendingTxs = transactions.filter(
            (tx) => tx.status === "pending" && tx.hash
        );
        if (pendingTxs.length === 0) return;

        pendingTxs.forEach(async (tx) => {
            try {
                const receipt = await publicClient.getTransactionReceipt({
                    hash: tx.hash as Hash,
                });

                if (receipt.status === "success") {
                    updateStatus(tx.hash as Hash, "success");
                    addToast(`Transaction confirmed: ${tx.summary}`, "success");
                } else if (receipt.status === "reverted") {
                    updateStatus(tx.hash as Hash, "failed");
                    addToast(`Transaction failed: ${tx.summary}`, "error");
                }
            } catch {}
        });
    }, [blockNumber, transactions, publicClient, mounted, addToast]);

    function addTransaction(tx: StoredTransaction) {
        setTransactions((prev) => [tx, ...prev].slice(0, 50));
    }

    function updateStatus(hash: Hash, status: StoredTransaction["status"]) {
        setTransactions((prev) =>
            prev.map((tx) => (tx.hash === hash ? { ...tx, status } : tx))
        );
    }

    function clearHistory() {
        setTransactions([]);
        if (address && chainId) {
            localStorage.removeItem(`${STORAGE_KEY_PREFIX}${address}-${chainId}`);
        }
    }

    return (
        <TxContext.Provider value={{ transactions, addTransaction, updateStatus, clearHistory }}>
            {children}
        </TxContext.Provider>
    );
}

export function useTransactionHistory() {
    const ctx = useContext(TxContext);
    if (!ctx)
        throw new Error(
            "useTransactionHistory must be used within TransactionProvider"
        );
    return ctx;
}