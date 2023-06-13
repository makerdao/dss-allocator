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
    function canCall(address, address, bytes4) external view returns (bool);
}

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function transferFrom(address, address, uint256) external;
}

interface CalleeLike {
    function swap(address src, address dst, uint256 amt, uint256 minOut, bytes calldata data) external returns (uint256 out);
}

contract Swapper {
    mapping (address => uint256) public wards;
    mapping (address => mapping (address => uint256)) public hops;       // [seconds]        hops[src][dst] is the swap cooldown when swapping `src` to `dst`.
    mapping (address => mapping (address => uint256)) public zzz;        // [seconds]         zzz[src][dst] is the timestamp of the last swap from `src` to `dst`.
    mapping (address => mapping (address => uint256)) public maxSrcAmts; // [weis]     maxSrcAmts[src][dst] is the maximum amount that can be swapped each hop when swapping `src` to `dst`.

    address public buffer;                                               // Escrow contract from which the GEM to sell is pulled and to which the bought GEM is pushed
    address public roles;                                                // Contract managing access control for this Swapper

    event Rely (address indexed usr);
    event Deny (address indexed usr);
    event File (bytes32 indexed what, address indexed src, address indexed dst, uint256 data);
    event File (bytes32 indexed what, address data);
    event Swap (address indexed sender, address indexed src, address indexed dst, uint256 amt, uint256 out);

    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        address roles_ = roles;
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
        require(access || wards[msg.sender] == 1, "Swapper/not-authorized");
        _;
    }

    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }

    function file(bytes32 what, address src, address dst, uint256 data) external auth {
        if      (what == "maxSrcAmt")  maxSrcAmts[src][dst] = data;
        else if (what == "hop")              hops[src][dst] = data;
        else revert("Swapper/file-unrecognized-param");
        emit File(what, src, dst, data);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "buffer") buffer = data;
        else revert("Swapper/file-unrecognized-param");
        emit File(what, data);
    }

    function swap(address src, address dst, uint256 amt, uint256 minOut, address callee, bytes calldata data) external auth returns (uint256 out) {
        require(block.timestamp >= zzz[src][dst] + hops[src][dst], "Swapper/too-soon");
        zzz[src][dst] = block.timestamp;

        require(amt <= maxSrcAmts[src][dst], "Swapper/exceeds-max-amt");

        uint256 prevDstBalance = GemLike(dst).balanceOf(buffer);
        GemLike(src).transferFrom(buffer, callee, amt);
        CalleeLike(callee).swap(src, dst, amt, minOut, data);
        uint256 dstBalance = GemLike(dst).balanceOf(buffer);
        require(dstBalance >= prevDstBalance + minOut, "Swapper/too-few-dst-received");
        out = dstBalance - prevDstBalance;

        emit Swap(msg.sender, src, dst, amt, out);
    }
}
