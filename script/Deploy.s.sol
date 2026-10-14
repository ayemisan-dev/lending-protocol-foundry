// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {ProtocolConfig} from "../src/core/ProtocolConfig.sol";
import {OracleReader} from "../src/oracles/OracleReader.sol";
import {LendingPool} from "../src/core/LendingPool.sol";
import {RiskEngine} from "../src/core/RiskEngine.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockAggregatorV3} from "../src/mocks/MockAggregatorV3.sol";

/// @notice Deploys the LendX protocol with one test asset on any EVM chain.
contract DeployLendX is Script {
    uint256 internal constant MAX_PRICE_AGE = 1 days;

    function run() external {
        vm.startBroadcast();

        address deployer = msg.sender;
        ProtocolConfig config = new ProtocolConfig(deployer);
        OracleReader oracle = new OracleReader(deployer, MAX_PRICE_AGE);
        LendingPool pool = new LendingPool(deployer);
        pool.setProtocolConfig(address(config));
        RiskEngine riskEngine = new RiskEngine(address(config), address(oracle), address(pool));
        pool.setRiskEngine(address(riskEngine));

        MockERC20 testToken = new MockERC20("LendX Test USD", "tUSD");
        MockAggregatorV3 testFeed = new MockAggregatorV3(8, 1e8, 1, block.timestamp, 1); // $1.00

        config.configureAsset(address(testToken), true, 8000, 8500, 500);
        oracle.setPriceFeed(address(testToken), address(testFeed));

        vm.stopBroadcast();

        console2.log("Deployer:      ", deployer);
        console2.log("ProtocolConfig:", address(config));
        console2.log("OracleReader:  ", address(oracle));
        console2.log("LendingPool:   ", address(pool));
        console2.log("RiskEngine:    ", address(riskEngine));
        console2.log("TestToken:     ", address(testToken));
        console2.log("TestFeed:      ", address(testFeed));
    }
}
