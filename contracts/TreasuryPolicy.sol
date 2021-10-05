// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ITreasuryPolicy.sol";

contract TreasuryPolicy is Ownable, Initializable, ITreasuryPolicy {
    address public treasury;

    // Constants for various precisions
    uint256 private constant PRICE_PRECISION = 1e6;
    uint256 private constant RATIO_PRECISION = 1e6;

    uint256 public override idleCollateralUtilizationRatio; // ratio where idle collateral can be used for investment
    uint256 public constant IDLE_COLLATERAL_UTILIZATION_RATION_MAX = 800000; // no more than 80%

    uint256 public override reservedCollateralThreshold; // ratio of the threshold where collateral are reserved for redemption
    uint256 public constant RESERVE_COLLATERAL_THRESHOLD_MIN = 150000; // no less than 15%

    // fees
    uint256 public override redemption_fee; // 6 decimals of precision
    uint256 public constant REDEMPTION_FEE_MAX = 9000; // 0.9%

    uint256 public override minting_fee; // 6 decimals of precision
    uint256 public constant MINTING_FEE_MAX = 5000; // 0.5%

    uint256 public override excess_collateral_safety_margin;
    uint256 public constant EXCESS_COLLATERAL_SAFETY_MARGIN_MIN = 150000; // 15%

    /* ========== EVENTS ============= */

    event TreasuryUpdated(address indexed newTreasury);
    event RedemptionFeeUpdated(uint256 newFee);
    event MintingFeeUpdated(uint256 newFee);
    event ExcessCollateralSafetyMarginUpdated(uint256 newSafetyMargin);
    event IdleCollateralUtilizationRatioUpdated(uint256 newUtilRatio);
    event ReservedCollateralThresholdUpdated(uint256 newThreshold);

    function initialize(
        address _treasury,
        uint256 _minting_fee,
        uint256 _redemption_fee,
        uint256 _excess_collateral_safety_margin,
        uint256 _idleCollateralUtilizationRatio,
        uint256 _reservedCollateralThreshold
    ) external initializer onlyOwner {
        setTreasury(_treasury);
        setMintingFee(_minting_fee);
        setRedemptionFee(_redemption_fee);
        setExcessCollateralSafetyMargin(_excess_collateral_safety_margin);
        setIdleCollateralUtilizationRatio(_idleCollateralUtilizationRatio);
        setReservedCollateralThreshold(_reservedCollateralThreshold);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setTreasury(address _treasury) public onlyOwner {
        require(_treasury != address(0), "Invalid address");
        treasury = _treasury;
        emit TreasuryUpdated(treasury);
    }

    function setRedemptionFee(uint256 _redemption_fee) public onlyOwner {
        require(_redemption_fee <= REDEMPTION_FEE_MAX, ">REDEMPTION_FEE_MAX");
        redemption_fee = _redemption_fee;
        emit RedemptionFeeUpdated(redemption_fee);
    }

    function setMintingFee(uint256 _minting_fee) public onlyOwner {
        require(_minting_fee <= MINTING_FEE_MAX, ">MINTING_FEE_MAX");
        minting_fee = _minting_fee;
        emit MintingFeeUpdated(minting_fee);
    }

    function setExcessCollateralSafetyMargin(uint256 _excess_collateral_safety_margin) public onlyOwner {
        require(
            _excess_collateral_safety_margin >= EXCESS_COLLATERAL_SAFETY_MARGIN_MIN,
            "<EXCESS_COLLATERAL_SAFETY_MARGIN_MIN"
        );
        excess_collateral_safety_margin = _excess_collateral_safety_margin;
        emit ExcessCollateralSafetyMarginUpdated(excess_collateral_safety_margin);
    }

    function setIdleCollateralUtilizationRatio(uint256 _idleCollateralUtilizationRatio) public onlyOwner {
        require(
            _idleCollateralUtilizationRatio <= IDLE_COLLATERAL_UTILIZATION_RATION_MAX,
            ">IDLE_COLLATERAL_UTILIZATION_RATION_MAX"
        );
        idleCollateralUtilizationRatio = _idleCollateralUtilizationRatio;
        emit IdleCollateralUtilizationRatioUpdated(idleCollateralUtilizationRatio);
    }

    function setReservedCollateralThreshold(uint256 _reservedCollateralThreshold) public onlyOwner {
        require(_reservedCollateralThreshold >= RESERVE_COLLATERAL_THRESHOLD_MIN, "<RESERVE_COLLATERAL_THRESHOLD_MIN");
        reservedCollateralThreshold = _reservedCollateralThreshold;
        emit ReservedCollateralThresholdUpdated(reservedCollateralThreshold);
    }
}
