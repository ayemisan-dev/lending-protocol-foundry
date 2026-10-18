export const lendingPoolAbi = [
    {
        type: "function",
        name: "deposit",
        stateMutability: "nonpayable",
        inputs: [
            { name: "asset", type: "address" },
            { name: "amount", type: "uint256" },
        ],
        outputs: [],
    },
    {
        type: "function",
        name: "withdraw",
        stateMutability: "nonpayable",
        inputs: [
            { name: "asset", type: "address" },
            { name: "amount", type: "uint256" },
        ],
        outputs: [],
    },
    {
        type: "function",
        name: "borrow",
        stateMutability: "nonpayable",
        inputs: [
            { name: "asset", type: "address" },
            { name: "amount", type: "uint256" },
        ],
        outputs: [],
    },
    {
        type: "function",
        name: "repay",
        stateMutability: "nonpayable",
        inputs: [
            { name: "asset", type: "address" },
            { name: "amount", type: "uint256" },
        ],
        outputs: [],
    },
    {
        type: "function",
        name: "getUserPosition",
        stateMutability: "view",
        inputs: [
            { name: "user", type: "address" },
            { name: "asset", type: "address" },
        ],
        outputs: [
            {
                name: "",
                type: "tuple",
                components: [
                    { name: "supplied", type: "uint256" },
                    { name: "borrowed", type: "uint256" },
                ],
            },
        ],
    },
    // ---------- custom errors ----------
    { type: "error", name: "InvalidAmount", inputs: [] },
    { type: "error", name: "InsufficientSupply", inputs: [] },
    { type: "error", name: "InsufficientLiquidity", inputs: [] },
    { type: "error", name: "RepayAmountExceedsDebt", inputs: [] },
    { type: "error", name: "BorrowingCapacityExceeded", inputs: [] },
    { type: "error", name: "HealthFactorTooLow", inputs: [] },
    { type: "error", name: "AssetNotEnabled", inputs: [] },
    { type: "error", name: "RiskEngineNotConfigured", inputs: [] },
    { type: "error", name: "ProtocolConfigNotConfigured", inputs: [] },

] as const;