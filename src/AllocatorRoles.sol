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
    mapping(bytes32 => address) public domains;
    mapping(bytes32 => mapping(address => bytes32)) public userRoles;
    mapping(bytes32 => mapping(address => mapping(bytes4 => bytes32))) public actionsRoles;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event SetDomainAdmin(bytes32 indexed domain, address user);
    event SetUserRole(address indexed who, uint8 indexed role, bool enabled);
    event SetRoleAction(uint8 indexed role, address indexed target, bytes4 indexed sig, bool enabled);

    // --- modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "AllocatorRoles/not-authorized");
        _;
    }

    modifier domainAuth(bytes32 domain) {
        require(domains[domain] == msg.sender, "AllocatorRoles/domain-not-authorized");
        _;
    }

    // --- constructor ---

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    // --- getters ---

    function hasUserRole(bytes32 domain, address who, uint8 role) external view returns (bool) {
        return bytes32(0) != userRoles[domain][who] & bytes32(2 ** uint256(role));
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

    function setDomainAdmin(bytes32 domain, address user) external auth {
        domains[domain] = user;
        emit SetDomainAdmin(domain, user);
    }

    // --- domain administration ---

    function setUserRole(bytes32 domain, address who, uint8 role, bool enabled) public domainAuth(domain) {
        bytes32 mask = bytes32(2 ** uint256(role));
        if (enabled) {
            userRoles[domain][who] |= mask;
        } else {
            userRoles[domain][who] &= _bitNot(mask);
        }
        emit SetUserRole(who, role, enabled);
    }

    function setRoleAction(bytes32 domain, uint8 role, address target, bytes4 sig, bool enabled) external domainAuth(domain) {
        bytes32 mask = bytes32(2 ** uint256(role));
        if (enabled) {
            actionsRoles[domain][target][sig] |= mask;
        } else {
            actionsRoles[domain][target][sig] &= _bitNot(mask);
        }
        emit SetRoleAction(role, target, sig, enabled);
    }

    // --- caller ---

    function canCall(bytes32 domain, address caller, address target, bytes4 sig) external view returns (bool ok) {
        ok = userRoles[domain][caller] & actionsRoles[domain][target][sig] != bytes32(0);
    }
}
