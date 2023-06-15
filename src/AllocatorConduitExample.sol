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

pragma solidity ^0.8.16;

import "./IAllocatorConduit.sol";

contract AllocatorConduitExample is IAllocatorConduit {
    // --- storage variables ---

    mapping(address => uint256) public wards;
    mapping(bytes32 => address) public roles;
    mapping(address => FundRequest[]) public fundRequests;
    uint256 public totalFundRequests;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event SetRoles(bytes32 indexed domain, address roles_);

    // --- modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "AllocatorBuffer/not-authorized");
        _;
    }

    modifier domainAuth(bytes32 domain) {
        address roles_ = roles[domain];
        bool access;
        if (roles_ != address(0)) {
            (bool ok, bytes memory ret) = roles_.call(
                                            abi.encodeWithSignature(
                                                "canCall(address,address,bytes4)",
                                                msg.sender,
                                                address(this),
                                                msg.sig
                                            )
            );
            access = ok && ret.length == 32 && abi.decode(ret, (bool));
        }
        require(access, "AllocatorConduitExample/not-authorized");
        _;
    }

    // --- getters ---

    function maxDeposit(bytes32 domain, address asset) external view returns (uint256 maxDeposit_) {
        // Implement the logic for maxDeposit
    }

    function maxWithdraw(bytes32 domain, address asset) external view returns (uint256 maxWithdraw_) {
        // Implement the logic for maxWithdraw
    }

    function isCancelable(uint256 fundRequestId) external view returns (bool isCancelable_) {
        FundRequest storage request = fundRequests[address(0)][fundRequestId];
        isCancelable_ = request.status != StatusEnum.CANCELLED && request.status != StatusEnum.COMPLETED;
    }

    function fundRequestStatus(uint256 fundRequestId) external view returns (FundRequest memory fundRequest) {
        fundRequest = fundRequests[address(0)][fundRequestId];
    }

    function activeFundRequests(bytes32 domain) external view returns (uint256[] memory fundRequestIds, uint256 totalAmount) {
        fundRequestIds = new uint256[](totalFundRequests);
        uint256 count;

        for (uint256 i = 1; i <= totalFundRequests; i++) {
            if (fundRequests[address(0)][i].domain == domain && fundRequests[address(0)][i].status != StatusEnum.CANCELLED && fundRequests[address(0)][i].status != StatusEnum.COMPLETED) {
                fundRequestIds[count++] = i;
            }
        }

        for (uint256 i = 0; i < count; i++) {
            totalAmount += fundRequests[address(0)][fundRequestIds[i]].amountRequested;
        }
    }

    function totalActiveFundRequests() external view returns (uint256 count) {
        for (uint256 i = 1; i <= totalFundRequests; i++) {
            if (fundRequests[address(0)][i].status != StatusEnum.CANCELLED && fundRequests[address(0)][i].status != StatusEnum.COMPLETED) {
                count++;
            }
        }
    }

    // --- admininstration ---

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function setRoles(bytes32 domain, address roles_) external auth {
        roles[domain] = roles_;
        emit SetRoles(domain, roles_);
    }

    // --- functions ---

    function deposit(bytes32 domain, address asset, uint256 amount) external domainAuth(domain) {
        // Implement the logic to deposit funds into the FundManager
        emit Deposit(domain, asset, amount);
    }

    function withdraw(bytes32 domain, address asset, address destination, uint256 amount) external domainAuth(domain) {
        // Implement the logic to withdraw funds from the FundManager

        emit Withdraw(domain, asset, destination, amount);
    }

    function requestFunds(bytes32 domain, address asset, uint256 amount, bytes memory data) external domainAuth(domain) returns (uint256 fundRequestId) {
        require(amount > 0, "AllocatorConduitExample/amount-not-greater-0");

        fundRequestId = ++totalFundRequests;
        fundRequests[asset].push(FundRequest(StatusEnum.PENDING, domain, amount, 0, data, fundRequestId));

        emit RequestFunds(domain, asset, amount, data, fundRequestId);
    }

    function cancelFundRequest(bytes32 domain, uint256 fundRequestId) external domainAuth(domain) {
        FundRequest storage request = fundRequests[address(0)][fundRequestId];
        require(request.domain == domain, "AllocatorConduitExample/domain-not-match");
        require(request.status != StatusEnum.CANCELLED && request.status != StatusEnum.COMPLETED, "AllocatorConduitExample/request-not-active");

        request.status = StatusEnum.CANCELLED;
        // emit CancelRequest(domain, asset, amount, data, fundRequestId); // TODO: define how to get certain data
    }
}
