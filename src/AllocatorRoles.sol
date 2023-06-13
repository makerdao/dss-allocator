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
    mapping(address => bytes32) public userRoles;
    mapping(address => mapping(bytes4 => bytes32)) public actionsRoles;
    mapping(address => mapping(bytes4 => uint256)) public publicActions;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event SetUserRole(address indexed who, uint8 indexed role, bool enabled);
    event SetPublicAction(address indexed target, bytes4 indexed sig, bool enabled);
    event SetRoleAction(uint8 indexed role, address indexed target, bytes4 indexed sig, bool enabled);

    // --- modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "AllocatorRoles/not-authorized");
        _;
    }

    // --- constructor ---

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- getters ---

    function hasUserRole(address who, uint8 role) external view returns (bool) {
        return bytes32(0) != userRoles[who] & bytes32(2 ** uint256(role));
    }

    // --- internals ---

    function _bitNot(bytes32 input) internal pure returns (bytes32 output) {
        output = (input ^ bytes32(type(uint256).max));
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

    function setUserRole(address who, uint8 role, bool enabled) public auth {
        bytes32 mask = bytes32(2 ** uint256(role));
        if (enabled) {
            userRoles[who] |= mask;
        } else {
            userRoles[who] &= _bitNot(mask);
        }
        emit SetUserRole(who, role, enabled);
    }

    function setPublicAction(address target, bytes4 sig, bool enabled) external auth {
        publicActions[target][sig] = enabled ? 1 : 0;
        emit SetPublicAction(target, sig, enabled);
    }

    function setRoleAction(uint8 role, address target, bytes4 sig, bool enabled) external auth {
<<<<<<< HEAD
        bytes32 mask = bytes32(2 ** uint256(role));
=======
        bytes32 mask = bytes32(uint256(uint256(2) ** uint256(role)));
>>>>>>> 5be5a3f (Add tests + some renaming)
        if (enabled) {
            actionsRoles[target][sig] |= mask;
        } else {
            actionsRoles[target][sig] &= _bitNot(mask);
        }
        emit SetRoleAction(role, target, sig, enabled);
    }

    // --- caller ---

    function canCall(address caller, address target, bytes4 sig) external view returns (bool ok) {
        ok = userRoles[caller] & actionsRoles[target][sig] != bytes32(0) || publicActions[target][sig] == 1;
    }
}
