// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/ITreasury.sol";
import "./interfaces/ITreasuryVault.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IPool.sol";
import "./interfaces/ICollateralRatioPolicy.sol";
import "./interfaces/ITreasuryPolicy.sol";
import "./interfaces/ICollateralReserve.sol";

contract Treasury is ITreasury, Ownable, Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // addresses
    address public override collateralReserve;
    address public oracleDollar;
    address public oracleShare;
    address public oracleCollateral;
    address public dollar;
    address public share;
    address public collateral;
    address public collateralRatioPolicy;
    address public treasuryPolicy;
    address public profitSharingFund;
    address public controller;
    address public vault;

    // pools
    address[] public pools_array;
    mapping(address => bool) public pools;

    // Constants for various precisions
    uint256 private constant PRICE_PRECISION = 1e6;
    uint256 private constant RATIO_PRECISION = 1e6;

    // Number of decimals needed to get to 18
    uint256 public missing_decimals;

    bool private is_vault_entered = false;

    /* ========== MODIFIERS ========== */

    modifier onlyPools {
        require(pools[msg.sender], "Only pools can use this function");
        _;
    }

    modifier onlyController {
        require(msg.sender == controller || msg.sender == owner(), "Only controller or owner can trigger");
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    function initialize(
        address _dollar,
        address _share,
        address _collateral,
        address _treasuryPolicy,
        address _collateralRatioPolicy,
        address _collateralReserve,
        address _profitSharingFund,
        address _controller
    ) external initializer onlyOwner {
        require(_dollar != address(0), "invalidAddress");
        require(_share != address(0), "invalidAddress");
        dollar = _dollar;
        share = _share;
        setCollateralAddress(_collateral);
        setTreasuryPolicy(_treasuryPolicy);
        setCollateralRatioPolicy(_collateralRatioPolicy);
        setCollateralReserve(_collateralReserve);
        setProfitSharingFund(_profitSharingFund);
        setController(_controller);
    }

    /* ========== VIEWS ========== */

    function dollarPrice() public view returns (uint256) {
        return IOracle(oracleDollar).consult();
    }

    function sharePrice() public view override returns (uint256) {
        return IOracle(oracleShare).consult();
    }

    function collateralPrice() public view returns (uint256) {
        return IOracle(oracleCollateral).consult();
    }

    function hasPool(address _address) external view override returns (bool) {
        return pools[_address] == true;
    }

    function target_collateral_ratio() public view returns (uint256) {
        return ICollateralRatioPolicy(collateralRatioPolicy).target_collateral_ratio();
    }

    function effective_collateral_ratio() public view returns (uint256) {
        return ICollateralRatioPolicy(collateralRatioPolicy).effective_collateral_ratio();
    }

    function minting_fee() public view returns (uint256) {
        return ITreasuryPolicy(treasuryPolicy).minting_fee();
    }

    function redemption_fee() public view returns (uint256) {
        return ITreasuryPolicy(treasuryPolicy).redemption_fee();
    }

    function info()
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            dollarPrice(),
            sharePrice(),
            IERC20(dollar).totalSupply(),
            target_collateral_ratio(),
            effective_collateral_ratio(),
            globalCollateralValue(),
            minting_fee(),
            redemption_fee()
        );
    }

    function globalCollateralBalance() public view override returns (uint256) {
        uint256 _collateralReserveBalance = IERC20(collateral).balanceOf(collateralReserve);
        uint256 _vaultBalance = 0;
        if (vault != address(0)) {
            _vaultBalance = ITreasuryVault(vault).vaultBalance();
        }
        return _collateralReserveBalance + _vaultBalance - totalUnclaimedBalance();
    }

    function globalCollateralValue() public view override returns (uint256) {
        return (globalCollateralBalance() * collateralPrice() * (10**missing_decimals)) / PRICE_PRECISION;
    }

    // Iterate through all pools and calculate all unclaimed collaterals in all pools globally
    function totalUnclaimedBalance() public view returns (uint256) {
        uint256 _totalUnclaimed = 0;
        for (uint256 i = 0; i < pools_array.length; i++) {
            // Exclude null addresses
            if (pools_array[i] != address(0)) {
                _totalUnclaimed = _totalUnclaimed + (IPool(pools_array[i]).unclaimed_pool_collateral());
            }
        }
        return _totalUnclaimed;
    }

    function excessCollateralBalance() public view returns (uint256 _excess) {
        uint256 _tcr = target_collateral_ratio();
        uint256 _ecr = effective_collateral_ratio();
        if (_ecr <= _tcr) {
            _excess = 0;
        } else {
            _excess = ((_ecr - _tcr) * globalCollateralBalance()) / RATIO_PRECISION;
        }
    }

    function calcCollateralReserveRatio() public view returns (uint256) {
        uint256 _collateralReserveBalance = IERC20(collateral).balanceOf(collateralReserve);
        uint256 _collateralBalanceWithoutVault = _collateralReserveBalance - totalUnclaimedBalance();
        uint256 _globalCollateralBalance = globalCollateralBalance();
        if (_globalCollateralBalance == 0) {
            return 0;
        }
        return (_collateralBalanceWithoutVault * RATIO_PRECISION) / _globalCollateralBalance;
    }

    // check if collateral reserve is above threshold
    function isAboveThreshold() public view returns (bool) {
        uint256 _ratio = calcCollateralReserveRatio();
        uint256 _threshold = ITreasuryPolicy(treasuryPolicy).reservedCollateralThreshold();
        return _ratio >= _threshold;
    }

    /* ========== CONTROLLER FUNCTIONS - VAULT & PROFIT =============== */

    function recallFromVault() public onlyController {
        _recallFromVault();
    }

    function enterVault() public onlyController {
        _enterVault();
    }

    function rebalanceVault() external onlyController {
        _recallFromVault();
        _enterVault();
    }

    function rebalanceIfUnderThreshold() external onlyController {
        if (!isAboveThreshold()) {
            _recallFromVault();
            _enterVault();
        }
    }

    function extractProfit(uint256 _amount) external onlyController {
        require(_amount > 0, "zero amount");
        require(profitSharingFund != address(0), "Invalid profitSharingFund");
        uint256 _maxExcess = excessCollateralBalance();
        uint256 _maxAllowableAmount =
            _maxExcess -
                ((_maxExcess * ITreasuryPolicy(treasuryPolicy).excess_collateral_safety_margin()) / RATIO_PRECISION);
        require(_amount <= _maxAllowableAmount, "Excess allowable amount");
        ICollateralReserve(collateralReserve).transferTo(collateral, profitSharingFund, _amount);
        emit ProfitExtracted(_amount);
    }

    function _recallFromVault() internal nonReentrant {
        require(vault != address(0), "Vault does not exist");
        ITreasuryVault(vault).withdraw();
        IERC20 _collateral = IERC20(collateral);
        uint256 _balance = _collateral.balanceOf(address(this));
        if (_balance > 0) {
            _collateral.safeTransfer(collateralReserve, _balance);
        }

        is_vault_entered = false;
    }

    function _enterVault() internal nonReentrant {
        require(treasuryPolicy != address(0), "No treasury policy");
        require(vault != address(0), "No vault");
        require(is_vault_entered == false, "Valut already entered");

        IERC20 _collateral = IERC20(collateral);

        // 1. move all collateral from treasury back to pool
        uint256 _balance = _collateral.balanceOf(address(this));
        if (_balance > 0) {
            _collateral.safeTransfer(collateralReserve, _balance);
        }

        // 2. now pools should contain all collaterals. we will calc how much to use
        uint256 _collateralBalance = globalCollateralBalance();
        uint256 _idleCollateralUltiRatio = ITreasuryPolicy(treasuryPolicy).idleCollateralUtilizationRatio();
        uint256 _investmentAmount = (_idleCollateralUltiRatio * _collateralBalance) / RATIO_PRECISION;
        if (_investmentAmount > 0) {
            ICollateralReserve(collateralReserve).transferTo(collateral, address(this), _investmentAmount);
            _collateral.safeApprove(vault, 0);
            _collateral.safeApprove(vault, _investmentAmount);
            ITreasuryVault(vault).deposit(_investmentAmount);

            is_vault_entered = true;
        }
    }

    /* ========== RESTRICTED OWNER FUNCTIONS ========== */

    function requestTransfer(
        address _token,
        address _receiver,
        uint256 _amount
    ) external override onlyPools {
        if (_token == collateral) {
            uint256 _collateralReserveBalance = IERC20(collateral).balanceOf(collateralReserve);
            // If the balance is not enough, extract collateral from vault and rebalance.
            if (_collateralReserveBalance < _amount && is_vault_entered) {
                _recallFromVault();
                ICollateralReserve(collateralReserve).transferTo(_token, _receiver, _amount);
                _enterVault();
                return;
            }
        }

        ICollateralReserve(collateralReserve).transferTo(_token, _receiver, _amount);
    }

    // Add new Pool
    function addPool(address pool_address) public onlyOwner {
        require(pools[pool_address] == false, "poolExisted");
        pools[pool_address] = true;
        pools_array.push(pool_address);
        emit PoolAdded(pool_address);
    }

    // Remove a pool
    function removePool(address pool_address) public onlyOwner {
        require(pools[pool_address] == true, "!pool");
        // Delete from the mapping
        delete pools[pool_address];
        // 'Delete' from the array by setting the address to 0x0
        for (uint256 i = 0; i < pools_array.length; i++) {
            if (pools_array[i] == pool_address) {
                pools_array[i] = address(0); // This will leave a null in the array and keep the indices the same
                break;
            }
        }
        emit PoolRemoved(pool_address);
    }

    function setTreasuryPolicy(address _treasuryPolicy) public onlyOwner {
        require(_treasuryPolicy != address(0), "invalidAddress");
        treasuryPolicy = _treasuryPolicy;
        emit TreasuryPolicyUpdated(_treasuryPolicy);
    }

    function setCollateralRatioPolicy(address _collateralRatioPolicy) public onlyOwner {
        require(_collateralRatioPolicy != address(0), "invalidAddress");
        collateralRatioPolicy = _collateralRatioPolicy;
        emit CollateralPolicyUpdated(_collateralRatioPolicy);
    }

    function setOracleDollar(address _oracleDollar) external onlyOwner {
        require(_oracleDollar != address(0), "invalidAddress");
        oracleDollar = _oracleDollar;
        emit OracleDollarUpdated(oracleDollar);
    }

    function setOracleShare(address _oracleShare) external onlyOwner {
        require(_oracleShare != address(0), "invalidAddress");
        oracleShare = _oracleShare;
        emit OracleShareUpdated(oracleShare);
    }

    function setOracleCollateral(address _oracleCollateral) external onlyOwner {
        require(_oracleCollateral != address(0), "invalidAddress");
        oracleCollateral = _oracleCollateral;
        emit OracleCollateralUpdated(oracleCollateral);
    }

    function setCollateralAddress(address _collateral) public onlyOwner {
        require(_collateral != address(0), "invalidAddress");
        collateral = _collateral;
        missing_decimals = 18 - ERC20(_collateral).decimals();
        emit CollateralAddressUpdated(collateral);
    }

    function setCollateralReserve(address _collateralReserve) public onlyOwner {
        require(_collateralReserve != address(0), "invalidAddress");
        collateralReserve = _collateralReserve;
        emit CollateralReserveUpdated(_collateralReserve);
    }

    function setProfitSharingFund(address _profitSharingFund) public onlyOwner {
        require(_profitSharingFund != address(0), "invalidAddress");
        profitSharingFund = _profitSharingFund;
        emit ProfitSharingFundUpdated(_profitSharingFund);
    }

    function setController(address _controller) public onlyOwner {
        require(_controller != address(0), "invalidAddress");
        controller = _controller;
        emit ControllerUpdated(_controller);
    }

    function setVault(address _vault) external onlyController {
        require(_vault != address(0), "invalidAddress");
        vault = _vault;
        emit VaultUpdated(_vault);
    }

    // *** RESCUE FUNCTIONS ***

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
        require(success, string("TreasuryVaultAave::executeTransaction: Transaction execution reverted."));
        return returnData;
    }

    receive() external payable {}

    /* ========== EVENTS ========== */
    event PoolAdded(address indexed pool);
    event PoolRemoved(address indexed pool);
    event CollateralPolicyUpdated(address indexed pool);
    event VaultUpdated(address indexed pool);
    event ControllerUpdated(address indexed pool);
    event CollateralReserveUpdated(address indexed pool);
    event ProfitSharingFundUpdated(address indexed pool);
    event TreasuryPolicyUpdated(address indexed pool);
    event ProfitExtracted(uint256 amount);
    event CollateralAddressUpdated(address indexed newCollateral);
    event OracleCollateralUpdated(address indexed newOracle);
    event OracleShareUpdated(address indexed newOracle);
    event OracleDollarUpdated(address indexed newOracle);
}
