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

    // --- modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "AllocatorRoles/not-authorized");
        _;
    }

    // --- getters ---

    function hasUserRole(address who, uint8 role) external view returns (bool) {
        return bytes32(0) != userRoles[who] & bytes32(uint256(uint256(2) ** uint256(role)));
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

    function setUserRole(address who, bytes32 role, bool enabled) public auth {
        bytes32 mask = bytes32(uint256(uint256(2) ** uint256(role)));
        if (enabled) {
            userRoles[who] |= mask;
        } else {
            userRoles[who] &= _bitNot(mask);
        }
    }

    function setPublicCapability(address target, bytes4 sig, bool enabled) external auth {
        publicActions[target][sig] = enabled ? 1 : 0;
    }

    function setRoleCapability(uint8 role, address target, bytes4 sig, bool enabled) external auth {
        bytes32 mask = bytes32(uint256(uint256(2) ** uint256(role)));
        if (enabled) {
            actionsRoles[target][sig] |= mask;
        } else {
            actionsRoles[target][sig] &= _bitNot(mask);
        }
    }

    // --- caller ---

    function canCall(address caller, address target, bytes4 sig) external view returns (bool ok) {
        ok = userRoles[caller] & actionsRoles[target][sig] != bytes32(0) || publicActions[target][sig] == 1;
    }
}
