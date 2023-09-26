pragma solidity ^0.8.16;

import {LiquidityAmounts, FixedPoint96} from "src/funnels/uniV3/LiquidityAmounts.sol";
import {TickMath}           from "src/funnels/uniV3/TickMath.sol";
import {FullMath}           from "src/funnels/uniV3/FullMath.sol";

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

    struct PositionInfo {
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    function positions(bytes32) external view returns (PositionInfo memory);
}

// https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/libraries/SafeCast.sol
library SafeCast {
    function toInt128(int256 y) internal pure returns (int128 z) {
        require((z = int128(y)) == y);
    }

    function toInt256(uint256 y) internal pure returns (int256 z) {
        require(y < 2**255);
        z = int256(y);
    }
}

library UniV3Utils {
    using SafeCast for uint256;

    address constant UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    
    // https://github.com/Uniswap/v3-periphery/blob/464a8a49611272f7349c970e0fadb7ec1d3c1086/contracts/libraries/PoolAddress.sol#L33
    function getPool(address gem0, address gem1, uint24 fee) internal pure returns (UniV3PoolLike pool) {
        pool = UniV3PoolLike(address(uint160(uint256(keccak256(abi.encodePacked(
                hex'ff',
                UNIV3_FACTORY,
                keccak256(abi.encode(gem0, gem1, fee)),
                bytes32(0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54) // POOL_INIT_CODE_HASH
            ))))));
    }

    function getLiquidity(
        address owner,
        address gem0,
        address gem1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint128 liquidity) {
        return getPool(gem0, gem1, fee).positions(keccak256(abi.encodePacked(owner, tickLower, tickUpper))).liquidity;
    }

    function getCurrentTick(address gem0, address gem1, uint24 fee) internal view returns (int24 tick) {
        (, tick,,,,,) = getPool(gem0, gem1, fee).slot0();
    }

    function getLiquidityForAmts(
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

    // https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/libraries/UnsafeMath.sol#L12
    function divRoundingUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := add(div(x, y), gt(mod(x, y), 0))
        }
    }

    // https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/libraries/SqrtPriceMath.sol#L153
    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount0) {
        unchecked {
            if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

            uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;
            uint256 numerator2 = sqrtRatioBX96 - sqrtRatioAX96;

            require(sqrtRatioAX96 > 0);

            return
                roundUp
                    ? divRoundingUp(
                        FullMath.mulDivRoundingUp(numerator1, numerator2, sqrtRatioBX96),
                        sqrtRatioAX96
                    )
                    : FullMath.mulDiv(numerator1, numerator2, sqrtRatioBX96) / sqrtRatioAX96;
        }
    }

    // https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/libraries/SqrtPriceMath.sol#L182
    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount1) {
        unchecked {
            if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

            return
                roundUp
                    ? FullMath.mulDivRoundingUp(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96)
                    : FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
        }
    }

    // https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/libraries/SqrtPriceMath.sol#L201
    function getAmount0Delta_(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        int128 liquidity
    ) internal pure returns (int256 amount0) {
        unchecked {
            return
                liquidity < 0
                    ? -getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(-liquidity), false).toInt256()
                    : getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(liquidity), true).toInt256();
        }
    }

    // https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/libraries/SqrtPriceMath.sol#L217C7-L217C7
    function getAmount1Delta_(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        int128 liquidity
    ) internal pure returns (int256 amount1) {
        unchecked {
            return
                liquidity < 0
                    ? -getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(-liquidity), false).toInt256()
                    : getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(liquidity), true).toInt256();
        }
    }

    // adapted from https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/UniswapV3Pool.sol#L327
    function getExpectedAmounts(
        address gem0,
        address gem1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 amt0Desired,
        uint256 amt1Desired,
        bool withdrawal
    ) internal view returns (uint256 expectedAmt0, uint256 expectedAmt1) {
        unchecked {
            UniV3PoolLike pool = getPool(gem0, gem1, fee);
            (uint160 sqrtPriceX96, int24 tick,,,,,) = pool.slot0();
            int256 liqDelta = int256(uint256(liquidity == 0 ? getLiquidityForAmts(pool, tickLower, tickUpper, amt0Desired, amt1Desired) : liquidity));
            int128 signedLiqDelta = int128(withdrawal ? -liqDelta : liqDelta);
            
            if (tick < tickUpper) {
                int256 expectedAmt0_ = getAmount0Delta_(
                    tick < tickLower ? TickMath.getSqrtRatioAtTick(tickLower) : sqrtPriceX96,
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    signedLiqDelta
                );
                expectedAmt0 = uint256(withdrawal ? -expectedAmt0_: expectedAmt0_);
            }
            if (tick >= tickLower) {
                int256 expectedAmt1_ = getAmount1Delta_(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    tick >= tickUpper ? TickMath.getSqrtRatioAtTick(tickUpper) : sqrtPriceX96,
                    signedLiqDelta
                );
                expectedAmt1 = uint256(withdrawal ? -expectedAmt1_: expectedAmt1_);
            }
        }
    }
}