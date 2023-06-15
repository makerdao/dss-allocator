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

interface NonFungibleTokenLike {
    function setApprovalForAll(address _operator, bool _approved) external;
}
interface TokenLike {
    function approve(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

contract AllocatorBuffer {
    // --- storage variables ---

    mapping(address => uint256) public wards;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Approve(address indexed token, address indexed spender, uint256 amount);
    event Deposit(address indexed token, address indexed sender, uint256 amount);

    // --- modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "AllocatorBuffer/not-authorized");
        _;
    }

    // --- constructor ---

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
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

    function setApprovalForAll(
        address token,
        address spender,
        bool approved
    ) external auth {
        NonFungibleTokenLike(token).setApprovalForAll(spender, approved);
        emit Approve(token, spender, approved ? 1 : 0);
    }

    function approve(
        address token,
        address spender,
        uint256 amount
    ) external auth {
        TokenLike(token).approve(spender, amount);
        emit Approve(token, spender, amount);
    }

    function deposit(address token, uint256 amount, address /* owner */) external {
        TokenLike(token).transferFrom(msg.sender, address(this), amount);
        emit Deposit(token, msg.sender, amount);
    }
}
