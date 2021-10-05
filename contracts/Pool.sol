// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/IShare.sol";
import "./interfaces/IDollar.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IPool.sol";

contract Pool is Ownable, ReentrancyGuard, Initializable, IPool {
    using SafeERC20 for ERC20;

    /* ========== ADDRESSES ================ */
    address public oracle;
    address public collateral;
    address public dollar;
    address public treasury;
    address public share;

    /* ========== STATE VARIABLES ========== */

    mapping(address => uint256) public redeem_share_balances;
    mapping(address => uint256) public redeem_collateral_balances;
    uint256 public pool_ceiling = 1000000001e6; // Total across all collaterals.
    uint256 public override unclaimed_pool_collateral;
    uint256 public unclaimed_pool_share;

    mapping(address => uint256) public last_redeemed;

    // Constants for various precisions
    uint256 private constant PRICE_PRECISION = 1e6;
    uint256 private constant COLLATERAL_RATIO_PRECISION = 1e6;
    uint256 private constant COLLATERAL_RATIO_MAX = 1e6;

    // 10 ** Number of decimals needed to get to 18
    uint256 private missing_decimals;

    // Number of blocks to wait before being able to collectRedemption()
    uint256 public redemption_delay = 1;

    // AccessControl state variables
    bool public mint_paused = false;
    bool public redeem_paused = false;
    bool public recollat_paused = false;

    // Recollat related
    uint256 public bonus_rate = 5000; // Bonus rate on IVORY minted during recollateralize(); 6 decimals of precision
    mapping(uint256 => uint256) public rct_hourly_cum; // Epoch hour ->  IVORY out in that hour
    uint256 public rct_max_share_out_per_hour = 0; // Infinite if 0

    /* ========== CONSTRUCTOR ========== */

    function initialize(
        address _dollar,
        address _share,
        address _collateral,
        address _treasury
    ) external initializer onlyOwner {
        dollar = _dollar;
        share = _share;
        collateral = _collateral;
        treasury = _treasury;
        missing_decimals = 10 ** (18 - ERC20(_collateral).decimals());
    }

    /* ========== VIEWS ========== */

    function info()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            bool,
            bool
        )
    {
        return (
            unclaimed_pool_collateral, // unclaimed amount of COLLATERAL
            unclaimed_pool_share, // unclaimed amount of SHARE
            getCollateralPrice(), // collateral price
            mint_paused,
            redeem_paused
        );
    }

    function collateralReserve() public view returns (address) {
        return ITreasury(treasury).collateralReserve();
    }

    function getCollateralPrice() public view override returns (uint256) {
        return IOracle(oracle).consult();
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function mint(
        uint256 _collateral_amount,
        uint256 _share_amount,
        uint256 _dollar_out_min
    ) external nonReentrant {
        require(mint_paused == false, "Minting is paused");
        (, uint256 _share_price, , uint256 _tcr, , , uint256 _minting_fee, ) = ITreasury(treasury).info();
        require(_share_price > 0, "Invalid share price");

        // Don't take in more collateral than the pool ceiling for this token allows
        require((ITreasury(treasury).globalCollateralBalance() + _collateral_amount) <= pool_ceiling, "Pool ceiling");

        uint256 _price_collateral = getCollateralPrice();
        uint256 _total_dollar_value = 0;
        uint256 _required_share_amount = 0;
        if (_tcr > 0) {
            uint256 _collateral_value = ((_collateral_amount * missing_decimals) * _price_collateral) / PRICE_PRECISION;
            _total_dollar_value = (_collateral_value * COLLATERAL_RATIO_PRECISION) / _tcr;
            if (_tcr < COLLATERAL_RATIO_MAX) {
                _required_share_amount = ((_total_dollar_value - _collateral_value) * PRICE_PRECISION) / _share_price;
            }
        } else {
            _total_dollar_value = (_share_amount * _share_price) / PRICE_PRECISION;
            _required_share_amount = _share_amount;
        }
        uint256 _actual_dollar_amount = _total_dollar_value - ((_total_dollar_value * _minting_fee) / PRICE_PRECISION);
        require(_dollar_out_min <= _actual_dollar_amount, "slippage");

        if (_required_share_amount > 0) {
            require(_required_share_amount <= _share_amount, "Not enough SHARE input");
            IShare(share).poolBurnFrom(msg.sender, _required_share_amount);
        }
        if (_collateral_amount > 0) {
            _transferCollateralToReserve(msg.sender, _collateral_amount);
        }
        IDollar(dollar).poolMint(msg.sender, _actual_dollar_amount);
    }

    function redeem(
        uint256 _dollar_amount,
        uint256 _share_out_min,
        uint256 _collateral_out_min
    ) external nonReentrant {
        require(redeem_paused == false, "Redeeming is paused");
        (, uint256 _share_price, , , uint256 _ecr, , , uint256 _redemption_fee) = ITreasury(treasury).info();
        uint256 _collateral_price = getCollateralPrice();
        require(_collateral_price > 0, "Invalid collateral price");
        require(_share_price > 0, "Invalid share price");
        uint256 _dollar_amount_post_fee = _dollar_amount - ((_dollar_amount * _redemption_fee) / PRICE_PRECISION);
        uint256 _collateral_output_amount = 0;
        uint256 _share_output_amount = 0;

        if (_ecr < COLLATERAL_RATIO_MAX) {
            uint256 _share_output_value = _dollar_amount_post_fee - ((_dollar_amount_post_fee * _ecr) / PRICE_PRECISION);
            _share_output_amount = (_share_output_value * PRICE_PRECISION) / _share_price;
        }

        if (_ecr > 0) {
            uint256 _collateral_output_value = ((_dollar_amount_post_fee * _ecr) / PRICE_PRECISION) / missing_decimals;
            _collateral_output_amount = (_collateral_output_value * PRICE_PRECISION) / _collateral_price;
        }

        // Check if collateral balance meets and meet output expectation
        uint256 _totalCollateralBalance = ITreasury(treasury).globalCollateralBalance();
        require(_collateral_output_amount <= _totalCollateralBalance, "exceed total collateral balance" );
        require(_collateral_out_min <= _collateral_output_amount && _share_out_min <= _share_output_amount, ">slippage");

        if (_collateral_output_amount > 0) {
            redeem_collateral_balances[msg.sender] = redeem_collateral_balances[msg.sender] + _collateral_output_amount;
            unclaimed_pool_collateral = unclaimed_pool_collateral + _collateral_output_amount;
        }

        if (_share_output_amount > 0) {
            redeem_share_balances[msg.sender] = redeem_share_balances[msg.sender] + _share_output_amount;
            unclaimed_pool_share = unclaimed_pool_share + _share_output_amount;
        }

        last_redeemed[msg.sender] = block.number;

        // Move all external functions to the end
        IDollar(dollar).poolBurnFrom(msg.sender, _dollar_amount);
        if (_share_output_amount > 0) {
            _mintShareToCollateralReserve(_share_output_amount);
        }
    }

    function collectRedemption() external nonReentrant {
        require((last_redeemed[msg.sender] + redemption_delay) <= block.number, "<redemption_delay");

        bool _send_share = false;
        bool _send_collateral = false;
        uint256 _share_amount;
        uint256 _collateral_amount;

        // Use Checks-Effects-Interactions pattern
        if (redeem_share_balances[msg.sender] > 0) {
            _share_amount = redeem_share_balances[msg.sender];
            redeem_share_balances[msg.sender] = 0;
            unclaimed_pool_share = unclaimed_pool_share - _share_amount;
            _send_share = true;
        }

        if (redeem_collateral_balances[msg.sender] > 0) {
            _collateral_amount = redeem_collateral_balances[msg.sender];
            redeem_collateral_balances[msg.sender] = 0;
            unclaimed_pool_collateral = unclaimed_pool_collateral - _collateral_amount;
            _send_collateral = true;
        }

        if (_send_share) {
            _requestTransferShare(msg.sender, _share_amount);
        }

        if (_send_collateral) {
            _requestTransferCollateral(msg.sender, _collateral_amount);
        }
    }

    // When the protocol is recollateralizing, we need to give a discount of IVORY to hit the new CR target
    // Thus, if the target collateral ratio is higher than the actual value of collateral, minters get IVORY for adding collateral
    // This function simply rewards anyone that sends collateral to a pool with the same amount of IVORY + the bonus rate
    // Anyone can call this function to recollateralize the protocol and take the extra IVORY value from the bonus rate as an arb opportunity
    function recollateralize(uint256 _collateral_amount, uint256 _share_out_min) external returns (uint256 share_out) {
        require(recollat_paused == false, "Recollat is paused");

        // Don't take in more collateral than the pool ceiling for this token allows
        require((ITreasury(treasury).globalCollateralBalance() + _collateral_amount) <= pool_ceiling, "Pool ceiling");

        uint256 _collateral_amount_d18 = _collateral_amount * missing_decimals;
        uint256 _share_price = ITreasury(treasury).sharePrice();

        // Get the amount of IVORY actually available (accounts for throttling)
        uint256 _share_actually_available = recollatAvailableShare();

        // Calculated the attempted amount of IVORY
        uint256 _collat_price = getCollateralPrice();
        share_out = _collateral_amount_d18 * _collat_price * (PRICE_PRECISION + bonus_rate) / PRICE_PRECISION / _share_price;

        // Make sure there is IVORY available
        require(share_out <= _share_actually_available, "Insuf IVORY Avail For RCT");

        // Check slippage
        require(share_out >= _share_out_min, "IVORY slippage");

        // Take in the collateral and pay out the IVORY
        _transferCollateralToReserve(msg.sender, _collateral_amount);
        IShare(share).poolMint(msg.sender, share_out);

        // Increment the outbound IVORY, in E18
        // Used for recollat throttling
        rct_hourly_cum[curEpochHr()] += share_out;

        emit Recollateralized(_collateral_amount, share_out);
    }

    // Returns the missing amount of collateral (in E18) needed to maintain the collateral ratio
    function recollatTheoColAvailableE18() public view returns (uint256) {
        uint256 _share_total_supply = ERC20(share).totalSupply();

        (, , , uint256 _tcr, uint256 _ecr, , ,) = ITreasury(treasury).info();

        uint256 _desired_collat_e24 = _tcr * _share_total_supply;
        uint256 _effective_collat_e24 = _ecr * _share_total_supply;

        // Return 0 if already overcollateralized
        // Otherwise, return the deficiency
        if (_effective_collat_e24 >= _desired_collat_e24) return 0;
        else {
            return (_desired_collat_e24 - _effective_collat_e24) / COLLATERAL_RATIO_PRECISION;
        }
    }

    // Returns the value of IVORY available to be used for recollats
    // Also has throttling to avoid dumps during large price movements
    function recollatAvailableShare() public view returns (uint256) {
        uint256 _share_price = ITreasury(treasury).sharePrice();

        // Get the amount of collateral theoretically available
        uint256 _recollat_theo_available_e18 = recollatTheoColAvailableE18();

        // Get the amount of IVORY theoretically outputtable
        uint256 _share_theo_out = _recollat_theo_available_e18 * PRICE_PRECISION / _share_price;

        // See how much IVORY has been issued this hour
        uint256 current_hr_rct = rct_hourly_cum[curEpochHr()];

        // Account for the throttling
        return comboCalcBbkRct(current_hr_rct, rct_max_share_out_per_hour, _share_theo_out);
    }

    // Returns the current epoch hour
    function curEpochHr() public view returns (uint256) {
        return (block.timestamp / 3600); // Truncation desired
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _transferCollateralToReserve(address _sender, uint256 _amount) internal {
        address _reserve = collateralReserve();
        require(_reserve != address(0), "Invalid reserve address");
        ERC20(collateral).safeTransferFrom(_sender, _reserve, _amount);
    }

    function _mintShareToCollateralReserve(uint256 _amount) internal {
        address _reserve = collateralReserve();
        require(_reserve != address(0), "Invalid reserve address");
        IShare(share).poolMint(_reserve, _amount);
    }

    function _requestTransferCollateral(address _receiver, uint256 _amount) internal {
        ITreasury(treasury).requestTransfer(collateral, _receiver, _amount);
    }

    function _requestTransferShare(address _receiver, uint256 _amount) internal {
        ITreasury(treasury).requestTransfer(share, _receiver, _amount);
    }

    function comboCalcBbkRct(uint256 _cur, uint256 _max, uint256 _theo) internal pure returns (uint256) {
        if (_max == 0) {
            // If the hourly limit is 0, it means there is no limit
            return _theo;
        }
        else if (_cur >= _max) {
            // If the hourly limit has already been reached, return 0;
            return 0;
        }
        else {
            // Get the available amount
            uint256 _available = _max - _cur;

            if (_theo >= _available) {
                // If the the theoretical is more than the available, return the available
                return _available;
            }
            else {
                // Otherwise, return the theoretical amount
                return _theo;
            }
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function toggleMinting() external onlyOwner {
        mint_paused = !mint_paused;
        emit MintingToggled();
    }

    function toggleRedeeming() external onlyOwner {
        redeem_paused = !redeem_paused;
        emit RedeemingToggled();
    }

    function toggleRecollat() external onlyOwner {
        recollat_paused = !recollat_paused;
        emit RecollatToggled();
    }

    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Invalid address");
        oracle = _oracle;
        emit OracleUpdated(oracle);
    }

    function setRedemptionDelay(uint256 _redemption_delay) external onlyOwner {
        redemption_delay = _redemption_delay;
        emit RedemptionDelayUpdate(redemption_delay);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid address");
        treasury = _treasury;
        emit TreasuryChanged(_treasury);
    }

    function setBonusRate(uint256 _rate) external onlyOwner {
        bonus_rate = _rate;
        emit BonusRateChanged(bonus_rate);
    }

    function setMaxPerHour(uint256 _max) external onlyOwner {
        rct_max_share_out_per_hour = _max;
        emit MaxPerHourChanged(rct_max_share_out_per_hour);
    }

    function setPoolCeiling(uint256 _ceiling) external onlyOwner {
        pool_ceiling = _ceiling;
        emit PoolCeilingChanged(_ceiling);
    }


    // EVENTS
    event TreasuryChanged(address indexed newTreasury);
    event MintingToggled();
    event RedeemingToggled();
    event RecollatToggled();
    event OracleUpdated(address indexed newOracle);
    event RedemptionDelayUpdate(uint redemptionDelay);
    event Recollateralized(uint256 col_amount, uint256 share_out);
    event BonusRateChanged(uint256 rate);
    event MaxPerHourChanged(uint256 max);
    event PoolCeilingChanged(uint256 ceiling);
}
