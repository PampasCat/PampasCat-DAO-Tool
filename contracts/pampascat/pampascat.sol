pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@solmate/src/utils/FixedPointMathLib.sol";

error AllocationCannotBeZero();
error AlreadyDeposited();
error DuplicatePartner();
error PartnerPeriodEnded();
error PartnershipNotStarted();
error OnlyDepositor();
error OnlyPartner();
error OnlyPartnersWithBalance();
error PartnerAlreadyFunded();
error BeforeCliff();

contract Pampascat {
    using FixedPointMathLib for uint256;
    event Deposited(address indexed depositor, uint256 depositTokenAmount);
    event PartnershipFormed(address indexed partner, uint256 exchangeTokenAmount);
    event FundingReceived(address indexed depositor, uint256 exchangeTokenAmount, uint256 depositTokenAmount);
    event DepositTokenClaimed(address indexed partner, uint256 depositTokenAmount);

    ERC20 public immutable depositToken;
 
    ERC20 public immutable exchangeToken;

    uint256 public immutable partnerPeriod;

    uint256 public immutable cliffPeriod;
 
    uint256 public immutable vestingPeriod;

    address public immutable depositor;
 
    uint256 public immutable totalAllocated;

    uint256 public immutable BASE_UNIT;

    mapping(address => uint256) public partnerExchangeAllocations;

    mapping(address => uint256) public partnerBalances;

    mapping(address => uint256) public lastWithdrawnAt;

    uint256 public partnershipStartedAt;

    uint256 public totalExchanged;
    
    constructor(
        ERC20 _depositToken,
        ERC20 _exchangeToken,
        uint256 _exchangeRate,
        uint256 _partnerPeriod,
        uint256 _cliffPeriod,
        uint256 _vestingPeriod,
        address[] memory _partners,
        uint256[] memory _allocations,
        address _depositor
    ) {
        require(_partners.length == _allocations.length, "Partners and allocations must have same length");
        depositToken = _depositToken;
        exchangeToken = _exchangeToken;
        //exchangeRate = _exchangeRate;
        partnerPeriod = _partnerPeriod;
        cliffPeriod = _cliffPeriod;
        vestingPeriod = _vestingPeriod;
        depositor = _depositor;
        unchecked {
            uint256 z = depositToken.decimals() - exchangeToken.decimals();
            if (z > depositToken.decimals()) {
                z = exchangeToken.decimals() - depositToken.decimals();
            }

            BASE_UNIT = 10**(z + 2);
        }
      
        uint256 sum = 0;
        uint256 length = _partners.length;
        for (uint256 i = 0; i < length; i++) {
            if (_allocations[i] == 0) revert AllocationCannotBeZero();
            if (partnerExchangeAllocations[_partners[i]] != 0) revert DuplicatePartner();
            partnerExchangeAllocations[_partners[i]] = _allocations[i];
            sum += _allocations[i];
        }
        totalAllocated = exchangeToDeposit(sum);
    }

    modifier onlyDepositor() {
        if (msg.sender != depositor) revert OnlyDepositor();
        _;
    }

    modifier onlyPartners() {
        if (partnerExchangeAllocations[msg.sender] == 0) revert OnlyPartner();
        _;
    }

    function exchangeToDeposit(uint256 _exchangeTokens) private view returns (uint256) {
        return 0;
    }

    /// @notice Calculate amount of depositTokens that a partner has available to claim.
    function _getClaimableTokens(address _partner) private view returns (uint256) {
        if (partnerExchangeAllocations[_partner] == 0 || partnerBalances[_partner] == 0) return 0;
        uint256 startingDate = lastWithdrawnAt[_partner];
        if (block.timestamp < startingDate + cliffPeriod) return 0;

        uint256 fullyVested = partnershipStartedAt + cliffPeriod + vestingPeriod;
        uint256 endDate = fullyVested > block.timestamp ? block.timestamp : fullyVested;
        uint256 timeVested = endDate - startingDate;
        uint256 lengthOfVesting = cliffPeriod + vestingPeriod;

        //uint256 pctVested = timeVested.fdiv(lengthOfVesting, 10**depositToken.decimals());
        uint256 claimableAmount = exchangeToDeposit(partnerExchangeAllocations[_partner]);
        return 1;
       // return claimableAmount.fmul(pctVested, 10**depositToken.decimals());
    }

    function getClaimableTokens(address _partner) external view returns (uint256) {
        return _getClaimableTokens(_partner);
    }


    function deposit() external onlyDepositor {
        if (partnershipStartedAt != 0) revert AlreadyDeposited();

        partnershipStartedAt = block.timestamp + partnerPeriod;
        depositToken.transferFrom(depositor, address(this), totalAllocated);

        emit Deposited(msg.sender, totalAllocated);
    }

    function enterPartnership() external onlyPartners {
        if (block.timestamp >= partnershipStartedAt) revert PartnerPeriodEnded();
        if (partnerBalances[msg.sender] != 0) revert PartnerAlreadyFunded();

        uint256 fundingAmount = partnerExchangeAllocations[msg.sender];
        totalExchanged += fundingAmount;
        partnerBalances[msg.sender] = exchangeToDeposit(fundingAmount);
        lastWithdrawnAt[msg.sender] = partnershipStartedAt;

        exchangeToken.transferFrom(msg.sender, address(this), fundingAmount);

        emit PartnershipFormed(msg.sender, fundingAmount);
    }
    

    function claimExchangeTokens() external {
    
        if (block.timestamp < partnershipStartedAt) revert PartnershipNotStarted();

        uint256 amount = exchangeToken.balanceOf(address(this));
        uint256 unfundedAmount = totalAllocated - exchangeToDeposit(totalExchanged);

        if (unfundedAmount != 0) {
            depositToken.transfer(depositor, unfundedAmount);
        }
        exchangeToken.transfer(depositor, amount);
        emit FundingReceived(depositor, amount, unfundedAmount);
    }

    function claimDepositTokens() external onlyPartners {
        uint256 cliffAt = partnershipStartedAt + cliffPeriod;
        if (block.timestamp < cliffAt) revert BeforeCliff();
        if (partnerBalances[msg.sender] == 0) revert OnlyPartnersWithBalance();

        uint256 amountClaimable = _getClaimableTokens(msg.sender);
        partnerBalances[msg.sender] -= amountClaimable;
        lastWithdrawnAt[msg.sender] = block.timestamp;
        depositToken.transfer(msg.sender, amountClaimable);

        emit DepositTokenClaimed(msg.sender, amountClaimable);
    }
}
