// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./ERC20/ERC20Custom.sol";
import "./interfaces/IShareTreasuryFund.sol";

contract TreasuryFund is Ownable, Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    address public share;
    uint256 public burnExcessRatio = 0;

    uint256 private constant PRECISION = 1000000;

    address public operator;

    event OperatorUpdated(address indexed newOperator);
    event ShareAddressUpdated(address indexed newShare);
    event BurnExcessRatioUpdated(uint256 indexed ratio);

    modifier onlyOwnerOrOperator() {
        require(msg.sender == owner() || msg.sender == operator, "Not owner or operator");
        _;
    }

    function initialize(address _share) external onlyOwner initializer {
        require(_share != address(0), "Invalid address");
        share = _share;
    }

    function claim() external onlyOwnerOrOperator nonReentrant {
        IShareTreasuryFund shareFund = IShareTreasuryFund(share);
        shareFund.claimTreasuryFundRewards();
    }

    function burnExcess() external onlyOwner {
        require(burnExcessRatio > 0, "burnExcessRatio is 0");
        uint256 fund_balance = ERC20Custom(share).balanceOf(address(this));
        uint256 burnAmount = (fund_balance * burnExcessRatio) / PRECISION;
        ERC20Custom(share).burn(burnAmount);
    }

    function transfer(address _recipient, uint256 amount) external onlyOwner {
        require(IERC20(share).transfer(_recipient, amount), "TreasuryFund.transfer: transfer failed");
    }

    function transferToOperator(uint256 amount) external onlyOwnerOrOperator {
        require(IERC20(share).transfer(operator, amount), "TreasuryFund.transferToOperator: transfer failed");
    }

    function transferTreasuryFundOwnership(address _newFund) external onlyOwner {
        IShareTreasuryFund(share).setTreasuryFund(_newFund);
    }

    function balance() public view returns (uint256) {
        return IERC20(share).balanceOf(address(this));
    }

    function setShareAddress(address _share) public onlyOwner {
        share = _share;
        emit ShareAddressUpdated(share);
    }

    function setBurnExcessRatio(uint256 _ratio) public onlyOwner {
        burnExcessRatio = _ratio;
        emit BurnExcessRatioUpdated(burnExcessRatio);
    }

    function rescueFund(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }

    function setOperator(address _operator) public onlyOwner {
        operator = _operator;
        emit OperatorUpdated(operator);
    }
}
