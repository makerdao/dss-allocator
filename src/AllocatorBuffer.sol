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

import "src/interfaces/IAllocatorConduit.sol";

interface TokenLike {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external;
    function transfer(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

contract AllocatorBuffer is IAllocatorConduit {
    // --- storage variables ---

    mapping(address => uint256) public wards;

    // --- immutables ---
    bytes32 immutable public ilk;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Approve(address indexed asset, address indexed spender, uint256 amount);

    // --- modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "AllocatorBuffer/not-authorized");
        _;
    }

    // --- constructor ---

    constructor(bytes32 ilk_) {
        ilk = ilk_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- getters ---

    function maxDeposit(bytes32, address) external pure returns (uint256 maxDeposit_) {
        maxDeposit_ = type(uint256).max;
    }

    function maxWithdraw(bytes32, address asset) external view returns (uint256 maxWithdraw_) {
        maxWithdraw_ = TokenLike(asset).balanceOf(address(this));
    }

    // --- administration ---

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    // --- functions ---

    function approve(address asset, address spender, uint256 amount) external auth {
        TokenLike(asset).approve(spender, amount);
        emit Approve(asset, spender, amount);
    }

    function deposit(bytes32, address asset, uint256 amount) external {
        TokenLike(asset).transferFrom(msg.sender, address(this), amount);
        emit Deposit(ilk, asset, amount);
    }

    function withdraw(bytes32, address asset, address destination, uint256 maxAmount) external auth returns (uint256 amount) {
        uint256 balance = TokenLike(asset).balanceOf(address(this));
        amount = balance < maxAmount ? balance : maxAmount;
        TokenLike(asset).transfer(destination, amount);
        emit Withdraw(ilk, asset, destination, amount);
    }
}
