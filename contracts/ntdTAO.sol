// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { wTAO } from "./wTAO.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract NtdTAO is
  Initializable,
  ERC20Upgradeable,
  Ownable2StepUpgradeable,
  ReentrancyGuardUpgradeable,
  AccessControlUpgradeable
{
  using SafeERC20 for IERC20;
  struct UnstakeRequest {
    uint256 amount;
    uint256 taoAmt;
    bool isReadyForUnstake;
    address wrappedToken;
    uint256 timestamp;
  }

  /*
   * set the exchange rate of wTAO:ntdTAO.
   * exchange rate is in 10^18
   */
  uint256 public exchangeRate; // 1 * 10^18
  /*
   * How much TAO it cost to unstake. This is to account for bridging cost from finney to eth
   */
  uint256 public unstakingFee;
  /*
   * How much TAO it cost to stake. This is to account for bridging cost from eth to finney
   */
  uint256 public stakingFee;
  /*
   * How much TAO it cost to bridge.
   */
  uint256 public bridgingFee;
  /*
   * How much is needed to be staked to be able to perform staking in 1 txn
   */
  uint256 public minStakingAmt;
  /*
   * Underlying token
   */
  address public wrappedToken;
  /*
   * Set the max amount of wTAO that can be deposited at once
   */
  uint256 public maxDepositPerRequest;
  /*
   * Determine if the contract is paused
   */
  bool public isPaused;
  /*
   * finney wallet that will receive the wTAO after wrap()
   * NOTE: it must be at least 48 chars so validation shall
   * be done to ensure that it is true
   */
  string public nativeWalletReceiver;
  /*
   * Set the max amount of unstake request for a given user
   */
  uint256 public maxUnstakeRequests;
  /*
   * Mapping from address to current active UnstakeRequest[]
   */
  mapping(address => UnstakeRequest[]) public unstakeRequests;
  /*
   * The address that can be allowed to withdraw
   */
  address public withdrawalManager;
  /*
   * The service fee that is charged for each unstake request in ETH
   * This is to pay for the gas fees for the withdrawal manager
   */
  uint256 public serviceFee;

  /*
   *
   * Defines maxSupply for ntdTAO
   *
   *
   */
  uint256 public maxSupply;

  /*
   * Defines both the upper bound and lower bound of the exchange rate
   */

  uint256 public lowerExchangeRateBound;
  uint256 public upperExchangeRateBound;

  address public protocolVault;

  bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
  bytes32 public constant EXCHANGE_UPDATE_ROLE = keccak256("EXCHANGE_UPDATE_ROLE");
  bytes32 public constant MANAGE_STAKING_CONFIG_ROLE = keccak256("MANAGE_STAKING_CONFIG_ROLE");
  bytes32 public constant TOKEN_SAFE_PULL_ROLE = keccak256("TOKEN_SAFE_PULL_ROLE");
  bytes32 public constant APPROVE_WITHDRAWAL_ROLE = keccak256("APPROVE_WITHDRAWAL_ROLE");


  modifier canPauseRole() {
    require(hasRole(PAUSE_ROLE, msg.sender), "Caller does not have PAUSE_ROLE");
    _;
  }

  modifier hasExchangeUpdateRole() {
    require(
      hasRole(EXCHANGE_UPDATE_ROLE, msg.sender),
      "Caller does not have EXCHANGE_UPDATE_ROLE"
    );
    _;
  }

  modifier hasManageStakingConfigRole() {
    require(
      hasRole(MANAGE_STAKING_CONFIG_ROLE, msg.sender),
      "Caller does not have MANAGE_STAKING_UPDATE_ROLE"
    );
    _;
  }

  modifier hasTokenSafePullRole() {
    require(
      hasRole(TOKEN_SAFE_PULL_ROLE, msg.sender),
      "Caller does not have TOKEN_SAFE_PULL_ROLE"
    );
    _;
  }

  modifier hasApproveWithdrawalRole() {
    require(
      hasRole(APPROVE_WITHDRAWAL_ROLE, msg.sender),
      "Caller does not have APPROVE_WITHDRAWAL_ROLE"
    );
    _;
  }


  struct UserRequest {
    address user;
    uint256 requestIndex;
  }


  // Keep counter of the amouht of wTAO to batch
  uint256 public batchTAOAmt;

  // Declaration of all events
  event UserUnstakeRequested(
    address indexed user,
    uint256 idx,
    uint256 requestTimestamp,
    uint256 wstAmount,
    uint256 outTaoAmt,
    address wrappedToken
  );
  event AdminUnstakeApproved(
    address indexed user,
    uint256 idx,
    uint256 approvedTimestamp
  );
  event UserUnstake(
    address indexed user,
    uint256 idx,
    uint256 unstakeTimestamp
  );
  event UserStake(
    address indexed user,
    uint256 stakeTimestamp,
    uint256 inTaoAmt,
    uint256 wstAmount
  );
  event UpdateProtocolVault(address newProtocolVault);
  event UpdateMaxSupply(uint256 newMaxSupply);
  event UpdateServiceFee(uint256 serviceFee);
  event UpdateWithdrawalManager(address withdrawalManager);
  event UpdateMinStakingAmt(uint256 minStakingAmt);
  event UpdateStakingFee(uint256 stakingFee);
  event UpdateBridgeFee(uint256 bridgingFee);
  event UpdateMaxDepositPerRequest(uint256 maxDepositPerRequest);
  event UpdateMaxUnstakeRequest(uint256 maxUnstakeRequests);
  event UpdateExchangeRate(uint256 newRate);
  event LowerBoundUpdated(uint256 newLowerBound);
  event UpperBoundUpdated(uint256 newUpperBound);
  event ContractPaused(bool paused);
  event UpdateWTao(address newWTAO);
  event UpdateUnstakingFee(uint256 newUnstakingFee);
  event UpdateNativeFinneyReceiver(string newNativeWalletReceiver);
  event ERC20TokenPulled(address tokenAddress, address to, uint256 amount);
  event NativeTokenPulled(address to, uint256 amount);

  // End of Declaration of all events

  // constructor() {
  //   _disableInitializers();
  // }

  /*
   *
   * In this initialization function, we initialize and 
   * set the initialOwner as the owner of ntdTAO
   * 
   * Initial supply must be more than 0. If initialSupply is 10^9
   * that means initial supply is 1 TAO
   *
   *
   */
  function initialize(address initialOwner, uint256 initialSupply) public initializer {
    require(initialOwner != address(0), "Owner cannot be null");
    require(initialSupply > 0, "Initial supply must be more than 0");
    __ERC20_init("NTD Staked TAO", "ntdTAO");
    __Ownable_init(initialOwner);
    __AccessControl_init();
    __ReentrancyGuard_init();
    _setRoleAdmin(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
    _transferOwnership(initialOwner);
    _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
    maxSupply = initialSupply;
  }

  /*
   * Common setters for the contract
   *
   */

  /*
   *
   * Function to update the current ETH service fee to support gas transactions for unstaking.
   *
   * Value Boundary: serviceFee can be 0 ETH
   *
   */
  function setServiceFee(uint256 _serviceFee) public hasManageStakingConfigRole {
    require(_serviceFee <= 0.01 ether, "Service fee cannot be more than 0.01 ETH");
    serviceFee = _serviceFee;
    emit UpdateServiceFee(serviceFee);
  }

  /*
   *
   * Function to set the withdrawal manager address that will receive the ETH service fee
   *
   * Value boundary: withdrawalManager cannot be address(0)
   *
   */
  function setWithdrawalManager(address _withdrawalManager) public hasManageStakingConfigRole {
    require(_withdrawalManager != address(0), "Withdrawal manager cannot be null");
    withdrawalManager = _withdrawalManager;
    emit UpdateWithdrawalManager(withdrawalManager);
  }

  /*
   *
   * This function sets the protocol vault address that
   * shall be responsible for receiving the staking fees.
   *
   * Boundary: address cannot be address(0)
   *
   */
  function setProtocolVault(address _protocolVault) public hasManageStakingConfigRole {
    require(_protocolVault != address(0), "Protocol vault cannot be null");
    protocolVault = _protocolVault;
    emit UpdateProtocolVault(protocolVault);
  }
  


  /*
   *
   * This methood sets the new max supply of ntdTAO
   *
   * Value Boundary: maxSupply cannot be less than the current total supply. 
   *
   * E.g. if total supply is 1000, new max supply must be more than 1000. _maxSupply provided cannot be 1000.
   *
   */
  function setMaxSupply(uint256 _maxSupply) public hasManageStakingConfigRole {
    require(_maxSupply > totalSupply(), "Max supply must be greater than the current total supply");
    maxSupply = _maxSupply;
    emit UpdateMaxSupply(maxSupply);
  }

  /*
   *
   * This method sets the min staking amount required to perform staking
   *
   * Value Boundary: minStakingAmt can be any value even 0 in the event that minStakingAmt by taobridge changes in the future
   *
   */
  function setMinStakingAmt(uint256 _minStakingAmt) public hasManageStakingConfigRole {
    require(_minStakingAmt > bridgingFee, "Min staking amount must be more than bridging fee");
    minStakingAmt = _minStakingAmt;
    emit UpdateMinStakingAmt(minStakingAmt);
  }

  /*
   *
   * Value Boundary: stakingFee can be between 0-999 (0% to 99.9%)
   *
   * 0% can be set in case stakingFee is disabled in the future.
   *
   */
  function setStakingFee(uint256 _stakingFee) public hasManageStakingConfigRole {
    // Staking fee cannot be equivalent to 2% staking fee. Max it can go is 19 (1.9%)
    require(_stakingFee < 20, "Staking fee cannot be more than equal to 20");
    stakingFee = _stakingFee;
    emit UpdateStakingFee(stakingFee);
  }

  /*
   *
   * This function sets the bridging fee that is used to bridge from eth to finney
   *
   * Value Boundary: bridgingFee can be any value even 0 in the event that bridgingFee by taobridge changes in the future
   *
   */
  function setBridgingFee(uint256 _bridgingFee) public hasManageStakingConfigRole {
    require(_bridgingFee <= 0.2 gwei, "Bridging fee cannot be more than 0.2 TAO");
    bridgingFee = _bridgingFee; // Assuming _bridgingFee is passed in mwei
    emit UpdateBridgeFee(bridgingFee);
  }

  /*
   *
   * Set the maximum number of deposit per request for a given user
   *
   * Value Boundary: maxDepositPerRequest must be more than 0
   *
   */
  function setMaxDepositPerRequest(uint256 _maxDepositPerRequest)
    public
    hasManageStakingConfigRole
  {
    require(_maxDepositPerRequest > 0, "Max deposit per request must be more than 0");
    maxDepositPerRequest = _maxDepositPerRequest;
    emit UpdateMaxDepositPerRequest(maxDepositPerRequest);
  }

  /*
   *
   * Set maximum unstake request
   *
   * Value Boundary: maxUnstakeRequests must be more than 0
   *
   */
  function setMaxUnstakeRequest(uint256 _maxUnstakeRequests) public hasManageStakingConfigRole {
    require(_maxUnstakeRequests > 0, "Max unstake requests must be more than 0");
    maxUnstakeRequests = _maxUnstakeRequests;
    emit UpdateMaxUnstakeRequest(maxUnstakeRequests);
  }

  function renounceOwnership() public override onlyOwner {}

  // Ensure that the lower bound is less than upper bound
  function setLowerExchangeRateBound(uint256 _newLowerBound) public hasExchangeUpdateRole {
    require(_newLowerBound > 0, "New lower bound must be more than 0");
    require(
      _newLowerBound < upperExchangeRateBound,
      "New lower bound must be less than current upper bound"
    );
    lowerExchangeRateBound = _newLowerBound;
    emit LowerBoundUpdated(_newLowerBound);
  }

  // Ensure that the upper bound is more than lower bound
  function setUpperExchangeRateBound(uint256 _newUpperBound) public hasExchangeUpdateRole {
    require(_newUpperBound > 0, "New upper bound must be more than 0");
    require(
      _newUpperBound > lowerExchangeRateBound,
      "New upper bound must be greater than current lower bound"
    );
    upperExchangeRateBound = _newUpperBound;
    emit UpperBoundUpdated(_newUpperBound);
  }

  /*
   * Our decimal places follow tao 9 decimal place.
   */
  function decimals() public view virtual override returns (uint8) {
    return 9;
  }

  function setPaused(bool _isPaused) public canPauseRole {
    isPaused = _isPaused;
    emit ContractPaused(isPaused);
  }

  /*
   *
   * This function determines the unstaking fee that is charged to the user
   *
   * The value is in gwei so if _unstakingFee is 1 gwei, it means 1 TAO is charged as unstaking fee
   *
   * Value Boundary: UnstakingFee can be any value even 0 in the event that unstakingFee is not longer charged.
   *
   */
  function setUnstakingFee(uint256 _unstakingFee) public hasManageStakingConfigRole {
    require(_unstakingFee <= 0.2 gwei, "Unstaking fee cannot be more than 0.2 TAO");
    unstakingFee = _unstakingFee;
    emit UpdateUnstakingFee(unstakingFee);
  }

  /*
   *
   * This function sets to wtao address that will be used to wrap and unwrap
   *
   * Value boundary: wTAO cannot be address(0)
   *
   */
  function setWTAO(address _wTAO) public hasManageStakingConfigRole nonReentrant {
    // Check to ensure _wTAO is not null
    _requireNonZeroAddress(_wTAO, "wTAO address cannot be null");
    address oldWTAO = wrappedToken;
    wrappedToken = _wTAO;

    if(batchTAOAmt > 0) {
      _checkValidFinneyWallet(nativeWalletReceiver);
      uint256 amountToBridgeBack = batchTAOAmt;
      batchTAOAmt = 0; 
      bool success = wTAO(oldWTAO).bridgeBack(
        amountToBridgeBack,
        nativeWalletReceiver
      );
      require(success, "Bridge back failed");
    }

    emit UpdateWTao(_wTAO);
  }

  /*
   * Function to set the natvive token receiver. Validation performed to determine if 48 characters
   */
  function setNativeTokenReceiver(string memory _nativeWalletReceiver)
    public
    hasManageStakingConfigRole
  {
    // Ensure it is a valid finney wallet before updating.
    _checkValidFinneyWallet(_nativeWalletReceiver);
    nativeWalletReceiver = _nativeWalletReceiver;
    emit UpdateNativeFinneyReceiver(_nativeWalletReceiver);
  }

  /*
   *
   * These those methods shall help to calculate the exchange rate
   * of wntdTAO given wTAO input and vice versa
   *
   * Note that there would be precision loss that would be rounded down
   * so the user will get less than expected to a precision of up to 1 wei if the rounding
   * down happens.
   *
   */
  function getWntdTAObyWTAO(uint256 wtaoAmount) public view returns (uint256) {
    return (wtaoAmount * exchangeRate) / 1 ether;
  }

  function getWTAOByWntdTAO(uint256 wntdTaoAmount) public view returns (uint256) {
    return (wntdTaoAmount * 1 ether) / exchangeRate;
  }

  function getWTAOByWntdTAOAfterFee(uint256 wntdTaoAmount)
    public
    view
    returns (uint256)
  {
    return ((wntdTaoAmount - unstakingFee) * 1 ether) / exchangeRate;
  }

  /*
   *
   * Here we add utility functions so that
   * we can perform checks using DRY principles
   *
   */

  
  /*
   *
   *
   */
  function _transferToVault(uint256 _feeAmt) internal {
    IERC20(wrappedToken).safeTransferFrom(msg.sender, address(protocolVault), _feeAmt);
  }

  function _transferToContract(uint256 _wrapAmt) internal {
    IERC20(wrappedToken).safeTransferFrom(msg.sender, address(this), _wrapAmt);
  }


  // Check if the address is a non null address
  // @param _address The address to check
  // @param errorMessage The error message to display if the address is null
  function _requireNonZeroAddress(address _address, string memory errorMessage)
    internal
    pure
  {
    require(_address != address(0), errorMessage);
  }

  /*
   *
   * this method is used to check if the native wallet receiver is valid
   * finney walllet must be 48 characters
   *
   * @param _nativeWalletReceiver The native wallet receiver to check
   *
   */
  function _checkValidFinneyWallet(string memory _nativeWalletReceiver)
    internal
    pure
  {
    require(
      bytes(_nativeWalletReceiver).length == 48,
      "nativeWalletReceiver must be of length 48"
    );
  }

  /*
   *
   * Mints only if the max supply is exceeded
   *
   */

  function _mintWithSupplyCap(address account, uint256 amount) internal {
    require(totalSupply() + amount <= maxSupply, "Max supply exceeded");
    _mint(account, amount);
  }

  // Check if the contract is paused
  modifier checkPaused() {
    require(!isPaused, "Contract is paused");
    _;
  }


  /*
   * This function is used for users to request for unstaking
   * When users request for unstaking, they will need to pay a fee
   * The fee will be used to pay for the gas fees for the withdrawal manager
   *
   * After user successfully request for unstake, the withdrawal manage will
   * need to approve the request before the user can unstake
   *
   * @params wntdTAOAmt The amount of wntdTAO to unstake
   *
   *
   */
  function requestUnstake(uint256 wntdTAOAmt) public payable nonReentrant checkPaused {
    // Check that wrappedToken and withdrawalManager is a valid address
    _requireNonZeroAddress(
      address(wrappedToken),
      "wrappedToken address is invalid"
    );
    _requireNonZeroAddress(
      address(withdrawalManager),
      "withdrawal address cannot be null"
    );


    // Ensure that the fee amount is sufficient
    require(msg.value >= serviceFee, "Fee amount is not sufficient");
    require(wntdTAOAmt > unstakingFee, "Invalid wntdTAO amount");
    // Check if enough balance
    require(balanceOf(msg.sender) >= wntdTAOAmt, "Insufficient wntdTAO balance");
    uint256 outWTaoAmt = getWTAOByWntdTAOAfterFee(wntdTAOAmt);

    uint256 length = unstakeRequests[msg.sender].length;
    bool added = false;
    // Loop throught the list of existing unstake requests
    for (uint256 i = 0; i < length; i++) {
      uint256 currAmt = unstakeRequests[msg.sender][i].amount;
      if (currAmt > 0) {
        continue;
      } else {
        // If the curr amt is zero, it means
        // we can add the unstake request in this index
        unstakeRequests[msg.sender][i] = UnstakeRequest({
          amount: wntdTAOAmt,
          taoAmt: outWTaoAmt,
          isReadyForUnstake: false,
          timestamp: block.timestamp,
          wrappedToken: wrappedToken
        });
        added = true;
        emit UserUnstakeRequested(
          msg.sender,
          i,
          block.timestamp,
          wntdTAOAmt,
          outWTaoAmt,
          wrappedToken
        );
        break;
      }
    }

    // If we have not added the unstake request, it means that
    // we need to push a new unstake request into the array
    if (!added) {
      require(
        unstakeRequests[msg.sender].length < maxUnstakeRequests,
        "Maximum unstake requests exceeded"
      );
      unstakeRequests[msg.sender].push(
        UnstakeRequest({
          amount: wntdTAOAmt,
          taoAmt: outWTaoAmt,
          isReadyForUnstake: false,
          timestamp: block.timestamp,
          wrappedToken: wrappedToken
        })
      );
      emit UserUnstakeRequested(
        msg.sender,
        length,
        block.timestamp,
        wntdTAOAmt,
        outWTaoAmt,
        wrappedToken

      );
    }

    // Perform burn
    _burn(msg.sender, wntdTAOAmt);
    // transfer the service fee to the withdrawal manager
    // withdrawalManager have already been checked to be a non zero address
    // in the guard condition at start of function
    bool success = payable(withdrawalManager).send(serviceFee);
    require(success, "Service fee transfer failed");
  }

  function getUnstakeRequestByUser(address user)
    public
    view
    returns (UnstakeRequest[] memory)
  {
    return unstakeRequests[user];
  }

  /*
   *
   * This method shall be used to approve withdrawals by the user
   * The withdrawal manager will need to approve the withdrawal.
   *
   * Note that multiple requests can be approved at once
   *
   * @params requests The list of requests to approve
   *
   *
   */
  function approveMultipleUnstakes(UserRequest[] calldata requests)
    public
    hasApproveWithdrawalRole
    nonReentrant
    checkPaused
  {
    uint256 totalRequiredTaoAmt = 0;
    require(requests.length > 0, "Requests array is empty");
    require(
      requests[0].requestIndex < unstakeRequests[requests[0].user].length,
      "First request index out of bounds"
    );
    // There might be cases that the underlying token might be different
    // so we need to add checks to ensure that the unstaking is the same token
    // across all indexes in the current requests UserRequest[] array
    // If there is 2 different tokens underlying in the requests, we return the
    // error as system is not designed to handle such a scenario.
    // In that scenario, the user needs to unstake the tokens separately
    // in two separate request
    address commonWrappedToken = unstakeRequests[requests[0].user][requests[0].requestIndex].wrappedToken;

    // Loop through each request to unstake and check if the request is valid
    for (uint256 i = 0; i < requests.length; i++) {
      UserRequest calldata request = requests[i];
      require(
        request.requestIndex < unstakeRequests[request.user].length,
        "Invalid request index"
      );
      require(
        unstakeRequests[request.user][request.requestIndex].amount > 0,
        "Request is invalid"
      );
      require(
        !unstakeRequests[request.user][request.requestIndex].isReadyForUnstake,
        "Request is already approved"
      );

      // Check if wrappedToken is the same for all requests
      require(
        unstakeRequests[request.user][request.requestIndex].wrappedToken == commonWrappedToken,
        "Wrapped token is not the same across all unstake requests"
      );

      totalRequiredTaoAmt += unstakeRequests[request.user][request.requestIndex]
        .taoAmt;
    }

    // Check if the sender has allowed the contract to spend enough tokens
    require(
      IERC20(commonWrappedToken).allowance(msg.sender, address(this)) >=
        totalRequiredTaoAmt,
      "Insufficient token allowance"
    );

    for (uint256 i = 0; i < requests.length; i++) {
      UserRequest calldata request = requests[i];
      unstakeRequests[request.user][request.requestIndex]
        .isReadyForUnstake = true;
    }

    // Transfer the tao from the withdrawal manager to this contract
    IERC20(commonWrappedToken).safeTransferFrom(
      msg.sender,
      address(this),
      totalRequiredTaoAmt
    );

    // Emit events after state changes and external interactions
    for (uint256 i = 0; i < requests.length; i++) {
      UserRequest calldata request = requests[i];
      emit AdminUnstakeApproved(
        request.user,
        request.requestIndex,
        block.timestamp
      );
    }
  }

  /*
   *
   * This method shall be used by the user to unstake and withdraw the
   * redeemed tao to their wallet
   *
   * @params requestIndex The index of the request to unstake
   *
   */
  function unstake(uint256 requestIndex) public nonReentrant checkPaused {

    require(
      requestIndex < unstakeRequests[msg.sender].length,
      "Invalid request index"
    );
    UnstakeRequest memory request = unstakeRequests[msg.sender][requestIndex];
    require(request.amount > 0, "No unstake request found");
    require(request.isReadyForUnstake, "Unstake not approved yet");

    // Transfer wTAO tokens back to the user
    uint256 amountToTransfer = request.taoAmt;

    // Update state to false
    delete unstakeRequests[msg.sender][requestIndex];

    // Perform ERC20 transfer
    IERC20(request.wrappedToken).safeTransfer(
      msg.sender,
      amountToTransfer
    );

    // Process the unstake event
    emit UserUnstake(msg.sender, requestIndex, block.timestamp);
  }

  /*
   *
   * This method shall be used by the admin to exchange the market rate
   * and the value of wTAO:ntdTAO.
   *
   * Owner shall be multisignature wallet
   *
   * @params newRate The new exchange rate
   *
   */
  function updateExchangeRate(uint256 newRate) public hasExchangeUpdateRole {
    require(newRate > 0, "New rate must be more than 0");
    require(
      newRate >= lowerExchangeRateBound && newRate <= upperExchangeRateBound,
      "New rate must be within bounds"
    );
    // This also checks for newRate > 0 since lowerExchangeRateBound is always more than 0
    // Recommended min lower and upper bound is define upon initialization
    require(
      lowerExchangeRateBound > 0 && upperExchangeRateBound > 0,
      "Bounds must be more than 0"
    );

    exchangeRate = newRate;
    emit UpdateExchangeRate(newRate);
  }

  /*
   * This method calculates the amount of wTAO after deducting both
   * the bridging fee and the staking fee
   *
   * In this calculation:
   * 1. We first deduct the bridging fee from the wTAO amount
   * 2. We then calculate the staking fee based on the amountAfterBridgingFee 
   * 3. We then deduct the staking fee from the amountAfterBridgingFee
   *
   * Note: 
   * 1. wTAOAmont must be bigger than bridgingFee 
   * 2. amountAfterTotalFees much be more than 0
   *
   */
  function calculateAmtAfterFee(uint256 wtaoAmount)
    public
    view
    returns (uint256, uint256)
  {
    require(
      wtaoAmount > bridgingFee,
      "wTAO amount must be more than bridging fee"
    );
    uint256 amountAfterBridgingFee = wtaoAmount - bridgingFee;

    // Apply the staking fee as a percentage (e.g., 0.1%)
    // Note: Multiply by 1000 to convert the decimal percentage to an integer
    uint256 feeAmount = 0;
    if(stakingFee > 0) {
      /*
       *
       * Formula to calculate feeAmount. Note that there might be precision loss of
       * 1 wei due to the division which is approx 4e-7 if TAO is $400 which is negliglbe
       * So we can accept this precision loss
       *
       */
      feeAmount = (amountAfterBridgingFee * stakingFee) / 1000;
    }

    // Subtract the percentage-based staking fee from the amount after bridging fee
    uint256 amountAfterTotalFees = amountAfterBridgingFee - feeAmount;

    require(amountAfterTotalFees > 0, "Wrap amount after fee must be more than 0");

    return (amountAfterTotalFees, feeAmount);
  }

  /*
   *
   * How to calculate the max TAO that we can wrap given the current supply.
   *
   * In this case, we need to reverse calculation used for calculateAmtAfterFee
   *
   *
   */
  function maxTaoForWrap() public view returns (uint256) {
    uint256 availableNtdTAOSupply = maxSupply - totalSupply();
    if (availableNtdTAOSupply == 0) {
      return 0;
    }

    uint256 equivalentTaoAmount = (availableNtdTAOSupply * 1 ether) / exchangeRate;
    uint256 grossTaoAmount;

    // Adjust for the staking fee and bridging fee
    if(stakingFee > 0) {
      grossTaoAmount = (equivalentTaoAmount * 1000) / (1000 - stakingFee);
    } else {
      grossTaoAmount = equivalentTaoAmount;
    }
    uint256 maxTaoToWrap = grossTaoAmount + bridgingFee;

    // Ensure the result does not exceed availableNtdTAOSupply
    return maxTaoToWrap;
  }

  /*
   * This function shall be used by the user to wrap their wTAO tokens
   * and get ntdTAO in return
   *
   * Note that stakingFee cna be 0% (0) so we do need to check for that
   *
   */
  function wrap(uint256 wtaoAmount) public nonReentrant checkPaused {
    // Deposit cap amount
    require(
      maxDepositPerRequest >= wtaoAmount,
      "Deposit amount exceeds maximum"
    );

    string memory _nativeWalletReceiver = nativeWalletReceiver;
    IERC20 _wrappedToken = IERC20(wrappedToken);
    // Check that the nativeWalletReceiver is not an empty string
    _checkValidFinneyWallet(_nativeWalletReceiver);
    _requireNonZeroAddress(
      address(_wrappedToken),
      "wrappedToken address is invalid"
    );
    require(
      _wrappedToken.balanceOf(msg.sender) >= wtaoAmount,
      "Insufficient wTAO balance"
    );

    // Check to ensure that the protocol vault address is not zero
    _requireNonZeroAddress(
      address(protocolVault),
      "Protocol vault address cannot be 0"
    );

    // Ensure that at least 0.125 TAO is being bridged
    // based on the smart contract
    require(wtaoAmount > minStakingAmt, "Does not meet minimum staking amount");


    // Ensure that the wrap amount after free is more than 0
    (uint256 wrapAmountAfterFee, uint256 feeAmt) = calculateAmtAfterFee(wtaoAmount);

    uint256 wntdTAOAmount = getWntdTAObyWTAO(wrapAmountAfterFee);

    // Perform token transfers
    _mintWithSupplyCap(msg.sender, wntdTAOAmount);
    _transferToVault(feeAmt);
    uint256 amtToBridge = wrapAmountAfterFee + bridgingFee;
    _transferToContract(amtToBridge);

    // We add this to the total amount we would like to batch together. 
    batchTAOAmt += amtToBridge;
    emit UserStake(msg.sender, block.timestamp, wtaoAmount, wntdTAOAmount);
  }


  /*
   *
   * This function shall be responsible for batch transfer of the wTAO
   * to the taobridge
   *
   * withdrawal wallet shall be responsible for performing this task
   *
   *
   */
  function batchTransferBridgeBack()
    public
    hasApproveWithdrawalRole
    nonReentrant
  {
    // ensure both wrappedToken and nativeWalletReceiver is a valid address
    _requireNonZeroAddress(
      address(wrappedToken),
      "wrappedToken address is invalid"
    );
    _checkValidFinneyWallet(nativeWalletReceiver);
    require(batchTAOAmt > 0, "No TAO to bridge back");
    uint256 amountToBridgeBack = batchTAOAmt;
    batchTAOAmt = 0;
    // Call the bridge back to send the TAO to the taobridge and indicate the finney wallet that
    // will receive it
    bool success = wTAO(wrappedToken).bridgeBack(
      amountToBridgeBack,
      nativeWalletReceiver
    );
    // reset the batchTAOAmt to 0 so that we are able to keep track of the next batch
    require(success, "Bridge back failed");
  }



  function safePullERC20(
    address tokenAddress,
    address to,
    uint256 amount
  ) public hasTokenSafePullRole checkPaused {
    _requireNonZeroAddress(to, "Recipient address cannot be null address");

    require(amount > 0, "Amount must be greater than 0");

    IERC20 token = IERC20(tokenAddress);
    uint256 balance = token.balanceOf(address(this));
    require(balance >= amount, "Not enough tokens in contract");

    // Deduct the amount from the batchTAOAmt if the token is wTAO
    if(tokenAddress == wrappedToken) {
      if(amount >= batchTAOAmt) {
        batchTAOAmt = 0;
      } else {
        batchTAOAmt -= amount;
      }
    }


    // "to" have been checked to be a non zero address
    token.safeTransfer(to, amount);
    emit ERC20TokenPulled(tokenAddress, to, amount);
  }

  function pullNativeToken(address to, uint256 amount) public hasTokenSafePullRole checkPaused {
    _requireNonZeroAddress(to, "Recipient address cannot be null address");
    require(amount > 0, "Amount must be greater than 0");

    uint256 balance = address(this).balance;
    require(balance >= amount, "Not enough native tokens in contract");

    // "to" have been checked to be a non zero address
    (bool success, ) = to.call{ value: amount }("");
    require(success, "Native token transfer failed");
    emit NativeTokenPulled(to, amount);
  }
}
