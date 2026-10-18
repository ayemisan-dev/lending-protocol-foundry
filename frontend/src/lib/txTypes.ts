import type { Address, Hash } from "viem";

export type TxStatus = "pending" | "success" | "failed" | "rejected";

export interface StoredTransaction {
    hash?: Hash;             
    chainId: number;
    from: Address;
    action: string;         // e.g. "deposit", "withdraw", "approve"
    summary?: string;       // e.g. "Deposit 10 tUSD"
    status: TxStatus;
    timestamp: number;
}