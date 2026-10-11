// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test, Vm} from "forge-std/Test.sol";
import {ProtocolConfig} from "../../src/core/ProtocolConfig.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

contract ProtocolConfigTest is Test {
    ProtocolConfig internal config;
    MockERC20 internal mockAsset;
    address internal asset;
    address internal owner = makeAddr("owner");

    function setUp() public {
        config = new ProtocolConfig(owner);
        mockAsset = new MockERC20("Mock USD Coin", "mUSDC");
        asset = address(mockAsset);
    }

    function test_OwnerIsInitialized() public view {
        assertEq(config.owner(), owner);
    }

    function test_OwnerCanTransferOwnership() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        config.transferOwnership(newOwner);
        assertEq(config.owner(), newOwner);
    }

    function test_NonOwnerCannotTransferOwnership() public {
        address attacker = makeAddr("attacker");
        address newOwner = makeAddr("newOwner");
        vm.prank(attacker);
        vm.expectRevert();
        config.transferOwnership(newOwner);
    }

    function test_OwnerCanConfigureAsset() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ProtocolConfig.AssetConfigUpdated(asset, true, 8000, 8500, 500);
        config.configureAsset(asset, true, 8000, 8500, 500);
        ProtocolConfig.AssetConfig memory assetConfig = config.getAssetConfig(asset);

        assertTrue(assetConfig.enabled);
        assertEq(assetConfig.ltvBps, 8000);
        assertEq(assetConfig.liquidationThresholdBps, 8500);
        assertEq(assetConfig.liquidationBonusBps, 500);
    }

    function test_NonOwnerCannotConfigureAsset() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        config.configureAsset(asset, true, 8000, 8500, 500);
        ProtocolConfig.AssetConfig memory assetConfig = config.getAssetConfig(asset);

        assertFalse(assetConfig.enabled);
        assertEq(assetConfig.ltvBps, 0);
        assertEq(assetConfig.liquidationThresholdBps, 0);
        assertEq(assetConfig.liquidationBonusBps, 0);
    }

    function test_RevertWhenLtvExceedsMaximum() public {
        vm.prank(owner);
        vm.expectRevert(ProtocolConfig.InvalidLtv.selector);
        config.configureAsset(asset, true, 10001, 8500, 500);
    }

    function test_RevertWhenLiquidationThresholdExceedsMaximum() public {
        vm.prank(owner);
        vm.expectRevert(ProtocolConfig.InvalidLiquidationThreshold.selector);
        config.configureAsset(asset, true, 8000, 10_001, 500);
    }

    function test_RevertWhenLtvExceedsLiquidationThreshold() public {
        vm.prank(owner);
        vm.expectRevert(ProtocolConfig.InvalidLtvThresholdRelation.selector);
        config.configureAsset(asset, true, 9000, 8500, 500);
    }

    function test_RevertWhenLiquidationBonusExceedsMaximum() public {
        vm.prank(owner);
        vm.expectRevert(ProtocolConfig.InvalidLiquidationBonus.selector);
        config.configureAsset(asset, true, 8000, 8500, 10001);
    }

    function test_RevertWhenAssetIsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ProtocolConfig.InvalidAsset.selector);
        config.configureAsset(address(0), true, 8000, 8500, 10001);
    }

    function test_OwnerCanUpdateAssetConfig() public {
        vm.startPrank(owner);
        config.configureAsset(asset, true, 8000, 8500, 500);

        vm.expectEmit(true, false, false, true);
        emit ProtocolConfig.AssetConfigUpdated(asset, true, 7500, 8000, 300);
        config.configureAsset(asset, true, 7500, 8000, 300);
        vm.stopPrank();

        ProtocolConfig.AssetConfig memory assetConfig = config.getAssetConfig(asset);

        assertTrue(assetConfig.enabled);
        assertEq(assetConfig.ltvBps, 7500);
        assertEq(assetConfig.liquidationThresholdBps, 8000);
        assertEq(assetConfig.liquidationBonusBps, 300);
    }

    function test_OwnerCanDisableAsset() public {
        vm.startPrank(owner);
        config.configureAsset(asset, true, 8000, 8500, 500);
        config.configureAsset(asset, false, 8000, 8500, 500);
        vm.stopPrank();

        ProtocolConfig.AssetConfig memory assetConfig = config.getAssetConfig(asset);

        assertFalse(assetConfig.enabled);
        assertEq(assetConfig.ltvBps, 8000);
        assertEq(assetConfig.liquidationThresholdBps, 8500);
        assertEq(assetConfig.liquidationBonusBps, 500);
    }

    function test_OwnerCanReenableAsset() public {
        vm.startPrank(owner);
        config.configureAsset(asset, true, 8000, 8500, 500);
        config.configureAsset(asset, false, 8000, 8500, 500);
        config.configureAsset(asset, true, 8000, 8500, 500);
        vm.stopPrank();

        ProtocolConfig.AssetConfig memory assetConfig = config.getAssetConfig(asset);

        assertTrue(assetConfig.enabled);
        assertEq(assetConfig.ltvBps, 8000);
        assertEq(assetConfig.liquidationThresholdBps, 8500);
        assertEq(assetConfig.liquidationBonusBps, 500);
    }

    function test_RevertWhenInvalidConfigDoesNotEmitEvent() public {
        vm.prank(owner);
        vm.recordLogs();
        vm.expectRevert(ProtocolConfig.InvalidLtv.selector);
        config.configureAsset(asset, true, 10001, 8500, 500);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
    }

    function test_ConfiguredAssetIsIncludedInAssetList() public {
        vm.prank(owner);
        config.configureAsset(asset, true, 8000, 8500, 500);

        address[] memory assets = config.getConfiguredAssets();

        assertEq(assets.length, 1);
        assertEq(assets[0], asset);
    }

    function test_UpdatingAssetConfigDoesNotDuplicateAsset() public {
        vm.startPrank(owner);
        config.configureAsset(asset, true, 8000, 8500, 500);
        config.configureAsset(asset, true, 7500, 8000, 300);
        vm.stopPrank();

        address[] memory assets = config.getConfiguredAssets();

        assertEq(assets.length, 1);
        assertEq(assets[0], asset);
    }

    function test_DisabledAssetRemainsInConfiguredAssetList() public {
        vm.startPrank(owner);
        config.configureAsset(asset, true, 8000, 8500, 500);
        config.configureAsset(asset, false, 8000, 8500, 500);
        vm.stopPrank();

        address[] memory assets = config.getConfiguredAssets();

        assertEq(assets.length, 1);
        assertEq(assets[0], asset);

        ProtocolConfig.AssetConfig memory assetConfig = config.getAssetConfig(asset);

        assertFalse(assetConfig.enabled);
    }
}
