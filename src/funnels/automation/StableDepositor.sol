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
        uint256 amt0Desired; // relevant only if liquidity == 0
        uint256 amt1Desired; // relevant only if liquidity == 0
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
        uint256 amt1
    );

    struct CollectParams {
        address gem0;
        address gem1;
        uint24  fee;
        int24   tickLower;
        int24   tickUpper;
    }

    function collect(CollectParams memory p) external returns (
        uint256 amt0,
        uint256 amt1
    );
}

contract StableDepositor {
    mapping (address => uint256) public wards;
    mapping (address => uint256) public buds;
    mapping (address => uint256) public bots;
    mapping (address => mapping (address => PairConfig)) public configs;

    DepositorLike public immutable depositor;

    event Rely  (address indexed usr);
    event Deny  (address indexed usr);
    event Kiss  (address indexed usr);
    event Diss  (address indexed usr);
    event Permit(address indexed usr);
    event Forbid(address indexed usr);
    event Config(address indexed gemA, address indexed gemB, PairConfig data);

    constructor(address _depositor) {
        depositor = DepositorLike(_depositor);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "StableSwapper/not-authorized");
        _;
    }

    // permissionned to facilitators
    modifier toll {
        require(buds[msg.sender] == 1, "StableSwapper/non-facilitator");
        _;
    }

    // permissionned to whitelisted keepers
    modifier keep {
        require(bots[msg.sender] == 1, "StableSwapper/non-keeper");
        _;
    }

    function rely  (address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny  (address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    function kiss  (address usr) external auth {  buds[usr] = 1; emit Kiss(usr); }
    function diss  (address usr) external auth {  buds[usr] = 0; emit Diss(usr); }
    function permit(address usr) external toll {  bots[usr] = 1; emit Permit(usr); }
    function forbid(address usr) external toll {  bots[usr] = 0; emit Forbid(usr); }

    struct PairConfig {
        uint32  count;
        uint24  fee;
        int24   tickLower;
        int24   tickUpper;
        uint128 amt0;
        uint128 amt1;
        uint128 minAmt0;
        uint128 minAmt1;
        uint128 reqAmt0;
        uint128 reqAmt1;
    }

    function setConfig(address gemA, address gemB, PairConfig memory cfg) external toll {
        (address gem0, address gem1) = gemA < gemB ? (gemA, gemB) : (gemB, gemA);
        configs[gem0][gem1] = cfg;
        emit Config(gemA, gemB, cfg);
    }

    // Note: the keeper's minAmts value must be updated whenever configs[gem0][gem1] is changed.
    // Failing to do so may result in this call reverting or in taking on more slippage than intended (up to a limit controlled by configs[src][dst].reqOut).
    function deposit(address gem0, address gem1, uint128 minAmt0, uint128 minAmt1)
        keep
        external
        returns (uint128 liquidity, uint256 amt0, uint256 amt1)
    {

        // Note: we rely on Depositor to enforce p.gem0 < p.gem1
        PairConfig memory cfg = configs[gem0][gem1];

        require(cfg.count > 0, "StableDepositor/exceeds-count");
        configs[gem0][gem1].count = cfg.count - 1;

        if (minAmt0 == 0) minAmt0 = cfg.reqAmt0;
        if (minAmt1 == 0) minAmt1 = cfg.reqAmt1;
        require(minAmt0 >= cfg.reqAmt0, "StableSwapper/min-amt0-too-small");
        require(minAmt1 >= cfg.reqAmt1, "StableSwapper/min-amt1-too-small");

        DepositorLike.LiquidityParams memory p = DepositorLike.LiquidityParams({
            gem0       : gem0,
            gem1       : gem1,
            fee        : cfg.fee,
            tickLower  : cfg.tickLower,
            tickUpper  : cfg.tickUpper,
            liquidity  : 0,             // use desired amount
            amt0Desired: cfg.amt0,
            amt1Desired: cfg.amt1,
            amt0Min    : minAmt0,
            amt1Min    : minAmt1
        });
        (liquidity, amt0, amt1) = depositor.deposit(p);
    }

    // Note: the keeper's minAmts value must be updated whenever configs[gem0][gem1] is changed.
    // Failing to do so may result in this call reverting or in taking on more slippage than intended (up to a limit controlled by configs[src][dst].reqOut).
    function withdraw(address gem0, address gem1, uint128 minAmt0, uint128 minAmt1)
        keep
        external
        returns (uint128 liquidity, uint256 amt0, uint256 amt1)
    {
        // Note: we rely on Depositor to enforce p.gem0 < p.gem1
        PairConfig memory cfg = configs[gem0][gem1];

        require(cfg.count > 0, "StableDepositor/exceeds-count");
        configs[gem0][gem1].count = cfg.count - 1;

        if (minAmt0 == 0) minAmt0 = cfg.reqAmt0;
        if (minAmt1 == 0) minAmt1 = cfg.reqAmt1;
        require(minAmt0 >= cfg.reqAmt0, "StableSwapper/min-amt0-too-small");
        require(minAmt1 >= cfg.reqAmt1, "StableSwapper/min-amt1-too-small");

        DepositorLike.LiquidityParams memory p = DepositorLike.LiquidityParams({
            gem0       : gem0,
            gem1       : gem1,
            fee        : cfg.fee,
            tickLower  : cfg.tickLower,
            tickUpper  : cfg.tickUpper,
            liquidity  : 0,             // use desired amount
            amt0Desired: cfg.amt0,
            amt1Desired: cfg.amt1,
            amt0Min    : minAmt0,
            amt1Min    : minAmt1
        });
        (liquidity, amt0, amt1) = depositor.withdraw(p, true);
    }

    function collect(address gem0, address gem1) toll external returns (uint256 amt0, uint256 amt1) {
        // Note: we rely on Depositor to enforce p.gem0 < p.gem1
        PairConfig memory cfg = configs[gem0][gem1];

        DepositorLike.CollectParams memory collectParams = DepositorLike.CollectParams({
            gem0     : gem0,
            gem1     : gem1,
            fee      : cfg.fee,
            tickLower: cfg.tickLower,
            tickUpper: cfg.tickUpper
        });
        (amt0, amt1) = depositor.collect(collectParams);
    }
}
