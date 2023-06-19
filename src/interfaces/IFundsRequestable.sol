// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity >=0.8.0;

/**
 *  @title IFundsRequestable
 *  @dev   After funds are deposited into this contract, they can be deployed by Fund Managers to earn yield.
 *         When Allocators want funds back, they can request funds from the Fund Managers.
 */
interface IFundsRequestable {

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
     *  @param domain The unique identifier of the domain.
     *  @param asset  The address of the asset for the filled request.
     *  @param amount The amount of asset for the filled request.
     *  @param data   Arbitrary encoded data to provide additional info to the Conduit.
     */
    event FillRequest(bytes32 indexed domain, address indexed asset, uint256 amount, bytes data);

    /**
     *  @dev   Struct representing a fund request.
     *  @param status          The current status of the fund request.
     *  @param domain          The unique identifier of the domain.
     *  @param amountAvailable The amount of asset available for withdrawal.
     *  @param amountRequested The amount of asset requested in the fund request.
     *  @param amountFilled    The amount of asset filled in the fund request.
     *  @param fundRequestId   The ID of the fund request.
     */
    struct FundRequest {
        StatusEnum status;
        bytes32    domain;
        uint256    amountAvailable;
        uint256    amountRequested;
        uint256    amountFilled;
        bytes      data;
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
     *  @param domain        The unique identifier of the domain.
     *  @param asset         The asset to cancel the fund request for.
     *  @param fundRequestId The ID of the withdrawal request.
     */
    function cancelFundRequest(bytes32 domain, address asset, uint256 fundRequestId) external;

    /**
     *  @dev    Function to check if a withdrawal request can be cancelled.
     *  @param  domain        The unique identifier of the domain.
     *  @param  asset         The asset to check.
     *  @param  fundRequestId The ID of the withdrawal request.
     *  @return isCancelable_ True if the withdrawal request can be cancelled, false otherwise.
     */
    function isCancelable(bytes32 domain, address asset, uint256 fundRequestId) external view returns (bool isCancelable_);

    /**
     *  @dev    Function to get the status of a withdrawal request.
     *  @param  domain        The unique identifier of the domain.
     *  @param  asset         The asset to check.
     *  @param  fundRequestId The ID of the withdrawal request.
     *  @return fundRequest   The FundRequest struct representing the withdrawal request.
     */
    function fundRequestStatus(bytes32 domain, address asset, uint256 fundRequestId) external returns (FundRequest memory fundRequest);

    /**
     *  @dev    Function to get the active fund requests for a particular domain.
     *  @param  asset          The address of the asset.
     *  @param  domain         The unique identifier of the domain.
     *  @return fundRequestIds Array of the IDs of active fund requests.
     *  @return totalAmount    The total amount of tokens requested in the active fund requests.
     */
    function activeFundRequests(bytes32 domain, address asset) external returns (uint256[] memory fundRequestIds, uint256 totalAmount);

}
