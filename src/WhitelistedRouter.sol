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

interface RolesLike {
    function canCall(bytes32, address, address, bytes4) external view returns (bool);
}

interface BoxLike {
    function withdraw(bytes32, address, address, uint256) external;
}

interface GemLike {
    function transferFrom(address, address, uint256) external;
    function approve(address, uint256) external;
}

contract WhitelistedRouter {

    // --- storage variables ---

    mapping (address => uint256) public wards;    // Auth
    mapping (address => uint256) public boxes;    // whitelisted boxes (e.g. RWA conduits, Escrow, SubDAO proxy)

    // --- immutables ---

    RolesLike immutable public roles;
    bytes32   immutable public ilk;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data, uint256 val);
    event Move(address sender, address indexed asset, address indexed from, address to, uint256 amt);

    // --- modifiers ---

    modifier auth() {
        require(roles.canCall(ilk, msg.sender, address(this), msg.sig) ||
                wards[msg.sender] == 1, "WhitelistedRouter/not-authorized");
        _;
    }

    // --- constructor ---

    constructor(address roles_, bytes32 ilk_) {
        roles = RolesLike(roles_);
        ilk = ilk_;

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

    function file(bytes32 what, address data, uint256 val) external auth {
        if (what == "box") boxes[data] = val;
        else revert("WhitelistedRouter/file-unrecognized-param");
        emit File(what, data, val);
    }

    // --- move execution ---

    function move(address asset, address from, address to, uint256 amt) external auth {
        require(boxes[from] == 1, "WhitelistedRouter/invalid-from");
        require(boxes[to] == 1, "WhitelistedRouter/invalid-to");
        BoxLike(from).withdraw(ilk, asset, to, amt);
        emit Move(msg.sender, asset, from, to, amt);
    }
}
