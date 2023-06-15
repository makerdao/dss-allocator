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

import "./Swapper.sol";

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

contract Depositor {
    mapping (address => uint256) public wards;
    mapping (bytes32 => uint256) public positions;  // key = keccak256(abi.encode(gem0, gem1, fee, tickLower, tickUpper)) => tokenId of the liquidity position

    address public buffer;                          // Escrow contract from/to which the two tokens that make up the liquidity position are pulled/pushed
    address public roles;                           // Contract managing access control for this Depositor
    address public swapper;                         // Swapper contract

    uint256 internal constant WAD = 10 ** 18;

    address internal immutable uniV3PositionManager;
    address internal immutable uniV3Factory;

    event Rely (address indexed usr);
    event Deny (address indexed usr);
    // event File (bytes32 indexed what, address indexed src, address indexed dst, uint256 data);
    event File (bytes32 indexed what, address data);
    event Deposit(address indexed sender, address indexed gem0, address indexed gem1, uint128 liquidity, uint256 amt0, uint256 amt1);
    event Withdraw(address indexed sender, address indexed gem0, address indexed gem1, uint128 liquidity, uint256 amt0, uint256 amt1);

    constructor(address _uniV3PositionManager, address _uniV3Factory) {
        uniV3PositionManager = _uniV3PositionManager; // 0xC36442b4a4522E871399CD717aBDD847Ab11FE88
        uniV3Factory = _uniV3Factory; // 0x1F98431c8aD98523631AE4a59f267346ea31F984
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        address roles_ = roles;
        bool access;
        if (roles_ != address(0)) {
            (bool ok, bytes memory ret) = roles_.call(
                                            abi.encodeWithSignature(
                                                "canCall(address,address,bytes4)",
                                                msg.sender,
                                                address(this),
                                                msg.sig
                                            )
            );
            access = ok && ret.length == 32 && abi.decode(ret, (bool));
        }
        require(access || wards[msg.sender] == 1, "Depositor/not-authorized");
        _;
    }

    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }

    function file(bytes32 what, address data) external auth {
        if      (what == "buffer")   buffer  = data;
        else if (what == "roles")    roles   = data;
        else if (what == "swapper")  swapper = data;
        else revert("Depositor/file-unrecognized-param");
        emit File(what, data);
    }

    // https://github.com/Uniswap/v3-periphery/blob/464a8a49611272f7349c970e0fadb7ec1d3c1086/contracts/libraries/PoolAddress.sol#L33
    function getPoolAddress(address gem0, address gem1, uint24 fee) internal view returns (address pool) {
        pool = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            uniV3Factory,
            keccak256(abi.encode(gem0, gem1, fee)),
            bytes32(0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54) // POOL_INIT_CODE_HASH
         )))));
    }

    struct DepositParams {
        address gem0;
        address gem1;
        uint256 amt0;
        uint256 amt1;
        uint256 minAmt0;
        uint256 minAmt1;
        uint256 minSwappedOut;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        address swapperCallee;
        bytes swapperData;
    }

    function sortDepositedTokens(DepositParams memory p) internal pure returns (DepositParams memory) {
        (p.gem0, p.gem1, p.amt0, p.amt1, p.minAmt0, p.minAmt1) 
            = p.gem0 < p.gem1 ? (p.gem0, p.gem1, p.amt0, p.amt1, p.minAmt0, p.minAmt1) : (p.gem1, p.gem0, p.amt1, p.amt0, p.minAmt1, p.minAmt0);
        return p;
    }

    function getConvertedAmounts(DepositParams memory p) internal view returns (uint256 amt0_1, uint256 amt1_0) {
        (uint160 sqrtPriceX96,,,,,,) = UniV3PoolLike(getPoolAddress(p.gem0, p.gem1, p.fee)).slot0();
        uint256 p0 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * WAD / uint256(2 ** 192);
        amt0_1 = p.amt0 * p0 / WAD;
        amt1_0 = p.amt1 * WAD / p0;
    }

    function swapBeforeDeposit(DepositParams memory p) internal returns (uint256 amt0, uint256 amt1) {
        (uint256 amt0_1, uint256 amt1_0) = getConvertedAmounts(p);
        // TODO1: return if differences amt0-amt1_0 and amt1-amt0_1 are both lower than some swap threshold
        // TODO2: calculate more accurate swap amounts when callee is UniV3SwapperCallee
        
        uint bought;
        uint sold;
        if (p.amt0 > amt1_0) {
            // need to sell some gem0
            sold = (p.amt0 - amt1_0) / 2;
            bought = Swapper(swapper).swap(p.gem0, p.gem1, sold, p.minSwappedOut, p.swapperCallee, p.swapperData);
            amt0 = p.amt0 - sold;
            amt1 = p.amt1 + bought;

        } else if (p.amt1 > amt0_1) {
            // need to sell some gem1
            sold = (p.amt1 - amt0_1) / 2;
            bought = Swapper(swapper).swap(p.gem1, p.gem0, sold, p.minSwappedOut, p.swapperCallee, p.swapperData);
            amt1 = p.amt1 - sold;
            amt0 = p.amt0 + bought;
        }
    }

    function addLiquidity(DepositParams memory p, address to, uint256 bal0, uint256 bal1) internal returns (uint128 liquidity, uint256 amt0, uint256 amt1) {
        bytes32 key = keccak256(abi.encode(p.gem0, p.gem1, p.fee, p.tickLower, p.tickUpper));
        uint256 tokenId = positions[key];
        if (tokenId == 0) {
            PositionManagerLike.MintParams memory params = PositionManagerLike.MintParams({
                token0: p.gem0,
                token1: p.gem1,
                fee: p.fee,
                tickLower: p.tickLower,
                tickUpper: p.tickUpper,
                amount0Desired: bal0,
                amount1Desired: bal1,
                amount0Min: p.minAmt0,
                amount1Min: p.minAmt1,
                recipient: to,
                deadline: block.timestamp
            });
            (tokenId, liquidity, amt0, amt1) = PositionManagerLike(uniV3PositionManager).mint(params);
            positions[key] = tokenId;
        } else {
            PositionManagerLike.IncreaseLiquidityParams memory params = PositionManagerLike.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: bal0,
                amount1Desired: bal1,
                amount0Min: p.minAmt0,
                amount1Min: p.minAmt1,
                deadline: block.timestamp
            });
            (liquidity, amt0, amt1) = PositionManagerLike(uniV3PositionManager).increaseLiquidity(params);
        }
        
        // Send leftover tokens back to buffer
        if(amt0 < bal0) GemLike(p.gem0).transfer(to, bal0 - amt0);
        if(amt1 < bal1) GemLike(p.gem1).transfer(to, bal1 - amt1);
    }

    function deposit(DepositParams memory p) external auth returns (uint128 liquidity, uint256 amt0, uint256 amt1) {
        p = sortDepositedTokens(p);
        (amt0, amt1) = swapBeforeDeposit(p);
        address buffer_ = buffer;
        GemLike(p.gem0).transferFrom(buffer_, address(this), amt0);
        GemLike(p.gem1).transferFrom(buffer_, address(this), amt1);
        GemLike(p.gem0).approve(uniV3PositionManager, amt0); // TODO: cheaper to SLOAD allowance to check if we need to approve max?
        GemLike(p.gem1).approve(uniV3PositionManager, amt1);
        (liquidity, amt0, amt1) = addLiquidity(p, buffer_, amt0, amt1);
        emit Deposit(msg.sender, p.gem0, p.gem1, liquidity, p.amt0, p.amt1);
    }

    struct WithdrawParams {
        address gem0;
        address gem1;
        uint128 liquidity;
        uint256 minAmt0;
        uint256 minAmt1;
        uint256 swappedAmt0;
        uint256 swappedAmt1;
        uint256 minSwappedOut;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        address swapperCallee;
        bytes swapperData;
    }

    function sortWithdrawnTokens(WithdrawParams memory p) internal pure returns (WithdrawParams memory) {
        (p.gem0, p.gem1, p.minAmt0, p.minAmt1, p.swappedAmt0, p.swappedAmt1) 
            = p.gem0 < p.gem1 ? (p.gem0, p.gem1, p.minAmt0, p.minAmt1, p.swappedAmt0, p.swappedAmt1) : (p.gem1, p.gem0, p.minAmt1, p.minAmt0, p.swappedAmt1, p.swappedAmt0);
        return p;
    }

    function swapAfterWithdraw(WithdrawParams memory p, uint256 bal0, uint256 bal1) internal returns (uint256 amt0, uint256 amt1) {
        uint256 sold;
        uint256 bought;
        if(p.swappedAmt0 > 0) {
            sold = p.swappedAmt0 > bal0 ? bal0 : p.swappedAmt0;
            bought = Swapper(swapper).swap(p.gem0, p.gem1, sold, p.minSwappedOut, p.swapperCallee, p.swapperData);
            amt0 = bal0 - sold;
            amt1 = bal1 + bought;
        } else if (p.swappedAmt1 > 0) {
            sold = p.swappedAmt1 > bal1 ? bal1 : p.swappedAmt1;
            bought = Swapper(swapper).swap(p.gem1, p.gem0, sold, p.minSwappedOut, p.swapperCallee, p.swapperData);
            amt1 = bal1 - sold;
            amt0 = bal0 + bought;
        }
    }

    function removeLiquidity(WithdrawParams memory p) internal returns (uint256 amt0, uint256 amt1) {
        bytes32 key = keccak256(abi.encode(p.gem0, p.gem1, p.fee, p.tickLower, p.tickUpper));
        uint256 tokenId = positions[key];
        require(tokenId > 0, "Depositor/no-position");
        
        PositionManagerLike.DecreaseLiquidityParams memory params = PositionManagerLike.DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: p.liquidity,
            amount0Min: p.minAmt0,
            amount1Min: p.minAmt1,
            deadline: block.timestamp
        });
        (amt0, amt1) = PositionManagerLike(uniV3PositionManager).decreaseLiquidity(params);

        PositionManagerLike.CollectParams memory collection = PositionManagerLike.CollectParams({
            tokenId: tokenId,
            recipient: address(buffer),
            amount0Max: type(uint128).max, // using max instead of amt0 so as to also collect fees
            amount1Max: type(uint128).max  // using max instead of amt1 so as to also collect fees
        });
        PositionManagerLike(uniV3PositionManager).collect(collection);
    }
        
    function withdraw(WithdrawParams memory p) external auth returns (uint256 amt0, uint256 amt1) {
        require(p.swappedAmt0 == 0 || p.swappedAmt1 == 0, "Depositor/cannot-swap-both-gems");
        p = sortWithdrawnTokens(p);
        (amt0, amt1) = removeLiquidity(p);
        (amt0, amt1) = swapAfterWithdraw(p, amt0, amt1);
        emit Withdraw(msg.sender, p.gem0, p.gem1, p.liquidity, amt0, amt1);
    }
}
