// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IFirebirdRouter.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IShare.sol";
import "./interfaces/IDollar.sol";
import "./ERC20/ERC20Custom.sol";
import "./libs/Babylonian.sol";


contract ZapPool is Ownable, ReentrancyGuard, Initializable {
    using SafeERC20 for ERC20;
    using Address for address;

    /* ========== STATE VARIABLES ========== */

    IOracle public oracle;
    IDollar public dollar;
    ERC20 public collateral;
    IShare public share;
    ITreasury public treasury;
    uint256 private missing_decimals;

    IFirebirdRouter public router;
    address[] public router_path;
    IUniswapV2Pair public pair;

    // Constants for various precisions
    uint256 private constant PRICE_PRECISION = 1e6;
    uint256 private constant RATIO_PRECISION = 1e6;
    uint256 private constant SHARE_PRECISION = 1e18;
    uint256 private constant COLLATERAL_RATIO_MAX = 1e6;
    uint256 private constant SLIPPAGE_MAX = 100000; // 10%
    uint256 private constant LIMIT_SWAP_TIME = 10 minutes;
    uint256 private constant SWAP_FEE_MAX = 20000; // 2%
    uint256 public slippage = 50000;
    uint256 public swap_fee = 2000; // 0.2%
    // AccessControl state variables
    bool public mint_paused = false;

    modifier notContract() {
        require(!msg.sender.isContract(), "Allow non-contract only");
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    function initialize(
        ITreasury _treasury,
        IDollar _dollar,
        IShare _share,
        ERC20 _collateral,
        IOracle _oracleCollateral
    ) external initializer onlyOwner {
        treasury = _treasury;
        dollar = _dollar;
        share = _share;
        collateral = _collateral;
        oracle = _oracleCollateral;
        missing_decimals = 10**(18 - _collateral.decimals());
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function collateralReserve() public view returns (address) {
        return treasury.collateralReserve();
    }

    function getCollateralPrice() public view returns (uint256) {
        return oracle.consult();
    }

    function unclaimed_pool_collateral() public pure returns (uint256) {
        return 0; // to avoid treasury call exception
    }

    function zapMint(uint256 _collateral_amount, uint256 _dollar_out_min) external notContract nonReentrant {
        require(mint_paused == false, "Minting is paused");
        (, uint256 _share_price, , uint256 _tcr, , , uint256 _minting_fee, ) = ITreasury(treasury).info();
        require(_share_price > 0, "Invalid share price");

        uint256 _col_amount_after_fee = _collateral_amount - (_collateral_amount * _minting_fee / PRICE_PRECISION);

        uint256 _col_price = getCollateralPrice();
        uint256 _dollar_amount = _col_amount_after_fee * missing_decimals * _col_price / PRICE_PRECISION;

        uint256 _col_amount_to_buy = 0;
        if (_tcr < COLLATERAL_RATIO_MAX) {
            _col_amount_to_buy = _calculateAmountToBuyShare(_col_amount_after_fee, _tcr, _col_price, _share_price);
            _dollar_amount = _dollar_amount - (_col_amount_to_buy * swap_fee * _col_price / RATIO_PRECISION / PRICE_PRECISION);
        }
        require(_dollar_amount >= _dollar_out_min, "slippage");

        collateral.safeTransferFrom(msg.sender, address(this), _collateral_amount);
        if (_col_amount_to_buy > 0) {
            collateral.safeApprove(address(router), 0);
            collateral.safeApprove(address(router), _col_amount_to_buy);
            uint256[] memory _received_amounts = router.swapExactTokensForTokens(
                address(collateral), address(share),
                _col_amount_to_buy, 1, router_path, address(this), block.timestamp + LIMIT_SWAP_TIME);
            emit ZapSwapped(_col_amount_to_buy, _received_amounts[_received_amounts.length - 1]);
        }

        uint256 _share_balance = ERC20(address(share)).balanceOf(address(this));
        uint256 _col_balance = collateral.balanceOf(address(this));
        if (_share_balance > 0) {
            ERC20Custom(address(share)).burn(_share_balance);
        }
        if (_col_balance > 0) {
            _transferCollateralToReserve(_col_balance); // transfer all collateral to reserve no matter what;
        }
        dollar.poolMint(msg.sender, _dollar_amount);
    }

    function _transferCollateralToReserve(uint256 _amount) internal {
        address _reserve = collateralReserve();
        require(_reserve != address(0), "Invalid reserve address");
        collateral.safeTransfer(_reserve, _amount);
        emit TransferedCollateral(_amount);
    }

    function _calculateAmountToBuyShare(uint256 _col_amount, uint256 _tcr, uint256 _col_price, uint256 _share_price) internal view returns (uint256) {
        (uint256 _r0, uint256 _r1, ) = pair.getReserves(); // r0 = USDC, r1 = IVORY
        uint256 _r_swap_fee = RATIO_PRECISION - swap_fee;

        uint256 _k = (RATIO_PRECISION * RATIO_PRECISION / _tcr) - RATIO_PRECISION;
        uint256 _b = _r0
                    + (_r_swap_fee * _r1  * _share_price * RATIO_PRECISION * PRICE_PRECISION / SHARE_PRECISION / PRICE_PRECISION / _k / _col_price)
                    - (_col_amount * _r_swap_fee / PRICE_PRECISION);

        uint256 _tmp = (_b * _b / PRICE_PRECISION) + (4 * _r_swap_fee * _col_amount * _r0 / PRICE_PRECISION / PRICE_PRECISION);

        return (Babylonian.sqrt(_tmp * PRICE_PRECISION) - _b) * RATIO_PRECISION / (2 * _r_swap_fee);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function toggleMinting() external onlyOwner {
        mint_paused = !mint_paused;
        emit MintingToggled();
    }

    function setSlippage(uint256 _slippage) external onlyOwner {
        require(_slippage <= SLIPPAGE_MAX, "SLIPPAGE TOO HIGH");
        slippage = _slippage;
        emit SlippageUpdated(slippage);
    }

    function setOracle(IOracle _oracle) external onlyOwner {
        require(address(_oracle) != address(0), "Invalid address");
        oracle = _oracle;
        emit OracleUpdated(address(oracle));
    }

    function setRouter(address _router, address[] calldata _path) external onlyOwner {
        require(_router != address(0), "Invalid router");
        router = IFirebirdRouter(_router);
        router_path = _path;
        emit RouterUpdated(_router);
    }

    function setPair(address _pair) external onlyOwner {
        require(_pair != address(0), "Invalid pair");
        pair = IUniswapV2Pair(_pair);
        emit SetUniswapPair(_pair);
    }

    function setSwapFee(uint256 _fee) external onlyOwner {
        require(_fee <= SWAP_FEE_MAX, "Swap fee too high");
        swap_fee = _fee;
        emit SwapFeeChanged(swap_fee);
    }

    event TransferedCollateral(uint256 indexed collateralAmount);
    event ZapSwapped(uint256 indexed collateralAmount, uint256 indexed shareAmount);
    event MintingToggled();
    event SlippageUpdated(uint256 newSlippage);
    event OracleUpdated(address indexed newOracle);
    event RouterUpdated(address indexed newRouter);
    event SwapFeeChanged(uint256 indexed swapFee);
    event SetUniswapPair(address indexed pairAddress);
}
