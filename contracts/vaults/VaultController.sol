// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../interfaces/ITreasuryVault.sol";
import "../interfaces/IUniswapV2Router.sol";
import "../interfaces/IFirebirdRouter.sol";
import "../ERC20/ERC20Custom.sol";

contract VaultController is Ownable, Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public admin;
    address public collateralReserve;
    address private usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174; // usdc
    address private wmatic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270; // wmatic
    address private share;
    ITreasuryVault public treasuryVault;

    uint256 private constant RATIO_PRECISION = 1000000; // 6 decimals
    uint256 private constant swapTimeout = 900; // 15 minutes approx.
    uint256 public slippage = 20000; // 6 decimals (2%)

    struct SwapInfo {
        address router;
        address[] swapPath;
    }
    mapping(address => SwapInfo) public swapInfo;

    // events
    event AdminChanged(address indexed newAdmin);
    event TreasuryHarvested(address indexed incentive, uint256 amount);
    event ShareBurnt(uint256 amount);
    event CollateralReserveUpdated(address indexed newCollateralReserve);
    event SwapOptionsUpdated(address indexed router, address[] swapPath);

    // modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin || msg.sender == owner(), "Only admin or owner can trigger this function");
        _;
    }

    // constructor
    function initialize(
        address _treasuryVault,
        address _admin,
        address _collateralReserve,
        address _share
    ) external initializer onlyOwner {
        treasuryVault = ITreasuryVault(_treasuryVault);
        setAdmin(_admin);
        setCollateralReserve(_collateralReserve);
        share = _share;
    }

    function claimIncentiveRewardsAndBurn() external onlyAdmin nonReentrant {
        require(collateralReserve != address(0), "No collateral reserve defined");
        require(share != address(0), "No share defined");

        treasuryVault.claimIncentiveRewards();

        // swap incentive to collateral
        uint256 _incentiveBalance = IERC20(wmatic).balanceOf(address(this));
        _swapQuickswap(wmatic, usdc, _incentiveBalance);

        // swap collateral to share
        uint256 _collateralBalance = IERC20(usdc).balanceOf(address(this));
        _swapFirebird(usdc, share, _collateralBalance);

        // burn share
        uint256 _shareBalance = IERC20(share).balanceOf(address(this));
        ERC20Custom(share).burn(_shareBalance);

        emit TreasuryHarvested(usdc, _collateralBalance);
        emit ShareBurnt(_shareBalance);
    }

    function _swapQuickswap(
        address _inputToken,
        address _outputToken,
        uint256 _inputAmount
    ) internal {
        if (_inputAmount == 0) {
            return;
        }
        SwapInfo memory _info = swapInfo[_inputToken];
        require(_info.router != address(0), "invalid route");
        require(_info.swapPath[_info.swapPath.length - 1] == _outputToken, "invalid path");
        IERC20(_inputToken).safeApprove(_info.router, 0);
        IERC20(_inputToken).safeApprove(_info.router, _inputAmount);

        IUniswapV2Router _swapRouter = IUniswapV2Router(_info.router);
        uint256[] memory _amounts = _swapRouter.getAmountsOut(_inputAmount, _info.swapPath);
        uint256 _minAmountOut = (_amounts[_amounts.length - 1] * (RATIO_PRECISION - slippage)) / RATIO_PRECISION;

        _swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _inputAmount,
            _minAmountOut,
            _info.swapPath,
            address(this),
            block.timestamp + swapTimeout
        );
    }

    function _swapFirebird(
        address _inputToken,
        address _outputToken,
        uint256 _inputAmount
    ) internal {
        if (_inputAmount == 0) {
            return;
        }
        SwapInfo memory _info = swapInfo[_inputToken];
        require(_info.router != address(0), "invalid route");
        require(_info.swapPath[_info.swapPath.length - 1] == _outputToken, "invalid path");
        IERC20(_inputToken).safeApprove(_info.router, 0);
        IERC20(_inputToken).safeApprove(_info.router, _inputAmount);

        IFirebirdRouter _swapRouter = IFirebirdRouter(_info.router);
        uint256[] memory _amounts = _swapRouter.getAmountsOut(_inputToken, _outputToken, _inputAmount, _info.swapPath);
        uint256 _minAmountOut = (_amounts[_amounts.length - 1] * (RATIO_PRECISION - slippage)) / RATIO_PRECISION;

        _swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _inputToken,
            _outputToken,
            _inputAmount,
            _minAmountOut,
            _info.swapPath,
            address(this),
            block.timestamp + swapTimeout
        );
    }

    // ===== OWNERS FUNCTIONS ===============

    function setAdmin(address _admin) public onlyOwner {
        require(_admin != address(0), "Invalid address");
        admin = _admin;
        emit AdminChanged(_admin);
    }

    function setSwapOptions(address _router, address[] calldata _path) public onlyOwner {
        require(_router != address(0), "Invalid address");
        require(_path.length > 1, "Invalid path");
        require(_path[0] == address(wmatic) || _path[0] == address(usdc), "Path must start with wmatic or usdc");
        require(_path[_path.length - 1] == address(usdc) || _path[_path.length - 1] == address(share), "Path must end with usdc or ivory");

        swapInfo[_path[0]] = SwapInfo(_router, _path);
        SwapInfo memory _info = swapInfo[_path[0]];
        emit SwapOptionsUpdated(_info.router, _info.swapPath);
    }

    function setCollateralReserve(address _collateralReserve) public onlyOwner {
        require(_collateralReserve != address(0), "Invalid address");
        collateralReserve = _collateralReserve;
        emit CollateralReserveUpdated(collateralReserve);
    }

    function executeTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data
    ) public onlyOwner returns (bytes memory) {
        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }
        // solium-disable-next-line security/no-call-value
        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        require(success, string("VaultController::executeTransaction: Transaction execution reverted."));
        return returnData;
    }

    receive() external payable {}
}
