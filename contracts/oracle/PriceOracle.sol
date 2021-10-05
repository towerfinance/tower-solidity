// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IPairOracle.sol";

contract PriceOracle is Ownable, IOracle {
    address public oracleTokenCollateral;
    address public oracleCollateralUsd;
    address public token;

    uint256 public missingDecimals;
    uint256 private constant PRICE_PRECISION = 1e6;

    event OracleTokenCollateralUpdated(address indexed newOracleDollarCollateral);
    event OracleCollateralUsdUpdated(address indexed newOracleCollateralUsd);

    constructor(
        address _token,
        address _oracleTokenCollateral,
        address _oracleCollateralUsd,
        uint256 _missingDecimals
    ) {
        token = _token;
        oracleTokenCollateral = _oracleTokenCollateral;
        oracleCollateralUsd = _oracleCollateralUsd;
        missingDecimals = 10**_missingDecimals;
    }

    function consult() external view override returns (uint256) {
        uint256 _priceCollateralUsd = IOracle(oracleCollateralUsd).consult();
        uint256 _priceTokenCollateral =
            IPairOracle(oracleTokenCollateral).consult(
                token,
                PRICE_PRECISION * missingDecimals
            );
        return (_priceCollateralUsd * _priceTokenCollateral) / PRICE_PRECISION;
    }

    function setOracleTokenCollateral(address _oracleTokenCollateral) external onlyOwner {
        oracleTokenCollateral = _oracleTokenCollateral;
        emit OracleTokenCollateralUpdated(oracleTokenCollateral);
    }

    function setOracleCollateralUsd(address _oracleCollateralUsd) external onlyOwner {
        oracleCollateralUsd = _oracleCollateralUsd;
        emit OracleCollateralUsdUpdated(oracleCollateralUsd);
    }
}
