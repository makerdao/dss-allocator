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
    bool        public immutable permissionless;

    struct PairConfig {
        uint128 num; // The remaining number of times that a src to dst swap can be performed by keepers
        uint32  hop; // Cooldown period it has to wait between swap executions
        uint32  zzz; // Timestamp of the last swap execution
        uint96  lot; // The amount swapped by keepers from src to dst every hop
        uint96  req; // The minimum required output amount to insist on in the swap form src to dst
    }

    uint256 internal constant WAD = 10 ** 18;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event SetConfig(address indexed src, address indexed dst, uint128 num, uint32 hop, uint96 lot, uint96 req);

    constructor(address swapper_, bool permissionless_) {
        swapper = SwapperLike(swapper_);
        permissionless = permissionless_;
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "StableSwapper/not-authorized");
        _;
    }

    // permissionned to whitelisted keepers
    modifier toll { 
        require(permissionless || buds[msg.sender] == 1, "StableSwapper/non-keeper");
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

    function setConfig(address src, address dst, uint128 num, uint32 hop, uint96 lot, uint96 req) external auth {
        configs[src][dst] = PairConfig({
            num: num,
            hop: hop,
            zzz: 0,
            lot: lot,
            req: req
        });
        emit SetConfig(src, dst, num, hop, lot, req);
    }

    // Note: the keeper's minOut value must be updated whenever configs[src][dst] is changed.
    // Failing to do so may result in this call reverting or in taking on more slippage than intended (up to a limit controlled by configs[src][dst].min).
    function swap(address src, address dst, uint256 minOut, address callee, bytes calldata data) toll external returns (uint256 out) {
        PairConfig memory cfg = configs[src][dst];

        require(cfg.num > 0, "StableSwapper/exceeds-num");
        require(block.timestamp >= cfg.zzz + cfg.hop, "StableSwapper/too-soon");
        unchecked { configs[src][dst].num = cfg.num - 1; }
        configs[src][dst].zzz = uint32(block.timestamp);

        if (minOut == 0) minOut = cfg.req;
        require(minOut >= cfg.req, "StableSwapper/min-too-small");

        out = swapper.swap(src, dst, cfg.lot, minOut, callee, data);
    }
}
