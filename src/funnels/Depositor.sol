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

import "./uniV3/LiquidityAmounts.sol";
import "./uniV3/TickMath.sol";

interface RolesLike {
    function canCall(bytes32, address, address, bytes4) external view returns (bool);
}

interface GemLike {
    function allowance(address, address) external view returns (uint256);
    function approve(address, uint256) external;
    function transfer(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

// https://github.com/Uniswap/v3-periphery/blob/464a8a49611272f7349c970e0fadb7ec1d3c1086/contracts/interfaces/INonfungiblePositionManager.sol#L17
interface PositionManagerLike {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    /// @notice Creates a new position wrapped in a NFT
    /// @dev Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized
    /// a method does not exist, i.e. the pool is assumed to be initialized.
    /// @param params The params necessary to mint a position, encoded as `MintParams` in calldata
    /// @return tokenId The ID of the token that represents the minted position
    /// @return liquidity The amount of liquidity for this position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Increases the amount of liquidity in a position, with tokens paid by the `msg.sender`
    /// @param params tokenId The ID of the token for which liquidity is being increased,
    /// amount0Desired The desired amount of token0 to be spent,
    /// amount1Desired The desired amount of token1 to be spent,
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    /// deadline The time by which the transaction must be included to effect the change
    /// @return liquidity The new liquidity amount as a result of the increase
    /// @return amount0 The amount of token0 to acheive resulting liquidity
    /// @return amount1 The amount of token1 to acheive resulting liquidity
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Decreases the amount of liquidity in a position and accounts it to the position
    /// @param params tokenId The ID of the token for which liquidity is being decreased,
    /// amount The amount by which liquidity will be decreased,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @return amount0 The amount of token0 accounted to the position's tokens owed
    /// @return amount1 The amount of token1 accounted to the position's tokens owed
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    /// @notice Collects up to a maximum amount of fees owed to a specific position to the recipient
    /// @param params tokenId The ID of the NFT for which tokens are being collected,
    /// recipient The account that should receive the tokens,
    /// amount0Max The maximum amount of token0 to collect,
    /// amount1Max The maximum amount of token1 to collect
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);

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

contract Depositor {
    mapping (address => uint256) public wards;
    mapping (address => mapping (address => uint256)) public hops;       // [seconds]   hops[gem0][gem1] is the cooldown one has to wait between changes to the liquidity of a (gem0, gem1) pool
    mapping (address => mapping (address => uint256)) public zzz;        // [seconds]    zzz[gem0][gem1] is the timestamp of the last liquidity change for a (gem0, gem1) pool
    mapping (address => mapping (address => Cap)) public caps;           // [amount]    caps[gem0][gem1] is the tuple (amt0, amt1) indicating the maximum amount of (gem0, gem1) that can be added as liquidity each hop for a (gem0, gem1) pool

    mapping (bytes32 => uint256) public tokenIds;  // key = keccak256(abi.encode(gem0, gem1, fee, tickLower, tickUpper)) => tokenId of the liquidity position

    address   public immutable buffer;                // Contract from/to which the two tokens that make up the liquidity position are pulled/pushed
    RolesLike public immutable roles;                 // Contract managing access control for this Depositor
    bytes32   public immutable ilk;
    address   public immutable uniV3Factory;          // 0x1F98431c8aD98523631AE4a59f267346ea31F984
    address   public immutable uniV3PositionManager;  // 0xC36442b4a4522E871399CD717aBDD847Ab11FE88

    struct Cap {
        uint128 amt0;
        uint128 amt1;
    }

    event Rely (address indexed usr);
    event Deny (address indexed usr);
    event File (bytes32 indexed what, address indexed gemA, address indexed gemB, uint256 data);
    event File (bytes32 indexed what, address indexed gemA, address indexed gemB, uint128 dataA, uint128 dataB);
    event File (bytes32 indexed what, address data);
    event Deposit(address indexed sender, address indexed gem0, address indexed gem1, uint128 liquidity, uint256 amt0, uint256 amt1);
    event Withdraw(address indexed sender, address indexed gem0, address indexed gem1, uint128 liquidity, uint256 amt0, uint256 amt1);
    event Collect(address indexed sender, address indexed gem0, address indexed gem1, uint256 amt0, uint256 amt1);

    constructor(address roles_, bytes32 ilk_, address uniV3Factory_, address uniV3PositionManager_, address buffer_) {
        roles = RolesLike(roles_);
        ilk = ilk_;
        uniV3Factory = uniV3Factory_;
        uniV3PositionManager = uniV3PositionManager_;
        buffer = buffer_;
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(roles.canCall(ilk, msg.sender, address(this), msg.sig) || wards[msg.sender] == 1, "Depositor/not-authorized");
        _;
    }

    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }

    function file(bytes32 what, address gemA, address gemB, uint256 data) external auth {
        (address gem0, address gem1) = gemA < gemB ? (gemA, gemB) : (gemB, gemA);
        if (what == "hop") hops[gem0][gem1] = data;
        else revert("Depositor/file-unrecognized-param");
        emit File(what, gemA, gemB, data);
    }

    function file(bytes32 what, address gemA, address gemB, uint128 dataA, uint128 dataB) external auth {
        (address gem0, address gem1, uint128 data0, uint128 data1) = gemA < gemB ? (gemA, gemB, dataA, dataB) : (gemB, gemA, dataB, dataA);
        if (what == "cap") caps[gem0][gem1] = Cap({ amt0: data0, amt1: data1 });
        else revert("Depositor/file-unrecognized-param");
        emit File(what, gemA, gemB, dataA, dataB);
    }

    // https://github.com/Uniswap/v3-periphery/blob/464a8a49611272f7349c970e0fadb7ec1d3c1086/contracts/libraries/PoolAddress.sol#L33
    function _getPoolAddress(address gem0, address gem1, uint24 fee) internal view returns (address pool) {
        pool = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            uniV3Factory,
            keccak256(abi.encode(gem0, gem1, fee)),
            bytes32(0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54) // POOL_INIT_CODE_HASH
         )))));
    }

    // https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/libraries/UnsafeMath.sol#L12C1-L16C6
    function _divRoundingUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := add(div(x, y), gt(mod(x, y), 0))
        }
    }

    // adapted from https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/libraries/SqrtPriceMath.sol#L153
    function _getAmount0ForLiquidityRoundingUp(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return
            _divRoundingUp(
                FullMath.mulDivRoundingUp(
                    uint256(liquidity) << FixedPoint96.RESOLUTION,
                    sqrtRatioBX96 - sqrtRatioAX96,
                    sqrtRatioBX96
                ),
                sqrtRatioAX96
            );
    }

    // adapted from https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/libraries/SqrtPriceMath.sol#L182
    function _getAmount1ForLiquidityRoundingUp(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        return FullMath.mulDivRoundingUp(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }

    // adapted from https://github.com/Uniswap/v3-periphery/blob/464a8a49611272f7349c970e0fadb7ec1d3c1086/contracts/libraries/LiquidityAmounts.sol#L120
    function _getAmountsForLiquidityRoundingUp(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            amount0 = _getAmount0ForLiquidityRoundingUp(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            amount0 = _getAmount0ForLiquidityRoundingUp(sqrtRatioX96, sqrtRatioBX96, liquidity);
            amount1 = _getAmount1ForLiquidityRoundingUp(sqrtRatioAX96, sqrtRatioX96, liquidity);
        } else {
            amount1 = _getAmount1ForLiquidityRoundingUp(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        }
    }

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

    function _getOptimalDepositAmounts(DepositParams memory p) internal view returns (uint256 amt0, uint256 amt1) {
        (uint160 sqrtPriceX96,,,,,,) = UniV3PoolLike(_getPoolAddress(p.gem0, p.gem1, p.fee)).slot0();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(p.tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(p.tickUpper);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, p.amt0, p.amt1);
        (amt0, amt1) = _getAmountsForLiquidityRoundingUp(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }

    function _addLiquidity(DepositParams memory p, address to) internal returns (uint128 liquidity, uint256 amt0, uint256 amt1) {
        bytes32 key = keccak256(abi.encode(p.gem0, p.gem1, p.fee, p.tickLower, p.tickUpper));
        uint256 tokenId = tokenIds[key];
        if (tokenId == 0) {
            PositionManagerLike.MintParams memory params = PositionManagerLike.MintParams({
                token0: p.gem0,
                token1: p.gem1,
                fee: p.fee,
                tickLower: p.tickLower,
                tickUpper: p.tickUpper,
                amount0Desired: p.amt0,
                amount1Desired: p.amt1,
                amount0Min: p.minAmt0,
                amount1Min: p.minAmt1,
                recipient: to,
                deadline: block.timestamp
            });
            (tokenId, liquidity, amt0, amt1) = PositionManagerLike(uniV3PositionManager).mint(params);
            tokenIds[key] = tokenId;
        } else {
            PositionManagerLike.IncreaseLiquidityParams memory params = PositionManagerLike.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: p.amt0,
                amount1Desired: p.amt1,
                amount0Min: p.minAmt0,
                amount1Min: p.minAmt1,
                deadline: block.timestamp
            });
            (liquidity, amt0, amt1) = PositionManagerLike(uniV3PositionManager).increaseLiquidity(params);
        }
    }

    function deposit(DepositParams memory p) external auth returns (uint128 liquidity, uint256 amt0, uint256 amt1) {
        require(p.gem0 < p.gem1, "Depositor/wrong-gem-order");

        require(block.timestamp >= zzz[p.gem0][p.gem1] + hops[p.gem0][p.gem1], "Depositor/too-soon");
        zzz[p.gem0][p.gem1] = block.timestamp;

        (amt0, amt1) = _getOptimalDepositAmounts(p); // Pre-calculating the exact amounts to deposit avoids having to send leftover tokens back to the buffer, saving ~40k gas
        Cap memory cap = caps[p.gem0][p.gem1];
        require(amt0 <= cap.amt0 && amt1 <= cap.amt1, "Depositor/exceeds-cap");
        require(amt0 >= p.minAmt0 && amt1 >= p.minAmt1, 'Depositor/exceeds-slippage'); // Saves gas by reverting early if slippage check fails

        address buffer_ = buffer;
        GemLike(p.gem0).transferFrom(buffer_, address(this), amt0);
        GemLike(p.gem1).transferFrom(buffer_, address(this), amt1);
        
        // Note: approving type(uint256).max reduces the cumulated gas cost after calling deposit() 3 times or more for the same gem pair
        if (GemLike(p.gem0).allowance(address(this), uniV3PositionManager) < type(uint256).max) {
            GemLike(p.gem0).approve(uniV3PositionManager, type(uint256).max);
        }
        if (GemLike(p.gem1).allowance(address(this), uniV3PositionManager) < type(uint256).max) {
            GemLike(p.gem1).approve(uniV3PositionManager, type(uint256).max);
        }

        (liquidity,,) = _addLiquidity(p, buffer_);

        emit Deposit(msg.sender, p.gem0, p.gem1, liquidity, amt0, amt1);
    }

    struct WithdrawParams {
        address gem0;
        address gem1;
        uint128 liquidity;
        uint256 minAmt0;
        uint256 minAmt1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
    }

    function _removeLiquidity(WithdrawParams memory p) internal returns (uint256 amt0, uint256 amt1) {
        bytes32 key = keccak256(abi.encode(p.gem0, p.gem1, p.fee, p.tickLower, p.tickUpper));
        uint256 tokenId = tokenIds[key];
        require(tokenId > 0, "Depositor/no-position");
        
        PositionManagerLike.DecreaseLiquidityParams memory params = PositionManagerLike.DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: p.liquidity,
            amount0Min: p.minAmt0,
            amount1Min: p.minAmt1,
            deadline: block.timestamp
        });
        PositionManagerLike(uniV3PositionManager).decreaseLiquidity(params);

        PositionManagerLike.CollectParams memory collection = PositionManagerLike.CollectParams({
            tokenId: tokenId,
            recipient: address(buffer),
            amount0Max: type(uint128).max, // using max to also collect fees
            amount1Max: type(uint128).max  // using max to also collect fees
        });
        (amt0, amt1) = PositionManagerLike(uniV3PositionManager).collect(collection);
    }
        
    function withdraw(WithdrawParams memory p) external auth returns (uint256 amt0, uint256 amt1) {
        require(p.gem0 < p.gem1, "Depositor/wrong-gem-order");

        require(block.timestamp >= zzz[p.gem0][p.gem1] + hops[p.gem0][p.gem1], "Depositor/too-soon");
        zzz[p.gem0][p.gem1] = block.timestamp;

        (amt0, amt1) = _removeLiquidity(p);
        Cap memory cap = caps[p.gem0][p.gem1];
        require(amt0 <= cap.amt0 && amt1 <= cap.amt1, "Depositor/exceeds-cap");

        emit Withdraw(msg.sender, p.gem0, p.gem1, p.liquidity, amt0, amt1);
    }

    struct CollectParams {
        address gem0;
        address gem1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
    }

    function collect(CollectParams memory p) external auth returns (uint256 amt0, uint256 amt1) {
        require(p.gem0 < p.gem1, "Depositor/wrong-gem-order");

        bytes32 key = keccak256(abi.encode(p.gem0, p.gem1, p.fee, p.tickLower, p.tickUpper));
        uint256 tokenId = tokenIds[key];
        require(tokenId > 0, "Depositor/no-position");
        
        PositionManagerLike.CollectParams memory collection = PositionManagerLike.CollectParams({
            tokenId: tokenId,
            recipient: address(buffer),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });
        (amt0, amt1) = PositionManagerLike(uniV3PositionManager).collect(collection);

        emit Collect(msg.sender, p.gem0, p.gem1, amt0, amt1);
    }
}
