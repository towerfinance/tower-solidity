//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockFirebirdRouter {
    using SafeERC20 for ERC20;

    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(deadline > 0, "deadline");
        require(tokenIn != address(0), "tokenIn");
        require(tokenOut != address(0), "tokenOut");

        uint112 reserve0 = 1000000000000000000000;
        uint112 reserve1 = 1000000000;
        uint256 amountToUse = amountIn - (amountIn * 2000 / 1e6);

        amounts = new uint[](2);
        amounts[0] = amountIn;
        amounts[1] = (reserve0 * 1e6 / (reserve1 + amountToUse)) * amountToUse / 1e6;

        require(amounts[1] > amountOutMin, "slippage");

        ERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        ERC20 share = ERC20(path[path.length - 1]);
        share.safeTransfer(to, amounts[1]);
    }
}
