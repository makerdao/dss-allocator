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

import {LiquidityAmounts} from "src/funnels/uniV3/LiquidityAmounts.sol";
import {TickMath}         from "src/funnels/uniV3/TickMath.sol";

interface RolesLike {
    function canCall(bytes32, address, address, bytes4) external view returns (bool);
}

interface GemLike {
    function transferFrom(address, address, uint256) external;
}

// https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/UniswapV3Pool.sol
interface UniV3PoolLike {
    function positions(bytes32) external view returns (
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );

    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );

    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);

    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1);

    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);
}

contract Depositor {
    mapping (address => uint256) public wards;                         // Admins
    mapping (address => mapping (address => mapping (uint24 => PairLimit))) public limits; // Rate limit parameters per (gem0, gem1) pair

    RolesLike public immutable roles;        // Contract managing access control for this Depositor
    bytes32   public immutable ilk;          // Collateral type
    address   public immutable uniV3Factory; // Uniswap V3 factory
    address   public immutable buffer;       // Contract from/to which the two tokens that make up the liquidity position are pulled/pushed

    struct PairLimit {
        uint32  zzz; // Timestamp of the last liquidity change for a (gem0, gem1) pool
        uint32  hop; // Cooldown period it has to wait between changes to the liquidity of a (gem0, gem1) pool
        uint96 due0; // Pending amount of gem0 that can still be added until next hop for a (gem0, gem1) pool
        uint96 due1; // Pending amount of gem1 that can still be added until next hop for a (gem0, gem1) pool
        uint96 cap0; // Maximum amount of gem0 that can be added as liquidity each hop for a (gem0, gem1) pool
        uint96 cap1; // Maximum amount of gem1 that can be added as liquidity each hop for a (gem0, gem1) pool
    }

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event SetLimits(address indexed gem0, address indexed gem1, uint24 indexed fee, uint32 hop, uint96 cap0, uint96 cap1);
    event Deposit(address indexed sender, address indexed gem0, address indexed gem1, uint128 liquidity, uint256 amt0, uint256 amt1);
    event Withdraw(address indexed sender, address indexed gem0, address indexed gem1, uint128 liquidity, uint256 amt0, uint256 amt1, uint256 fees0, uint256 fees1);
    event Collect(address indexed sender, address indexed gem0, address indexed gem1, uint256 fees0, uint256 fees1);

    constructor(address roles_, bytes32 ilk_, address uniV3Factory_, address buffer_) {
        roles        = RolesLike(roles_);
        ilk          = ilk_;
        uniV3Factory = uniV3Factory_;
        buffer       = buffer_;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(roles.canCall(ilk, msg.sender, address(this), msg.sig) || wards[msg.sender] == 1, "Depositor/not-authorized");
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

    function setLimits(address gem0, address gem1, uint24 fee, uint32 hop, uint96 cap0, uint96 cap1) external auth {
        require(gem0 < gem1, "Depositor/wrong-gem-order");
        limits[gem0][gem1][fee].hop = hop;
        if (limits[gem0][gem1][fee].due0 > cap0) { limits[gem0][gem1][fee].due0 = cap0; }
        if (limits[gem0][gem1][fee].due1 > cap1) { limits[gem0][gem1][fee].due1 = cap1; }
        limits[gem0][gem1][fee].cap0 = cap0;
        limits[gem0][gem1][fee].cap1 = cap1;
        emit SetLimits(gem0, gem1, fee, hop, cap0, cap1);
    }

    // https://github.com/Uniswap/v3-periphery/blob/464a8a49611272f7349c970e0fadb7ec1d3c1086/contracts/libraries/PoolAddress.sol#L33
    function _getPool(address gem0, address gem1, uint24 fee) internal view returns (UniV3PoolLike pool) {
        pool = UniV3PoolLike(address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            uniV3Factory,
            keccak256(abi.encode(gem0, gem1, fee)),
            bytes32(0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54) // POOL_INIT_CODE_HASH
        ))))));
    }

    function getPosition(
        address gem0,
        address gem1,
        uint24  fee,
        int24   tickLower,
        int24   tickUpper
    ) external view returns (
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    ) {
        return _getPool(gem0, gem1, fee).
            positions(keccak256(abi.encodePacked(address(this), tickLower, tickUpper)));
    }

    function _getLiquidityForAmts(
        UniV3PoolLike pool,
        int24         tickLower,
        int24         tickUpper,
        uint256       amt0Desired,
        uint256       amt1Desired
    ) internal view returns (uint128 liquidity) {
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            amt0Desired,
            amt1Desired
        );
    }

    struct MintCallbackData {
        address gem0;
        address gem1;
        uint24  fee;
    }

    // https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/interfaces/callback/IUniswapV3MintCallback.sol#L6
    function uniswapV3MintCallback(
        uint256        amt0Owed,
        uint256        amt1Owed,
        bytes calldata data
    ) external {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        address pool = address(_getPool(decoded.gem0, decoded.gem1, decoded.fee));
        require(msg.sender == pool, "Depositor/sender-not-a-pool");

        if (amt0Owed > 0) GemLike(decoded.gem0).transferFrom(buffer, msg.sender, amt0Owed);
        if (amt0Owed > 0) GemLike(decoded.gem1).transferFrom(buffer, msg.sender, amt1Owed);
    }

    struct LiquidityParams {
        address gem0;
        address gem1;
        uint24  fee;
        int24   tickLower;
        int24   tickUpper;
        uint128 liquidity;   // Useful for clearing out the entire liquidity of a position
        uint256 amt0Desired; // Relevant only if liquidity == 0
        uint256 amt1Desired; // Relevant only if liquidity == 0
        uint256 amt0Min;
        uint256 amt1Min;
    }

    function deposit(LiquidityParams memory p)
        external
        auth
        returns (uint128 liquidity, uint256 amt0, uint256 amt1)
    {
        require(p.gem0 < p.gem1, "Depositor/wrong-gem-order");

        PairLimit memory limit;
        limit.zzz  = limits[p.gem0][p.gem1][p.fee].zzz;
        limit.hop  = limits[p.gem0][p.gem1][p.fee].hop;
        limit.due0 = limits[p.gem0][p.gem1][p.fee].due0;
        limit.due1 = limits[p.gem0][p.gem1][p.fee].due1;

        unchecked {
            if (block.timestamp - limit.zzz >= limit.hop) {
                // Reset batch
                limit.due0 = limits[p.gem0][p.gem1][p.fee].cap0;
                limit.due1 = limits[p.gem0][p.gem1][p.fee].cap1;
                limit.zzz  = uint32(block.timestamp);
            }
        }

        UniV3PoolLike pool = _getPool(p.gem0, p.gem1, p.fee);
        liquidity = (p.liquidity == 0)
            ? _getLiquidityForAmts(pool, p.tickLower, p.tickUpper, p.amt0Desired, p.amt1Desired)
            : p.liquidity;

        (amt0, amt1) = pool.mint({
            recipient: address(this),
            tickLower: p.tickLower,
            tickUpper: p.tickUpper,
            amount   : liquidity,
            data     : abi.encode(MintCallbackData({gem0: p.gem0, gem1: p.gem1, fee: p.fee}))
        });
        require(amt0 >= p.amt0Min && amt1 >= p.amt1Min, "Depositor/exceeds-slippage");
        require(amt0 <= limit.due0 && amt1 <= limit.due1, "Depositor/exceeds-due-amt");

        limits[p.gem0][p.gem1][p.fee].due0 = limit.due0 - uint96(amt0);
        limits[p.gem0][p.gem1][p.fee].due1 = limit.due1 - uint96(amt1);
        limits[p.gem0][p.gem1][p.fee].zzz  = limit.zzz;

        emit Deposit(msg.sender, p.gem0, p.gem1, liquidity, amt0, amt1);
    }

    function withdraw(LiquidityParams memory p, bool takeFees)
        external
        auth
        returns (uint128 liquidity, uint256 amt0, uint256 amt1, uint256 fees0, uint256 fees1)
    {
        require(p.gem0 < p.gem1, "Depositor/wrong-gem-order");

        PairLimit memory limit;
        limit.zzz  = limits[p.gem0][p.gem1][p.fee].zzz;
        limit.hop  = limits[p.gem0][p.gem1][p.fee].hop;
        limit.due0 = limits[p.gem0][p.gem1][p.fee].due0;
        limit.due1 = limits[p.gem0][p.gem1][p.fee].due1;

        unchecked {
            if (block.timestamp - limit.zzz >= limit.hop) {
                // Reset batch
                limit.due0 = limits[p.gem0][p.gem1][p.fee].cap0;
                limit.due1 = limits[p.gem0][p.gem1][p.fee].cap1;
                limit.zzz  = uint32(block.timestamp);
            }
        }

        UniV3PoolLike pool = _getPool(p.gem0, p.gem1, p.fee);
        liquidity = (p.liquidity == 0)
            ? _getLiquidityForAmts(pool, p.tickLower, p.tickUpper, p.amt0Desired, p.amt1Desired)
            : p.liquidity;

        (amt0, amt1) = pool.burn({ tickLower: p.tickLower, tickUpper: p.tickUpper, amount: liquidity });
        require(amt0 >= p.amt0Min && amt1 >= p.amt1Min,  "Depositor/exceeds-slippage");
        require(amt0 <= limit.due0 && amt1 <= limit.due1, "Depositor/exceeds-due-amt");

        limits[p.gem0][p.gem1][p.fee].due0 = limit.due0 - uint96(amt0);
        limits[p.gem0][p.gem1][p.fee].due1 = limit.due1 - uint96(amt1);

        (uint256 collected0, uint256 collected1) = pool.collect({
            recipient       : buffer,
            tickLower       : p.tickLower,
            tickUpper       : p.tickUpper,
            amount0Requested: takeFees ? type(uint128).max : uint128(amt0),
            amount1Requested: takeFees ? type(uint128).max : uint128(amt1)
        });
        (fees0, fees1) = (collected0 - amt0, collected1 - amt1);

        emit Withdraw(msg.sender, p.gem0, p.gem1, liquidity, amt0, amt1, fees0, fees1);
    }

    struct CollectParams {
        address gem0;
        address gem1;
        uint24  fee;
        int24   tickLower;
        int24   tickUpper;
    }

    function collect(CollectParams memory p)
        external
        auth
        returns (uint256 fees0, uint256 fees1)
    {
        require(p.gem0 < p.gem1, "Depositor/wrong-gem-order");

        UniV3PoolLike pool = _getPool(p.gem0, p.gem1, p.fee);
        pool.burn({ tickLower: p.tickLower, tickUpper: p.tickUpper, amount: 0 }); // Update the position's owed fees

        (fees0, fees1) = pool.collect({
            recipient       : buffer,
            tickLower       : p.tickLower,
            tickUpper       : p.tickUpper,
            amount0Requested: type(uint128).max,
            amount1Requested: type(uint128).max
        });

        emit Collect(msg.sender, p.gem0, p.gem1, fees0, fees1);
    }
}
