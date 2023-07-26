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

interface DepositorLike {
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

contract StableDepositor {
    mapping (address => uint256) public wards;                           // Admins
    mapping (address => uint256) public buds;                            // Whitelisted keepers
    mapping (address => mapping (address => mapping (uint24 => mapping (int24 => mapping (int24 => PairConfig))))) public configs; // Configuration for keepers

    DepositorLike public immutable depositor; // Depositor for this StableDepositor

    struct PairConfig {
        uint32 num;  // The remaining number of times that a (gem0, gem1) operation can be performed by keepers
        uint32 zzz;  // Timestamp of the last deposit/withdraw execution
        uint96 amt0; // Amount of gem0 to deposit/withdraw each (gem0, gem1) operation
        uint96 amt1; // Amount of gem1 to deposit/withdraw each (gem0, gem1) operation
        uint96 min0; // The minimum deposit/withdraw amount of gem0 to insist on in each (gem0, gem1) operation
        uint96 min1; // The minimum deposit/withdraw amount of gem1 to insist on in each (gem0, gem1) operation
        uint32 hop;  // Cooldown period it has to wait between deposit/withdraw executions
    }

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event SetConfig(address indexed gem0, address indexed gem1, uint24 indexed fee, int24 tickLower, int24 tickUpper, uint32 num, uint32 hop, uint96 amt0, uint96 amt1, uint96 min0, uint96 min1);

    constructor(address _depositor) {
        depositor = DepositorLike(_depositor);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "StableDepositor/not-authorized");
        _;
    }

    // Permissionned to whitelisted keepers
    modifier toll {
        require(buds[msg.sender] == 1, "StableDepositor/non-keeper");
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

    function setConfig(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, uint32 num, uint32 hop, uint96 amt0, uint96 amt1, uint96 min0, uint96 min1) external auth {
        require(gem0 < gem1, "StableDepositor/wrong-gem-order");
        configs[gem0][gem1][fee][tickLower][tickUpper] = PairConfig({
            num:  num,
            zzz:  0,
            amt0: amt0,
            amt1: amt1,
            min0: min0,
            min1: min1,
            hop:  hop
        });
        emit SetConfig(gem0, gem1, fee, tickLower, tickUpper, num, hop, amt0, amt1, min0, min1);
    }

    // Note: the keeper's minAmts value must be updated whenever configs[gem0][gem1][fee][tickLower][tickUpper] is changed.
    // Failing to do so may result in this call reverting or in taking on more slippage than intended (up to a limit controlled by configs[gem0][gem1][fee][tickLower][tickUpper].min0/1).
    function deposit(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 amt0Min, uint128 amt1Min)
        toll
        external
        returns (uint128 liquidity, uint256 amt0, uint256 amt1)
    {
        PairConfig memory cfg = configs[gem0][gem1][fee][tickLower][tickUpper];

        require(cfg.num > 0, "StableDepositor/exceeds-num");
        require(block.timestamp >= cfg.zzz + cfg.hop, "StableDepositor/too-soon");
        configs[gem0][gem1][fee][tickLower][tickUpper].num = cfg.num - 1;
        configs[gem0][gem1][fee][tickLower][tickUpper].zzz = uint32(block.timestamp);

        if (amt0Min == 0) amt0Min = cfg.min0;
        if (amt1Min == 0) amt1Min = cfg.min1;
        require(amt0Min >= cfg.min0, "StableDepositor/min-amt0-too-small");
        require(amt1Min >= cfg.min1, "StableDepositor/min-amt1-too-small");

        DepositorLike.LiquidityParams memory p = DepositorLike.LiquidityParams({
            gem0       : gem0,
            gem1       : gem1,
            fee        : fee,
            tickLower  : tickLower,
            tickUpper  : tickUpper,
            liquidity  : 0,             // Use desired amounts
            amt0Desired: cfg.amt0,
            amt1Desired: cfg.amt1,
            amt0Min    : amt0Min,
            amt1Min    : amt1Min
        });
        (liquidity, amt0, amt1) = depositor.deposit(p);
    }

    // Note: the keeper's minAmts value must be updated whenever configs[gem0][gem1][fee][tickLower][tickUpper] is changed.
    // Failing to do so may result in this call reverting or in taking on more slippage than intended (up to a limit controlled by configs[gem0][gem1][fee][tickLower][tickUpper].min0/1).
    function withdraw(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 amt0Min, uint128 amt1Min)
        toll
        external
        returns (uint128 liquidity, uint256 amt0, uint256 amt1, uint256 fees0, uint256 fees1)
    {
        PairConfig memory cfg = configs[gem0][gem1][fee][tickLower][tickUpper];

        require(cfg.num > 0, "StableDepositor/exceeds-num");
        require(block.timestamp >= cfg.zzz + cfg.hop, "StableDepositor/too-soon");
        configs[gem0][gem1][fee][tickLower][tickUpper].num = cfg.num - 1;
        configs[gem0][gem1][fee][tickLower][tickUpper].zzz = uint32(block.timestamp);

        if (amt0Min == 0) amt0Min = cfg.min0;
        if (amt1Min == 0) amt1Min = cfg.min1;
        require(amt0Min >= cfg.min0, "StableDepositor/min-amt0-too-small");
        require(amt1Min >= cfg.min1, "StableDepositor/min-amt1-too-small");

        DepositorLike.LiquidityParams memory p = DepositorLike.LiquidityParams({
            gem0       : gem0,
            gem1       : gem1,
            fee        : fee,
            tickLower  : tickLower,
            tickUpper  : tickUpper,
            liquidity  : 0,             // Use desired amounts
            amt0Desired: cfg.amt0,
            amt1Desired: cfg.amt1,
            amt0Min    : amt0Min,
            amt1Min    : amt1Min
        });
        (liquidity, amt0, amt1, fees0, fees1) = depositor.withdraw(p, true);
    }

    function collect(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper)
        toll
        external
        returns (uint256 fees0, uint256 fees1)
    {
        DepositorLike.CollectParams memory collectParams = DepositorLike.CollectParams({
            gem0     : gem0,
            gem1     : gem1,
            fee      : fee,
            tickLower: tickLower,
            tickUpper: tickUpper
        });
        (fees0, fees1) = depositor.collect(collectParams);
    }
}
