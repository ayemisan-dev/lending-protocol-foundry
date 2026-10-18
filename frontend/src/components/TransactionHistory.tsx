"use client";

import { useTransactionHistory } from "@/context/TransactionProvider";
import { useConnection } from "wagmi";
import { sepolia } from "wagmi/chains";

const EXPLORER = "https://sepolia.etherscan.io/tx/";

export function TransactionHistory() {
    const { isConnected } = useConnection();
    const { transactions, clearHistory } = useTransactionHistory();

    if (!isConnected) return null;

    return (
        <section className="rounded-2xl border border-neutral-800 bg-neutral-900 p-6">
            <div className="mb-4 flex items-center justify-between">
                <h2 className="text-lg font-semibold text-white">Recent transactions</h2>
                {transactions.length > 0 && (
                    <button onClick={clearHistory} className="text-xs text-neutral-500 hover:text-neutral-300">
                        Clear history
                    </button>
                )}
            </div>

            {transactions.length === 0 ? (
                <p className="text-sm text-neutral-500">No transactions yet.</p>
            ) : (
                <ul className="space-y-3">
                    {transactions.map((tx, i) => (
                        <li key={tx.hash ?? i} className="flex items-center justify-between rounded-xl border border-neutral-800 bg-neutral-950/50 p-4">
                            <div>
                                <p className="text-sm font-medium text-neutral-200">{tx.summary ?? tx.action}</p>
                                <p className="text-xs text-neutral-500">{new Date(tx.timestamp).toLocaleString()}</p>
                            </div>
                            <div className="flex items-center gap-3">
                                <span className={`text-xs font-medium px-2 py-1 rounded-full ${
                                    tx.status === "success" ? "bg-emerald-900/50 text-emerald-400" :
                                    tx.status === "failed" || tx.status === "rejected" ? "bg-red-900/50 text-red-400" :
                                    "bg-amber-900/50 text-amber-400"
                                }`}>
                                    {tx.status}
                                </span>
                                {tx.hash && (
                                    <a href={`${EXPLORER}${tx.hash}`} target="_blank" rel="noopener noreferrer" className="text-xs text-blue-400 hover:underline">
                                        Etherscan ↗
                                    </a>
                                )}
                            </div>
                        </li>
                    ))}
                </ul>
            )}
        </section>
    );
}