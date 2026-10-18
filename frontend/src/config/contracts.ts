import type { Address } from "viem";

/**
 * Deployed contract addresses on Ethereum Sepolia.
 */
export const CONTRACTS = {
    protocolConfig: "0x8388c77999ebB82D53D4997CFE8e6cACDEA9A43e" as Address,
    oracleReader: "0x9b19CD6b433E9B151c2f11a174f72808B979d59d" as Address,
    lendingPool: "0xeC8de0C9E429652F7541BD313cA51e944277aFB8" as Address,
    riskEngine: "0xEF6194e4C2B22d11008dD45424309eD4994c6F53" as Address,
    testToken: "0xBCFf6dA2f6e00B66655954C87d6894cBa33777c7" as Address,
    testFeed: "0xF340ef2988A635B0789304EE182A29bC34EF36D8" as Address,
} as const;

/** The single asset currently configured in the protocol. */
export const SUPPORTED_ASSETS = [
    {
        address: CONTRACTS.testToken,
        symbol: "tUSD",
        decimals: 18,
    },
] as const;