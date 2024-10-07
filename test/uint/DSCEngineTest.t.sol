// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer; //用于部署 DSC 和 DSCEngine 的 DeployDSC 实例
    DecentralizedStableCoin dsc; //已部署的 DecentralizedStableCoin 实例
    DSCEngine dsce; //已部署的 DSCEngine 实例
    HelperConfig config; //用于获取价格预言机和 WETH 地址
    address ethUsdPriceFeed; //ETH/USD 的价格预言机地址
    address weth; //WETH 代币的地址

    address public USER = makeAddr("user"); //用于模拟测试环境中的用户地址
    uint256 public constant AMOUNT_COLLATERAL = 10 ether; //用户提供的抵押物数量
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether; //账户初始ERC20代币余额

    function setUp() public {
        deployer = new DeployDSC(); // 实例化部署者
        (dsc, dsce, config) = deployer.run(); // 部署 DSC、DSCEngine，并获取配置
        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig(); // 获取 WETH 地址和价格预言机

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE); // 为用户铸造初始的 WETH 代币
    }

    //////////////////price tests////////////////////
    // 检查 DSCEngine 合约的 getUsdValue 函数是否正确计算出 WETH 的美元价值
    function testGetUsdValue() public {
        // 15e18 * 2,000/ETH = 30,000e18
        uint256 ethAmount = 15e18; // 15 ETH
        uint256 expectedUsd = 30000e18; // 预期的 USD 值（30000 USD）
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount); // 调用 DSCEngine 获取实际 USD 值
        assertEq(expectedUsd, actualUsd); // 断言预期值和实际值是否相等
    }

    //////////////////depositColleteral tests////////////////////
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER); // 以用户身份开始交易
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL); // 用户批准将 WETH 抵押到 DSCEngine

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector); // 预期交易会失败，并且失败原因是 'NeedsMoreThanZero'
        dsce.depositCollateral(weth, 0); // 尝试存入 0 WETH 作为抵押品，应该失败
        vm.stopPrank(); // 停止用户身份
    }
}
