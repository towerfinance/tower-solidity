// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IPairOracle.sol";

contract MockPairOracle is IPairOracle, Ownable {
    uint256 public mockPrice;
    uint256 internal constant PRICE_PRECISION = 1e6;
    uint256 public PERIOD = 600; // 10-minute TWAP (time-weighted average price)

    constructor(uint256 _mockPrice) {
        mockPrice = _mockPrice;
    }

    function forceUpdateAndSetPeriod(uint256 _period) external onlyOwner {
        PERIOD = _period;
    }

    function consult(address, uint256 amountIn) external view override returns (uint256 amountOut) {
        return (mockPrice * amountIn) / PRICE_PRECISION;
    }

    function update() external override {}

    function setPeriod(uint256 _period) external onlyOwner {
        PERIOD = _period;
    }

    function mock(uint256 _mockPrice) external {
        mockPrice = _mockPrice;
    }
}
