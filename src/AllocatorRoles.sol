// SPDX-FileCopyrightText: © 2017 DappHub, LLC
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

contract AllocatorRoles
{
    // --- storage variables ---

    mapping(address => uint256) public wards;
    mapping(bytes32 => address) public ilkAdmins;
    mapping(bytes32 => mapping(address => bytes32)) public userRoles;
    mapping(bytes32 => mapping(address => mapping(bytes4 => bytes32))) public actionsRoles;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event SetIlkAdmin(bytes32 indexed ilk, address user);
    event SetUserRole(bytes32 indexed ilk, address indexed who, uint8 indexed role, bool enabled);
    event SetRoleAction(bytes32 indexed ilk, uint8 indexed role, address indexed target, bytes4 sig, bool enabled);

    // --- modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "AllocatorRoles/not-authorized");
        _;
    }

    modifier ilkAuth(bytes32 ilk) {
        require(ilkAdmins[ilk] == msg.sender, "AllocatorRoles/ilk-not-authorized");
        _;
    }

    // --- constructor ---

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- getters ---

    function hasUserRole(bytes32 ilk, address who, uint8 role) external view returns (bool) {
        return bytes32(0) != userRoles[ilk][who] & bytes32(2 ** uint256(role));
    }

    // --- internals ---

    function _bitNot(bytes32 input) internal pure returns (bytes32 output) {
        output = (input ^ bytes32(type(uint256).max));
    }

    // --- general administration ---

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function setIlkAdmin(bytes32 ilk, address user) external auth {
        ilkAdmins[ilk] = user;
        emit SetIlkAdmin(ilk, user);
    }

    // --- ilk administration ---

    function setUserRole(bytes32 ilk, address who, uint8 role, bool enabled) public ilkAuth(ilk) {
        bytes32 mask = bytes32(2 ** uint256(role));
        if (enabled) {
            userRoles[ilk][who] |= mask;
        } else {
            userRoles[ilk][who] &= _bitNot(mask);
        }
        emit SetUserRole(ilk, who, role, enabled);
    }

    function setRoleAction(bytes32 ilk, uint8 role, address target, bytes4 sig, bool enabled) external ilkAuth(ilk) {
        bytes32 mask = bytes32(2 ** uint256(role));
        if (enabled) {
            actionsRoles[ilk][target][sig] |= mask;
        } else {
            actionsRoles[ilk][target][sig] &= _bitNot(mask);
        }
        emit SetRoleAction(ilk, role, target, sig, enabled);
    }

    // --- caller ---

    function canCall(bytes32 ilk, address caller, address target, bytes4 sig) external view returns (bool ok) {
        ok = userRoles[ilk][caller] & actionsRoles[ilk][target][sig] != bytes32(0);
    }
}
