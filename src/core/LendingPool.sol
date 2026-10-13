// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {RiskEngine} from "./RiskEngine.sol";
import {ProtocolConfig} from "./ProtocolConfig.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract LendingPool is ILendingPool, Ownable {
    using SafeERC20 for IERC20;

    mapping(address user => mapping(address asset => ILendingPool.UserPosition)) internal positions;
    address public riskEngine;
    ProtocolConfig public config;

    error InvalidAmount();
    error InsufficientSupply();
    error InsufficientLiquidity();
    error RepayAmountExceedsDebt();
    error InvalidRiskEngineAddress();
    error RiskEngineAlreadySet();
    error BorrowingCapacityExceeded();
    error HealthFactorTooLow();
    error AssetNotEnabled();
    error InvalidProtocolConfigAddress();
    error ProtocolConfigAlreadySet();
    error ProtocolConfigNotConfigured();
    error RiskEngineNotConfigured();
    error PositionNotLiquidatable();
    error InsufficientCollateralForLiquidation();

    event LiquidationExecuted(
        address indexed borrower,
        address indexed liquidator,
        address indexed debtAsset,
        address collateralAsset,
        uint256 debtRepaid,
        uint256 collateralSeized
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setRiskEngine(address _riskEngine) external onlyOwner {
        if (_riskEngine == address(0)) revert InvalidRiskEngineAddress();
        if (riskEngine != address(0)) revert RiskEngineAlreadySet();
        if (_riskEngine.code.length == 0) revert InvalidRiskEngineAddress();

        RiskEngine engine = RiskEngine(_riskEngine);

        if (address(config) == address(0)) revert ProtocolConfigNotConfigured();
        if (address(engine.lendingPool()) != address(this) || address(engine.protocolConfig()) != address(config)) {
            revert InvalidRiskEngineAddress();
        }

        riskEngine = _riskEngine;
    }

    function setProtocolConfig(address _config) external onlyOwner {
        if (_config == address(0) || _config.code.length == 0) revert InvalidProtocolConfigAddress();
        if (address(config) != address(0)) revert ProtocolConfigAlreadySet();

        config = ProtocolConfig(_config);
    }

    function deposit(address asset, uint256 amount) external override {
        if (amount == 0) revert InvalidAmount();

        if (address(config) == address(0)) {
            revert ProtocolConfigNotConfigured();
        }

        if (!config.getAssetConfig(asset).enabled) {
            revert AssetNotEnabled();
        }

        IERC20 token = IERC20(asset);

        // 1. Record the pool balance before the transfer.
        uint256 balanceBefore = token.balanceOf(address(this));

        // 2. Transfer tokens from the user to the pool.
        token.safeTransferFrom(msg.sender, address(this), amount);

        // 3. Calculate the actual amount received.
        uint256 balanceAfter = token.balanceOf(address(this));
        uint256 receivedAmount = balanceAfter - balanceBefore;

        // 4. Reject tokens that deliver less than the requested amount.
        if (receivedAmount != amount) {
            revert InvalidAmount();
        }

        // 5. Update the user's position only after validation.
        positions[msg.sender][asset].supplied += receivedAmount;
    }

    function withdraw(address asset, uint256 amount) external override {
        if (amount == 0) revert InvalidAmount();
        if (riskEngine == address(0)) revert RiskEngineNotConfigured();

        ILendingPool.UserPosition storage position = positions[msg.sender][asset];
        if (amount > position.supplied) revert InsufficientSupply();

        // 1. Apply the withdrawal to the user's position first.
        position.supplied -= amount;

        // 2. Validate the health factor after the withdrawal.
        uint256 healthFactor = RiskEngine(riskEngine).getHealthFactor(msg.sender);

        if (healthFactor < 1e18) revert HealthFactorTooLow();

        // 3. Transfer collateral only after validation succeeds.
        IERC20(asset).safeTransfer(msg.sender, amount);
    }

    function borrow(address asset, uint256 amount) external override {
        if (amount == 0) revert InvalidAmount();
        if (riskEngine == address(0)) revert RiskEngineNotConfigured();
        if (IERC20(asset).balanceOf(address(this)) < amount) revert InsufficientLiquidity();

        uint256 currentDebtValue = RiskEngine(riskEngine).getTotalDebtValue(msg.sender);
        uint256 additionalDebtValue = RiskEngine(riskEngine).getAssetUsdValue(asset, amount);
        uint256 maxBorrowableValue = RiskEngine(riskEngine).getMaxBorrowableValue(msg.sender);

        if (currentDebtValue + additionalDebtValue > maxBorrowableValue) revert BorrowingCapacityExceeded();

        positions[msg.sender][asset].borrowed += amount;
        IERC20(asset).safeTransfer(msg.sender, amount);
    }

    function repay(address asset, uint256 amount) external override {
        if (amount == 0) revert InvalidAmount();

        ILendingPool.UserPosition storage position = positions[msg.sender][asset];

        if (amount > position.borrowed) revert RepayAmountExceedsDebt();

        IERC20 token = IERC20(asset);

        // 1. Record the pool's balance before repayment.
        uint256 balanceBefore = token.balanceOf(address(this));

        // 2. Transfer tokens from the user to the pool.
        token.safeTransferFrom(msg.sender, address(this), amount);

        // 3. Calculate the actual amount received.
        uint256 balanceAfter = token.balanceOf(address(this));
        uint256 receivedAmount = balanceAfter - balanceBefore;

        // 4. Reject fee-on-transfer or otherwise short-paying tokens.
        if (receivedAmount != amount) revert InvalidAmount();

        // 5. Reduce debt only after validating the received amount.
        position.borrowed -= receivedAmount;
    }

    function getUserPosition(address user, address asset)
        external
        view
        override
        returns (ILendingPool.UserPosition memory)
    {
        return positions[user][asset];
    }

    function liquidate(address borrower, address debtAsset, address collateralAsset, uint256 debtToCover)
        external
        override
    {
        if (debtToCover == 0) revert InvalidAmount();
        if (riskEngine == address(0)) revert RiskEngineNotConfigured();

        // Only positions below the health-factor can be liquidated.
        uint256 healthFactor = RiskEngine(riskEngine).getHealthFactor(borrower);
        if (healthFactor >= 1e18) revert PositionNotLiquidatable();

        // The liquidator cannot cover more debt than the borrower actually owes.
        ILendingPool.UserPosition storage borrowerDebtPosition = positions[borrower][debtAsset];
        if (debtToCover > borrowerDebtPosition.borrowed) revert RepayAmountExceedsDebt();

        // The borrower must hold collateral in the requested collateral asset.
        ILendingPool.UserPosition storage borrowerCollateralPosition = positions[borrower][collateralAsset];
        if (borrowerCollateralPosition.supplied == 0) revert InsufficientCollateralForLiquidation();

        // Compute the collateral to seize.
        ProtocolConfig.AssetConfig memory collateralConfig = config.getAssetConfig(collateralAsset);
        uint256 bonusFactor = 10_000 + collateralConfig.liquidationBonusBps;
        uint256 debtValueUsd = RiskEngine(riskEngine).getAssetUsdValue(debtAsset, debtToCover);
        uint256 collateralValueWithBonus = Math.mulDiv(debtValueUsd, bonusFactor, 10_000);
        uint256 collateralToSeize =
            RiskEngine(riskEngine).getAssetAmountForUsdValue(collateralAsset, collateralValueWithBonus);

        if (collateralToSeize == 0 || collateralToSeize > borrowerCollateralPosition.supplied) {
            revert InsufficientCollateralForLiquidation();
        }

        // update borrower position
        borrowerDebtPosition.borrowed -= debtToCover;
        borrowerCollateralPosition.supplied -= collateralToSeize;

        // Pull debt tokens from the liquidator and reject short-paying tokens
        IERC20 debtToken = IERC20(debtAsset);
        uint256 poolBalanceBefore = debtToken.balanceOf(address(this));
        debtToken.safeTransferFrom(msg.sender, address(this), debtToCover);
        uint256 received = debtToken.balanceOf(address(this)) - poolBalanceBefore;
        if (received != debtToCover) revert InvalidAmount();

        // Send the seized collateral to the liquidator.
        IERC20(collateralAsset).safeTransfer(msg.sender, collateralToSeize);

        emit LiquidationExecuted(borrower, msg.sender, debtAsset, collateralAsset, debtToCover, collateralToSeize);
    }
}
