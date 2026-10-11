// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ProtocolConfig} from "./ProtocolConfig.sol";
import {OracleReader} from "../oracles/OracleReader.sol";
import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract RiskEngine {
    ProtocolConfig public immutable protocolConfig;
    OracleReader public immutable oracleReader;
    ILendingPool public immutable lendingPool;

    error InvalidAddress();
    error AssetNotEnabled();
    error InvalidTokenDecimals();

    constructor(address protocolConfig_, address oracleReader_, address lendingPool_) {
        if (
            protocolConfig_ == address(0) || oracleReader_ == address(0) || lendingPool_ == address(0)
                || protocolConfig_.code.length == 0 || oracleReader_.code.length == 0 || lendingPool_.code.length == 0
        ) {
            revert InvalidAddress();
        }

        protocolConfig = ProtocolConfig(protocolConfig_);
        oracleReader = OracleReader(oracleReader_);
        lendingPool = ILendingPool(lendingPool_);
    }

    function getAssetUsdValue(address asset, uint256 amount) external view returns (uint256) {
        return _getAssetUsdValue(asset, amount);
    }

    function _getAssetUsdValue(address asset, uint256 amount) internal view returns (uint256) {
        ProtocolConfig.AssetConfig memory assetConfig = protocolConfig.getAssetConfig(asset);

        if (!assetConfig.enabled) {
            revert AssetNotEnabled();
        }

        return _calculateUsdValue(asset, amount);
    }

    function _calculateUsdValue(address asset, uint256 amount) internal view returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        uint8 tokenDecimals = IERC20Metadata(asset).decimals();

        // 10**78 exceeds uint256's maximum value.
        if (tokenDecimals > 77) {
            revert InvalidTokenDecimals();
        }

        uint256 price = oracleReader.getPrice(asset);
        uint256 tokenScale = 10 ** uint256(tokenDecimals);

        return Math.mulDiv(amount, price, tokenScale);
    }

    function getTotalCollateralValue(address user) external view returns (uint256 totalValue) {
        address[] memory assets = protocolConfig.getConfiguredAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];

            ProtocolConfig.AssetConfig memory assetConfig = protocolConfig.getAssetConfig(asset);

            if (!assetConfig.enabled || assetConfig.ltvBps == 0) {
                continue;
            }

            ILendingPool.UserPosition memory position = lendingPool.getUserPosition(user, asset);

            if (position.supplied == 0) {
                continue;
            }

            totalValue += _calculateUsdValue(asset, position.supplied);
        }
    }

    function getTotalDebtValue(address user) external view returns (uint256) {
        return _getTotalDebtValue(user);
    }

    function _getTotalDebtValue(address user) internal view returns (uint256 totalValue) {
        address[] memory assets = protocolConfig.getConfiguredAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];

            ILendingPool.UserPosition memory position = lendingPool.getUserPosition(user, asset);

            if (position.borrowed == 0) {
                continue;
            }

            totalValue += _calculateUsdValue(asset, position.borrowed);
        }
    }

    function getMaxBorrowableValue(address user) external view returns (uint256 totalBorrowingPower) {
        address[] memory assets = protocolConfig.getConfiguredAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];

            ProtocolConfig.AssetConfig memory assetConfig = protocolConfig.getAssetConfig(asset);

            if (!assetConfig.enabled || assetConfig.ltvBps == 0) {
                continue;
            }

            ILendingPool.UserPosition memory position = lendingPool.getUserPosition(user, asset);

            if (position.supplied == 0) {
                continue;
            }

            uint256 collateralValue = _calculateUsdValue(asset, position.supplied);

            uint256 assetBorrowingPower = Math.mulDiv(collateralValue, assetConfig.ltvBps, 10_000);

            totalBorrowingPower += assetBorrowingPower;
        }
    }

    function getLiquidationAdjustedCollateralValue(address user) external view returns (uint256) {
        return _getLiquidationAdjustedCollateralValue(user);
    }

    function _getLiquidationAdjustedCollateralValue(address user) internal view returns (uint256 totalValue) {
        address[] memory assets = protocolConfig.getConfiguredAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];

            ProtocolConfig.AssetConfig memory assetConfig = protocolConfig.getAssetConfig(asset);

            if (!assetConfig.enabled || assetConfig.liquidationThresholdBps == 0) {
                continue;
            }

            ILendingPool.UserPosition memory position = lendingPool.getUserPosition(user, asset);

            if (position.supplied == 0) {
                continue;
            }

            uint256 collateralValue = _calculateUsdValue(asset, position.supplied);

            totalValue += Math.mulDiv(collateralValue, assetConfig.liquidationThresholdBps, 10_000);
        }
    }

    function getHealthFactor(address user) external view returns (uint256) {
        uint256 totalDebtValue = _getTotalDebtValue(user);
        if (totalDebtValue == 0) {
            return type(uint256).max;
        }

        uint256 adjustedCollateralValue = _getLiquidationAdjustedCollateralValue(user);

        return Math.mulDiv(adjustedCollateralValue, 1e18, totalDebtValue);
    }
}
