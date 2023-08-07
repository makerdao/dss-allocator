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

import "./utils/EnumerableSet.sol";

interface SwapperLike {
    function swap(address, address, uint256, uint256, address, bytes calldata) external returns (uint256);
}

contract StableSwapper {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    mapping (address => uint256) public wards;       // Admins
    mapping (address => uint256) public buds;        // Whitelisted keepers
    mapping (bytes32 => PairConfig) public configs; // Configuration for keepers

    mapping (bytes32 => Pair) public pairs;
    EnumerableSet.Bytes32Set private pairHashes;
    
    SwapperLike public immutable swapper;                                // Swapper for this StableSwapper

    struct PairConfig {
        uint128 num; // The remaining number of times that a src to dst swap can be performed by keepers
        uint32  hop; // Cooldown period it has to wait between swap executions
        uint32  zzz; // Timestamp of the last swap execution
        uint96  lot; // The amount swapped by keepers from src to dst every hop
        uint96  req; // The minimum required output amount to insist on in the swap form src to dst
    }

    struct Pair {
        address src;
        address dst;
    }

    uint256 internal constant WAD = 10 ** 18;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event SetConfig(address indexed src, address indexed dst, uint128 num, uint32 hop, uint96 lot, uint96 req);

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

    function getPairHash(address src, address dst) public pure returns (bytes32) {
        return keccak256(abi.encode(src, dst));
    }

    function getConfig(address src, address dst) external view returns (uint128 num, uint32 hop, uint32 zzz, uint96 lot, uint96 req) {
        PairConfig memory cfg = configs[getPairHash(src, dst)];
        return (cfg.num, cfg.hop, cfg.zzz, cfg.lot, cfg.req);
    }

    function setConfig(address src, address dst, uint128 num, uint32 hop, uint96 lot, uint96 req) external auth {
        bytes32 key = getPairHash(src, dst);
        configs[key] = PairConfig({
            num: num,
            hop: hop,
            zzz: 0,
            lot: lot,
            req: req
        });
        if (num > 0) { // TODO: check hop < type(uint32).max ?
            if (pairHashes.add(key)) pairs[key] = Pair(src, dst);
        } else {
            pairHashes.remove(key);
        }
        emit SetConfig(src, dst, num, hop, lot, req);
    }

    function numPairs() external view returns (uint256) {
        return pairHashes.length();
    }

    function pairAt(uint256 index) external view returns (Pair memory) {
        return pairs[pairHashes.at(index)];
    }

    // Note: the keeper's minOut value must be updated whenever configs[src][dst] is changed.
    // Failing to do so may result in this call reverting or in taking on more slippage than intended (up to a limit controlled by configs[src][dst].min).
    function swap(address src, address dst, uint256 minOut, address callee, bytes calldata data) toll external returns (uint256 out) {
        bytes32 key = getPairHash(src, dst);
        PairConfig memory cfg = configs[key];

        require(cfg.num > 0, "StableSwapper/exceeds-num");
        require(block.timestamp >= cfg.zzz + cfg.hop, "StableSwapper/too-soon");
        unchecked { configs[key].num = cfg.num - 1; }
        configs[key].zzz = uint32(block.timestamp);

        if (minOut == 0) minOut = cfg.req;
        require(minOut >= cfg.req, "StableSwapper/min-too-small");

        if (cfg.num == 1) pairHashes.remove(keccak256(abi.encode(src, dst))); // TODO: maybe no cleanup?

        out = swapper.swap(src, dst, cfg.lot, minOut, callee, data);
    }
}
