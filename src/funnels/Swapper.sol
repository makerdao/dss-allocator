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

interface RolesLike {
    function canCall(bytes32, address, address, bytes4) external view returns (bool);
}

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function transferFrom(address, address, uint256) external;
}

interface CalleeLike {
    function swap(address, address, uint256, uint256, address, bytes calldata) external;
}

contract Swapper {
    mapping (address => uint256) public wards;                         // Admins
    mapping (address => mapping (address => PairLimit)) public limits; // Rate limit parameters per src->dst pair

    RolesLike public immutable roles;  // Contract managing access control for this Depositor
    bytes32   public immutable ilk;    // Collateral type
    address   public immutable buffer; // Contract from which the GEM to sell is pulled and to which the bought GEM is pushed

    struct PairLimit {
        uint128 cap; // Maximum amount of src token that can be swapped each hop for a src->dst pair
        uint64  hop; // Cooldown one has to wait between each src to dst swap
        uint128 amt; // Amount already swapped during the last hop
        uint64  zzz; // Timestamp of the last src to dst swap
    }

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event SetLimits(address indexed src, address indexed dst, uint128 cap, uint64 hop);
    event Swap(address indexed sender, address indexed src, address indexed dst, uint256 amt, uint256 out);

    constructor(address roles_, bytes32 ilk_, address buffer_) {
        roles = RolesLike(roles_);
        ilk = ilk_;
        buffer = buffer_;
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(roles.canCall(ilk, msg.sender, address(this), msg.sig) || wards[msg.sender] == 1, "Swapper/not-authorized");
        _;
    }

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function setLimits(address src, address dst, uint128 cap, uint64 hop) external auth {
        limits[src][dst] = PairLimit({
            cap: cap,
            hop: hop,
            amt: limits[src][dst].amt,
            zzz: limits[src][dst].zzz
        });
        emit SetLimits(src, dst, cap, hop);
    }

    function swap(address src, address dst, uint256 amt, uint256 minOut, address callee, bytes calldata data) external auth returns (uint256 out) {
        PairLimit memory limit = limits[src][dst];

        unchecked {
            if (block.timestamp - limit.zzz >= limit.hop) {
                // Reset batch
                limit.amt = limit.cap;
                limit.zzz = uint64(block.timestamp);
            }
        }

        require(amt <= limit.amt, "Swapper/exceeds-max-amt");

        unchecked {
            limits[src][dst].amt = limit.amt - uint128(amt);
            limits[src][dst].zzz = limit.zzz;
        }

        uint256 prevDstBalance = GemLike(dst).balanceOf(buffer);
        GemLike(src).transferFrom(buffer, callee, amt);
        CalleeLike(callee).swap(src, dst, amt, minOut, buffer, data);

        out = GemLike(dst).balanceOf(buffer) - prevDstBalance;
        require(out >= minOut, "Swapper/too-few-dst-received");

        emit Swap(msg.sender, src, dst, amt, out);
    }
}
