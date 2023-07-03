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

import "src/funnels/uniV3/LiquidityAmounts.sol";
import "src/funnels/uniV3/TickMath.sol";
import "src/funnels/uniV3/PoolAddress.sol";
import "src/funnels/uniV3/LiquidityAmountsRoundingUp.sol";

interface DepositorLike {
    struct DepositParams {
        address gem0;
        address gem1;
        uint256 amt0;
        uint256 amt1;
        uint256 minAmt0;
        uint256 minAmt1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
    }

    function deposit(DepositParams memory params) external returns (
        uint128 liquidity,
        uint256 amt0,
        uint256 amt1
    );

    struct WithdrawParams {
        address gem0;
        address gem1;
        uint128 liquidity;
        uint256 minAmt0;
        uint256 minAmt1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        bool collectFees;
    }

    function withdraw(WithdrawParams memory p) external returns (
        uint256 amt0,
        uint256 amt1
    );

    struct CollectParams {
        address gem0;
        address gem1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
    }

    function collect(CollectParams memory p) external returns (
        uint256 amt0,
        uint256 amt1
    );
}

interface UniV3PoolLike {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
}

contract StableDepositor {
    mapping (address => uint256) public wards;
    mapping (address => uint256) public buds;
    mapping (address => uint256) public bots;
    mapping (address => mapping (address => PairConfig)) public configs;

    DepositorLike public immutable depositor;

    address internal immutable uniV3Factory; // 0x1F98431c8aD98523631AE4a59f267346ea31F984

    event Rely     (address indexed usr);
    event Deny     (address indexed usr);
    event Kissed   (address indexed usr);
    event Dissed   (address indexed usr);
    event Permit (address indexed usr);
    event Forbid (address indexed usr);
    event Config (address indexed gemA, address indexed gemB, PairConfig data);

    constructor(address uniV3Factory_, address _depositor) {
        uniV3Factory = uniV3Factory_;
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
    function kiss  (address usr) external auth {  buds[usr] = 1; emit Kissed(usr); }
    function diss  (address usr) external auth {  buds[usr] = 0; emit Dissed(usr); }
    function permit(address usr) external toll {  bots[usr] = 1; emit Permit(usr); }
    function forbid(address usr) external toll {  bots[usr] = 0; emit Forbid(usr); }

    struct PairConfig {
        uint32  count;
        uint24  fee;
        int24   tickLower;
        int24   tickUpper;
        uint128 amt0; // TODO: should amts really be 112?
        uint128 amt1;
        uint128 minAmt0;
        uint128 minAmt1;
        uint128 reqAmt0;
        uint128 reqAmt1;
    }

    // gemA, gemB as params
    function setConfig(address gemA, address gemB, PairConfig memory cfg) external toll {
        (address gem0, address gem1) = gemA < gemB ? (gemA, gemB) : (gemB, gemA);
        configs[gem0][gem1] = cfg;
        emit Config(gemA, gemB, cfg);
    }

    function _getOptimalDepositAmounts(address gem0, address gem1, PairConfig memory cfg) internal view returns (uint256 amt0, uint256 amt1) {
        (uint160 sqrtPriceX96,,,,,,) =
            UniV3PoolLike(PoolAddress.getPoolAddress(uniV3Factory, gem0, gem1, cfg.fee)).slot0();

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(cfg.tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(cfg.tickUpper);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, cfg.amt0, cfg.amt1);

        (amt0, amt1) = LiquidityAmountsRoundingUp.getAmountsForLiquidityRoundingUp(
            sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, liquidity
        );
    }

    // Note: the keeper's minAmts value must be updated whenever configs[gem0][gem1] is changed.
    // Failing to do so may result in this call reverting or in taking on more slippage than intended (up to a limit controlled by configs[src][dst].reqOut).
    function deposit(address gem0, address gem1, uint128 minAmt0, uint128 minAmt1)
        keep
        external
        returns (uint128 liquidity, uint256 amt0, uint256 amt1) {

        // Note: we rely on Depositor to enforce p.gem0 < p.gem1
        PairConfig memory cfg = configs[gem0][gem1];

        require(cfg.count > 0, "StableDepositor/exceeds-count");
        configs[gem0][gem1].count = cfg.count - 1;

        if (minAmt0 == 0) minAmt0 = cfg.reqAmt0;
        if (minAmt1 == 0) minAmt1 = cfg.reqAmt1;
        require(minAmt0 >= cfg.reqAmt0, "StableSwapper/min-amt0-too-small");
        require(minAmt1 >= cfg.reqAmt1, "StableSwapper/min-amt1-too-small");

        // Pre-calculating the exact amounts to deposit avoids having to send leftover tokens back to the buffer, saving ~40k gas
        (amt0, amt1) = _getOptimalDepositAmounts(gem0, gem1, cfg);

        DepositorLike.DepositParams memory depositParams = DepositorLike.DepositParams({
            gem0     : gem0,
            gem1     : gem1,
            amt0     : amt0,
            amt1     : amt1,
            minAmt0  : minAmt0,
            minAmt1  : minAmt1,
            fee      : cfg.fee,
            tickLower: cfg.tickLower,
            tickUpper: cfg.tickUpper
        });
        (liquidity, amt0, amt1) = depositor.deposit(depositParams);
    }

    // Note: the keeper's minAmts value must be updated whenever configs[gem0][gem1] is changed.
    // Failing to do so may result in this call reverting or in taking on more slippage than intended (up to a limit controlled by configs[src][dst].reqOut).
    function withdraw(address gem0, address gem1, uint128 minAmt0, uint128 minAmt1)
        keep
        external
        returns (uint128 liquidity, uint256 amt0, uint256 amt1) {

        // Note: we rely on Depositor to enforce p.gem0 < p.gem1
        PairConfig memory cfg = configs[gem0][gem1];

        require(cfg.count > 0, "StableDepositor/exceeds-count");
        configs[gem0][gem1].count = cfg.count - 1;

        if (minAmt0 == 0) minAmt0 = cfg.reqAmt0;
        if (minAmt1 == 0) minAmt1 = cfg.reqAmt1;
        require(minAmt0 >= cfg.reqAmt0, "StableSwapper/min-amt0-too-small");
        require(minAmt1 >= cfg.reqAmt1, "StableSwapper/min-amt1-too-small");

        (uint160 _sqrtPriceX96,,,,,,) =
            UniV3PoolLike(PoolAddress.getPoolAddress(uniV3Factory, gem0, gem1, cfg.fee)).slot0();

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            _sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(cfg.tickLower),
            TickMath.getSqrtRatioAtTick(cfg.tickUpper),
            cfg.amt0,
            cfg.amt1
        );

        DepositorLike.WithdrawParams memory withdrawParams = DepositorLike.WithdrawParams({
            gem0       : gem0,
            gem1       : gem1,
            liquidity  : liquidity,
            minAmt0    : cfg.minAmt0,
            minAmt1    : cfg.minAmt1,
            fee        : cfg.fee,
            tickLower  : cfg.tickLower,
            tickUpper  : cfg.tickUpper,
            collectFees: true
        });
        (amt0, amt1) = depositor.withdraw(withdrawParams);
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
