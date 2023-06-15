// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

/**
 *  @title IAllocatorConduit
 *  @dev   Conduits are to be used to manage positions for multiple Allocators.
 *         After funds are deposited into a Conduit, they can be deployed by Fund Managers to earn yield.
 *         When Allocators want funds back, they can request funds from the Fund Managers and then withdraw once liquidity is available.
 */
interface IConduit {

    /**
     *  @dev   Event emitted when a deposit is made to the Conduit.
     *  @param domain The unique identifier of the domain.
     *  @param asset  The address of the asset deposited.
     *  @param amount The amount of asset deposited.
     */
    event Deposit(bytes32 indexed domain, address indexed asset, uint256 amount);

    /**
     *  @dev   Event emitted when a withdrawal is made from the Conduit.
     *  @param domain      The unique identifier of the domain.
     *  @param asset       The address of the asset withdrawn.
     *  @param destination The address where the asset is sent.
     *  @param amount      The amount of asset withdrawn.
     */
    event Withdraw(bytes32 indexed domain, address indexed asset, address destination, uint256 amount);

    /**
     *  @dev   Event emitted when a Conduit request is made.
     *  @param domain        The unique identifier of the domain.
     *  @param asset         The address of the asset to be withdrawn.
     *  @param amount        The amount of asset to be withdrawn.
     *  @param data          Arbitrary encoded data to provide additional info to the Fund Manager.
     *  @param fundRequestId The ID of the fund request.
     */
    event RequestFunds(bytes32 indexed domain, address indexed asset, uint256 amount, bytes data, uint256 fundRequestId);

    /**
     *  @dev   Event emitted when a fund request is cancelled.
     *  @param domain        The unique identifier of the domain.
     *  @param asset         The address of the asset for the cancelled request.
     *  @param amount        The amount of asset for the cancelled request.
     *  @param data          Arbitrary encoded data to provide additional info to the Fund Manager.
     *  @param fundRequestId The ID of the cancelled fund request.
     */
    event CancelRequest(bytes32 indexed domain, address indexed asset, uint256 amount, bytes data, uint256 fundRequestId);

    /**
     *  @dev   Event emitted when a fund request is filled.
     *  @param domain    The unique identifier of the domain.
     *  @param asset     The address of the asset for the filled request.
     *  @param amount    The amount of asset for the filled request.
     *  @param data      Arbitrary encoded data to provide additional info to the Conduit.
     */
    event FillRequest(bytes32 indexed domain, address indexed asset, uint256 amount, bytes data);

    /**
     *  @dev   Struct representing a fund request.
     *  @param status          The current status of the fund request.
     *  @param domain          The unique identifier of the domain.
     *  @param amountRequested The amount of asset requested in the fund request.
     *  @param amountFilled    The amount of asset filled in the fund request.
     *  @param fundRequestId   The ID of the fund request.
     */
    struct FundRequest {
        StatusEnum status;
        bytes32    domain;
        uint256    amountRequested;
        uint256    amountFilled;
        uint256    fundRequestId;  // NOTE: Investigate usage
    }

    /**
     *  @dev Enum representing the status of a fund request.
     *
     *  @notice PENDING   - The fund request has been made, but not yet processed.
     *  @notice PARTIAL   - The fund request has been partially filled, but not yet completed.
     *  @notice CANCELLED - The fund request has been cancelled by the domain or due to an error or rejection.
     *  @notice COMPLETED - The fund request has been fully processed and completed.
     */
    enum StatusEnum {
        PENDING,
        PARTIAL,
        CANCELLED,
        COMPLETED
    }

    /**
     *  @dev    Function for depositing tokens into a Fund Manager.
     *  @param  domain    The unique identifier of the domain.
     *  @param  asset     The asset to deposit.
     *  @param  amount    The amount of tokens to deposit.
     */
    function deposit(bytes32 domain, address asset, uint256 amount) external;

    /**
     *  @dev   Function for withdrawing tokens from a Fund Manager.
     *  @param domain      The unique identifier of the domain.
     *  @param asset       The asset to withdraw.
     *  @param destination The address to send the withdrawn tokens to.
     *  @param amount      The amount of tokens to withdraw.
     */
    function withdraw(bytes32 domain, address asset, address destination, uint256 amount) external;

    /**
     *  @dev    Function to get the maximum deposit possible for a specific asset and domain.
     *  @param  domain      The unique identifier of the domain.
     *  @param  asset       The asset to check.
     *  @return maxDeposit_ The maximum possible deposit for the asset.
     */
    function maxDeposit(bytes32 domain, address asset) external view returns (uint256 maxDeposit_);

    /**
     *  @dev    Function to get the maximum withdrawal possible for a specific asset and domain.
     *  @param  domain       The unique identifier of the domain.
     *  @param  asset        The asset to check.
     *  @return maxWithdraw_ The maximum possible withdrawal for the asset.
     */
    function maxWithdraw(bytes32 domain, address asset) external view returns (uint256 maxWithdraw_);

    /**
     *  @dev    Function to initiate a withdrawal request from a Fund Manager.
     *  @param  domain        The unique identifier of the domain.
     *  @param  asset         The asset to withdraw.
     *  @param  amount        The amount of tokens to withdraw.
     *  @param  data          Arbitrary encoded data to provide additional info to the Fund Manager.
     *  @return fundRequestId The ID of the withdrawal request.
     */
    function requestFunds(bytes32 domain, address asset, uint256 amount, bytes memory data) external returns (uint256 fundRequestId);

    /**
     *  @dev   Function to cancel a withdrawal request from a Fund Manager.
     *  @param fundRequestId The ID of the withdrawal request.
     */
    function cancelFundRequest(uint256 fundRequestId) external;

    /**
     *  @dev    Function to check if a withdrawal request can be cancelled.
     *  @param  fundRequestId The ID of the withdrawal request.
     *  @return isCancelable_ True if the withdrawal request can be cancelled, false otherwise.
     */
    function isCancelable(uint256 fundRequestId) external view returns (bool isCancelable_);

    /**
     *  @dev    Function to get the status of a withdrawal request.
     *  @param  fundRequestId The ID of the withdrawal request.
     *  @return domain        The domain of the withdrawal request.
     *  @return fundRequest   The FundRequest struct representing the withdrawal request.
     */
    function fundRequestStatus(uint256 fundRequestId) external returns (bytes32 domain, FundRequest memory fundRequest);

    /**
     *  @dev    Function to get the active fund requests for a particular domain.
     *  @param  domain         The unique identifier of the domain.
     *  @return fundRequestIds Array of the IDs of active fund requests.
     *  @return totalAmount    The total amount of tokens requested in the active fund requests.
     */
    function activeFundRequests(bytes32 domain) external returns (uint256[] memory fundRequestIds, uint256 totalAmount);

    /**
     *  @dev    Function to get the total amount of active withdrawal requests.
     *  @return totalAmount The total amount of tokens requested for withdrawal.
     */
    function totalActiveFundRequests() external returns (uint256 totalAmount);

}
