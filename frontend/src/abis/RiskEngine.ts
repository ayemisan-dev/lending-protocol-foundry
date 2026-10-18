export const riskEngineAbi = [
    {
        type: "function",
        name: "getHealthFactor",
        stateMutability: "view",
        inputs: [{ name: "user", type: "address" }],
        outputs: [{ name: "", type: "uint256" }],
    },
    {
        type: "function",
        name: "getTotalCollateralValue",
        stateMutability: "view",
        inputs: [{ name: "user", type: "address" }],
        outputs: [{ name: "totalValue", type: "uint256" }],
    },
    {
        type: "function",
        name: "getTotalDebtValue",
        stateMutability: "view",
        inputs: [{ name: "user", type: "address" }],
        outputs: [{ name: "totalValue", type: "uint256" }],
    },
    {
        type: "function",
        name: "getMaxBorrowableValue",
        stateMutability: "view",
        inputs: [{ name: "user", type: "address" }],
        outputs: [{ name: "totalBorrowingPower", type: "uint256" }],
    },
] as const;