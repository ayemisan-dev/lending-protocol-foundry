export const protocolConfigAbi = [
    {
        type: "function",
        name: "getAssetConfig",
        stateMutability: "view",
        inputs: [{ name: "asset", type: "address" }],
        outputs: [
            {
                name: "",
                type: "tuple",
                components: [
                    { name: "enabled", type: "bool" },
                    { name: "ltvBps", type: "uint256" },
                    { name: "liquidationThresholdBps", type: "uint256" },
                    { name: "liquidationBonusBps", type: "uint256" },
                ],
            },
        ],
    },
] as const;