pragma solidity ^0.8.18;

import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";


contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    constructor(DSCEngine _engine, DecentralizedStableCoin _dsc) {
        dsce = _engine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    // Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    function depositCollateral (uint256 collateralSeed, uint256 amountCollateral) public {
    ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    dsce.depositCollateral(address(collateral), amountCollateral);
}
}
