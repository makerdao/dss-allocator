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

interface DepositorUniV3Like {
    struct LiquidityParams {
        address gem0;
        address gem1;
        uint24  fee;
        int24   tickLower;
        int24   tickUpper;
        uint128 liquidity;
        uint256 amt0Desired; // Relevant only if liquidity == 0
        uint256 amt1Desired; // Relevant only if liquidity == 0
        uint256 amt0Min;
        uint256 amt1Min;
    }

    function deposit(LiquidityParams memory params) external returns (
        uint128 liquidity,
        uint256 amt0,
        uint256 amt1
    );

    function withdraw(LiquidityParams memory p, bool takeFee) external returns (
        uint128 liquidity,
        uint256 amt0,
        uint256 amt1,
        uint256 fees0,
        uint256 fees1
    );

    struct CollectParams {
        address gem0;
        address gem1;
        uint24  fee;
        int24   tickLower;
        int24   tickUpper;
    }

    function collect(CollectParams memory p) external returns (
        uint256 fees0,
        uint256 fees1
    );
}

contract StableDepositorUniV3 {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    mapping (address => uint256) public wards;                           // Admins
    mapping (address => uint256) public buds;                            // Whitelisted keepers
    mapping (bytes32 => RangeConfig) public configs; // Configuration for keepers

    mapping (bytes32 => Range) public ranges;
    EnumerableSet.Bytes32Set private rangeHashes;

    DepositorUniV3Like public immutable depositor; // DepositorUniV3 for this StableDepositorUniV3

    struct RangeConfig {
        int32  num;  // The remaining number of times that a (gem0, gem1) operation can be performed by keepers (> 0: deposit, < 0: withdraw)
        uint32 zzz;  // Timestamp of the last deposit/withdraw execution
        uint96 amt0; // Amount of gem0 to deposit/withdraw each (gem0, gem1) operation
        uint96 amt1; // Amount of gem1 to deposit/withdraw each (gem0, gem1) operation
        uint96 req0; // The minimum required deposit/withdraw amount of gem0 to insist on in each (gem0, gem1) operation
        uint96 req1; // The minimum required deposit/withdraw amount of gem1 to insist on in each (gem0, gem1) operation
        uint32 hop;  // Cooldown period it has to wait between deposit/withdraw executions
    }

    struct Range {
        address gem0;
        address gem1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
    }

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event SetConfig(address indexed gem0, address indexed gem1, uint24 indexed fee, int24 tickLower, int24 tickUpper, int32 num, uint32 hop, uint96 amt0, uint96 amt1, uint96 req0, uint96 req1);

    constructor(address _depositor) {
        depositor = DepositorUniV3Like(_depositor);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "StableDepositorUniV3/not-authorized");
        _;
    }

    // Permissionned to whitelisted keepers
    modifier toll {
        require(buds[msg.sender] == 1, "StableDepositorUniV3/non-keeper");
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

    function getRangeHash(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(gem0, gem1, fee, tickLower, tickUpper));
    }

    function getConfig(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper) external view returns (int32 num, uint32 zzz, uint96 amt0, uint96 amt1, uint96 req0, uint96 req1, uint32 hop) {
        RangeConfig memory cfg = configs[getRangeHash(gem0, gem1, fee, tickLower, tickUpper)];
        return (cfg.num, cfg.zzz, cfg.amt0, cfg.amt1, cfg.req0, cfg.req1, cfg.hop);
    }


    function setConfig(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, int32 num, uint32 hop, uint96 amt0, uint96 amt1, uint96 req0, uint96 req1) external auth {
        require(gem0 < gem1, "StableDepositorUniV3/wrong-gem-order");
        bytes32 key = getRangeHash(gem0, gem1, fee, tickLower, tickUpper);
        configs[key] = RangeConfig({
            num:  num,
            zzz:  0,
            amt0: amt0,
            amt1: amt1,
            req0: req0,
            req1: req1,
            hop:  hop
        });
        if (num != 0) { // TODO: check hop < type(uint32).max ?
            if (rangeHashes.add(key)) ranges[key] = Range(gem0, gem1, fee, tickLower, tickUpper);
        } else {
            rangeHashes.remove(key);
        }
        emit SetConfig(gem0, gem1, fee, tickLower, tickUpper, num, hop, amt0, amt1, req0, req1);
    }

    function numRanges() external view returns (uint256) {
        return rangeHashes.length();
    }

    function rangeAt(uint256 index) external view returns (Range memory) {
        return ranges[rangeHashes.at(index)];
    }

    function doDeposit(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 amt0Min, uint128 amt1Min, RangeConfig memory cfg) internal returns (uint128 liquidity, uint256 amt0, uint256 amt1) {
        DepositorUniV3Like.LiquidityParams memory p = DepositorUniV3Like.LiquidityParams({
            gem0       : gem0,
            gem1       : gem1,
            fee        : fee,
            tickLower  : tickLower,
            tickUpper  : tickUpper,
            liquidity  : 0,         // Use desired amounts
            amt0Desired: cfg.amt0,
            amt1Desired: cfg.amt1,
            amt0Min    : amt0Min,
            amt1Min    : amt1Min
        });
        (liquidity, amt0, amt1) = depositor.deposit(p);
    }

    // Note: the keeper's minAmts value must be updated whenever configs[gem0][gem1][fee][tickLower][tickUpper] is changed.
    // Failing to do so may result in this call reverting or in taking on more slippage than intended (up to a limit controlled by configs[gem0][gem1][fee][tickLower][tickUpper].req0/1).
    function deposit(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 amt0Min, uint128 amt1Min)
        toll
        external
        returns (uint128 liquidity, uint256 amt0, uint256 amt1)
    {
        bytes32 key = getRangeHash(gem0, gem1, fee, tickLower, tickUpper);
        RangeConfig memory cfg = configs[key];

        require(cfg.num > 0, "StableDepositorUniV3/exceeds-num");
        require(block.timestamp >= cfg.zzz + cfg.hop, "StableDepositorUniV3/too-soon");
        unchecked { configs[key].num = cfg.num - 1; }
        configs[key].zzz = uint32(block.timestamp);

        if (amt0Min == 0) amt0Min = cfg.req0;
        if (amt1Min == 0) amt1Min = cfg.req1;
        require(amt0Min >= cfg.req0, "StableDepositorUniV3/min-amt0-too-small");
        require(amt1Min >= cfg.req1, "StableDepositorUniV3/min-amt1-too-small");

        if (cfg.num == 1) rangeHashes.remove(key); // TODO: maybe no cleanup?

        (liquidity, amt0, amt1) = doDeposit(gem0, gem1, fee, tickLower, tickUpper, amt0Min, amt1Min, cfg);
    }

    function doWithdraw(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 amt0Min, uint128 amt1Min, RangeConfig memory cfg) internal returns (uint128 liquidity, uint256 amt0, uint256 amt1, uint256 fees0, uint256 fees1) {
        DepositorUniV3Like.LiquidityParams memory p = DepositorUniV3Like.LiquidityParams({
            gem0       : gem0,
            gem1       : gem1,
            fee        : fee,
            tickLower  : tickLower,
            tickUpper  : tickUpper,
            liquidity  : 0,         // Use desired amounts
            amt0Desired: cfg.amt0,
            amt1Desired: cfg.amt1,
            amt0Min    : amt0Min,
            amt1Min    : amt1Min
        });
        (liquidity, amt0, amt1, fees0, fees1) = depositor.withdraw(p, true);
    }

    // Note: the keeper's minAmts value must be updated whenever configs[gem0][gem1][fee][tickLower][tickUpper] is changed.
    // Failing to do so may result in this call reverting or in taking on more slippage than intended (up to a limit controlled by configs[gem0][gem1][fee][tickLower][tickUpper].req0/1).
    function withdraw(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 amt0Min, uint128 amt1Min)
        toll
        external
        returns (uint128 liquidity, uint256 amt0, uint256 amt1, uint256 fees0, uint256 fees1)
    {
        bytes32 key = getRangeHash(gem0, gem1, fee, tickLower, tickUpper);
        RangeConfig memory cfg = configs[key];

        require(cfg.num < 0, "StableDepositorUniV3/exceeds-num");
        require(block.timestamp >= cfg.zzz + cfg.hop, "StableDepositorUniV3/too-soon");
        unchecked { configs[key].num = cfg.num + 1; }
        configs[key].zzz = uint32(block.timestamp);

        if (amt0Min == 0) amt0Min = cfg.req0;
        if (amt1Min == 0) amt1Min = cfg.req1;
        require(amt0Min >= cfg.req0, "StableDepositorUniV3/min-amt0-too-small");
        require(amt1Min >= cfg.req1, "StableDepositorUniV3/min-amt1-too-small");

        if (cfg.num == -1) rangeHashes.remove(key); // TODO: maybe no cleanup?

        (liquidity, amt0, amt1, fees0, fees1) = doWithdraw(gem0, gem1, fee, tickLower, tickUpper, amt0Min, amt1Min, cfg);
    }

    function collect(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper)
        toll
        external
        returns (uint256 fees0, uint256 fees1)
    {
        DepositorUniV3Like.CollectParams memory collectParams = DepositorUniV3Like.CollectParams({
            gem0     : gem0,
            gem1     : gem1,
            fee      : fee,
            tickLower: tickLower,
            tickUpper: tickUpper
        });
        (fees0, fees1) = depositor.collect(collectParams);
    }
}
