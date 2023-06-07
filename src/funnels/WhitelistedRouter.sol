// SPDX-FileCopyrightText: © 2020 Lev Livnev <lev@liv.nev.org.uk>
// SPDX-FileCopyrightText: © 2021 Dai Foundation <www.daifoundation.org>
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

interface BoxLike {
    function moved(address owner, uint256 amount) external;
    function isCancelable(uint256 withdrawalId) external view returns (bool isCancelable);
    function initiateWithdraw(address owner, uint256 amount) external returns (uint256 withdrawalId);
    function cancelWithdraw(uint256 withdrawalId) external;
    function withdraw(uint256 withdrawalId) external returns (uint256 resultingWithdrawalId);
}

interface GemLike {
    function transferFrom(address, address, uint256) external returns (bool);
}

contract WhitelistedRouter {
    mapping (address => uint256) public wards;    // Auth
    mapping (address => uint256) public buds;     // whitelisted facilitators
    mapping (address => uint256) public boxes;    // whitelisted boxes (e.g. RWA conduits, Escrow, SubDAO proxy)

    address public owner;                         // The SubDAO proxy owning this router. Used to notify boxes about the account owning the funds moved to them.

    event Rely    (address indexed usr);
    event Deny    (address indexed usr);
    event Kissed  (address indexed usr);
    event Dissed  (address indexed usr);
    event File    (bytes32 indexed what, address data);
    event File    (bytes32 indexed what, address data, uint256 val);
    event Transfer(address indexed router, address indexed from, address indexed to, uint256 amt, bool ack);

    constructor(address _gem) {
        gem = _gem;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "WhitelistedRouter/not-authorized");
        _;
    }

    // permissionned to whitelisted facilitators
    modifier toll { 
        require(buds[msg.sender] == 1, "WhitelistedRouter/non-facilitator"); 
        _;
    }

    address public immutable gem;

    function rely(address usr)   external auth { wards[usr]   = 1; emit Rely(usr); }
    function deny(address usr)   external auth { wards[usr]   = 0; emit Deny(usr); }
    function kiss(address usr)   external auth { buds[usr]    = 1; emit Kissed(usr); }
    function diss(address usr)   external auth { buds[usr]    = 0; emit Dissed(usr); }

    function file(bytes32 what, address data) external auth {
        if (what == "owner") owner = data;
        else revert("WhitelistedRouter/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, address data, uint256 val) external auth {
        if (what == "box") boxes[data] = val;
        else revert("WhitelistedRouter/file-unrecognized-param");
        emit File(what, data, val);
    }

    // Fund Transfer

    function transferFrom(address from, address to, uint256 amt) external toll returns (bool ack) {
        require(boxes[from] == 1, "WhitelistedRouter/invalid-from");
        require(boxes[to] == 1, "WhitelistedRouter/invalid-to");
        require(GemLike(gem).transferFrom(from, to, amt), "WhitelistedRouter/transfer-failed");
        (ack,) = address(to).call(abi.encodeWithSelector(BoxLike.moved.selector, owner, amt)); // this call is allowed to fail - `to` may not implement BoxLike.moved()
        emit Transfer(address(this), from, to, amt, ack);
    }

    // RWA Conduit Withdrawal Management

    function initiateWithdraw(address box, uint256 amt) external toll returns (uint256 withdrawalId) {
        withdrawalId = BoxLike(box).initiateWithdraw(owner, amt);
    }

    function cancelWithdraw(address box, uint256 withdrawalId) external toll {
        require(BoxLike(box).isCancelable(withdrawalId), "WhitelistedRouter/not-cancelable");
        BoxLike(box).cancelWithdraw(withdrawalId);
    }

    function withdraw(address box, uint256 withdrawalId) external toll returns (uint256 resultingWithdrawalId) {
        resultingWithdrawalId = BoxLike(box).withdraw(withdrawalId);
    }
}
