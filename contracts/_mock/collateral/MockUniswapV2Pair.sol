// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

contract MockUniswapV2Pair {
    function getReserves() external pure returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) {
        reserve0 = 1000000000;
        reserve1 = 1000000000000000000000;
        blockTimestampLast = 0;
    }
}
