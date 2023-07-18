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

interface SwapperLike {
    function swap(address, address, uint256, uint256, address, bytes calldata) external returns (uint256);
}

contract StableSwapper {
    mapping (address => uint256) public wards;                           // Admins
    mapping (address => uint256) public buds;                            // Whitelisted keepers
    mapping (address => mapping (address => PairConfig)) public configs; // Configuration for keepers

    SwapperLike public immutable swapper;                                // Swapper for this StableSwapper

    uint256 internal constant WAD = 10 ** 18;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event SetConfig(address indexed src, address indexed dst, uint128 count, uint64 hop, uint128 lot, uint128 reqOut);

    constructor(address swapper_) {
        swapper = SwapperLike(swapper_);
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "StableSwapper/not-authorized");
        _;
    }

    // permissionned to whitelisted keepers
    modifier toll { 
        require(buds[msg.sender] == 1, "StableSwapper/non-keeper");
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

    function kiss(address usr) external auth {
        buds[usr] = 1;
        emit Kiss(usr);
    }

    function diss(address usr) external auth {
        buds[usr] = 0;
        emit Diss(usr);
    }

    struct PairConfig {
        uint128 count;  // The remaining number of times that a src to dst swap can be performed by keepers
        uint64  hop;
        uint64  zzz;
        uint128 lot;    // The amount swapped by keepers from src to dst every hop
        uint128 reqOut; // The minimum output amount to insist on in the swap form src to dst
    }

    function setConfig(address src, address dst, uint128 count, uint64 hop, uint128 lot, uint128 reqOut) external auth {
        configs[src][dst] = PairConfig({
            count: count,
            hop: hop,
            zzz: configs[src][dst].zzz,
            lot: lot,
            reqOut: reqOut
        });
        emit SetConfig(src, dst, count, hop, lot, reqOut);
    }

    // Note: the keeper's minOut value must be updated whenever configs[src][dst] is changed.
    // Failing to do so may result in this call reverting or in taking on more slippage than intended (up to a limit controlled by configs[src][dst].reqOut).
    function swap(address src, address dst, uint256 minOut, address callee, bytes calldata data) toll external returns (uint256 out) {
        PairConfig memory cfg = configs[src][dst];

        require(cfg.count > 0, "StableSwapper/exceeds-count");
        require(block.timestamp >= cfg.zzz + cfg.hop, "StableSwapper/too-soon");
        configs[src][dst].count = cfg.count - 1;
        configs[src][dst].zzz   = uint64(block.timestamp);

        if (minOut == 0) minOut = cfg.reqOut;
        require(minOut >= cfg.reqOut, "StableSwapper/min-too-small");

        out = swapper.swap(src, dst, cfg.lot, minOut, callee, data);
    }
}
