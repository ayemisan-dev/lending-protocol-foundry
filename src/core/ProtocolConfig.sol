// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ProtocolConfig is Ownable {
    struct AssetConfig {
        bool enabled;
        uint256 ltvBps;
        uint256 liquidationThresholdBps;
        uint256 liquidationBonusBps;
    }
    mapping(address asset => AssetConfig assetConfig) private assetConfigs;

    address[] private configuredAssets;
    mapping(address asset => bool exists) private isAssetConfigured;

    error InvalidAsset();
    error InvalidLtv();
    error InvalidLiquidationThreshold();
    error InvalidLtvThresholdRelation();
    error InvalidLiquidationBonus();

    event AssetConfigUpdated(
        address indexed asset,
        bool enabled,
        uint256 ltvBps,
        uint256 liquidationThresholdBps,
        uint256 liquidationBonusBps
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    function configureAsset(
        address asset,
        bool enabled,
        uint256 ltvBps,
        uint256 liquidationThresholdBps,
        uint256 liquidationBonusBps
    ) external onlyOwner {
        if (asset == address(0)) {
            revert InvalidAsset();
        }
        if (ltvBps > 10_000) {
            revert InvalidLtv();
        }
        if (liquidationThresholdBps > 10_000) {
            revert InvalidLiquidationThreshold();
        }
        if (ltvBps > liquidationThresholdBps) {
            revert InvalidLtvThresholdRelation();
        }
        if (liquidationBonusBps > 10_000) {
            revert InvalidLiquidationBonus();
        }

        if (!isAssetConfigured[asset]) {
            configuredAssets.push(asset);
            isAssetConfigured[asset] = true;
        }

        assetConfigs[asset] = AssetConfig({
            enabled: enabled,
            ltvBps: ltvBps,
            liquidationThresholdBps: liquidationThresholdBps,
            liquidationBonusBps: liquidationBonusBps
        });

        emit AssetConfigUpdated(asset, enabled, ltvBps, liquidationThresholdBps, liquidationBonusBps);
    }

    function getAssetConfig(address asset) external view returns (AssetConfig memory) {
        return assetConfigs[asset];
    }

    function getConfiguredAssets() external view returns (address[] memory) {
        return configuredAssets;
    }
}
