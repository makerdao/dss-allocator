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

interface RolesLike {
    function canCall(bytes32, address, address, bytes4) external view returns (bool);
}

interface GemLike {
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

contract Depositor {
    mapping (address => uint256) public wards;
    mapping (address => mapping (address => uint256)) public hops;       // [seconds]   hops[gem0][gem1] is the cooldown one has to wait between changes to the liquidity of a (gem0, gem1) pool
    mapping (address => mapping (address => uint256)) public zzz;        // [seconds]    zzz[gem0][gem1] is the timestamp of the last liquidity change for a (gem0, gem1) pool
    mapping (address => mapping (address => Cap)) public caps;           // [amount]    caps[gem0][gem1] is the tuple (cap0, cap1) indicating the maximum amount of (gem0, gem1) that can be added as liquidity each hop for a (gem0, gem1) pool

    mapping (bytes32 => uint256) public positions;  // key = keccak256(abi.encode(gem0, gem1, fee, tickLower, tickUpper)) => tokenId of the liquidity position

    address public buffer;                          // Escrow contract from/to which the two tokens that make up the liquidity position are pulled/pushed

    RolesLike public immutable roles;                 // Contract managing access control for this Depositor
    bytes32   public immutable ilk;
    address internal immutable uniV3PositionManager;  // 0xC36442b4a4522E871399CD717aBDD847Ab11FE88

    struct Cap {
        uint128 cap0;
        uint128 cap1;
    }

    event Rely (address indexed usr);
    event Deny (address indexed usr);
    event File (bytes32 indexed what, address indexed gem0, address indexed gem1, uint256 data);
    event File (bytes32 indexed what, address indexed gem0, address indexed gem1, uint128 data0, uint128 data1);
    event File (bytes32 indexed what, address data);
    event Deposit(address indexed sender, address indexed gem0, address indexed gem1, uint128 liquidity, uint256 amt0, uint256 amt1);
    event Withdraw(address indexed sender, address indexed gem0, address indexed gem1, uint128 liquidity, uint256 amt0, uint256 amt1);

    constructor(address roles_, bytes32 ilk_, address _uniV3PositionManager) {
        roles = RolesLike(roles_);
        ilk = ilk_;
        uniV3PositionManager = _uniV3PositionManager;
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(roles.canCall(ilk, msg.sender, address(this), msg.sig) || wards[msg.sender] == 1, "Depositor/not-authorized");
        _;
    }

    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }

    function file(bytes32 what, address data) external auth {
        if (what == "buffer") buffer = data;
        else revert("Depositor/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, address gem0, address gem1, uint256 data) external auth {
        (gem0, gem1) = gem0 < gem1 ? (gem0, gem1) : (gem1, gem0);
        if (what == "hop") hops[gem0][gem1] = data;
        else revert("Depositor/file-unrecognized-param");
        emit File(what, gem0, gem1, data);
    }

    function file(bytes32 what, address gem0, address gem1, uint128 data0, uint128 data1) external auth {
        (gem0, gem1, data0, data1) = gem0 < gem1 ? (gem0, gem1, data0, data1) : (gem1, gem0, data1, data0);
        if (what == "cap") caps[gem0][gem1] = Cap({ cap0: data0, cap1: data1 });
        else revert("Depositor/file-unrecognized-param");
        emit File(what, gem0, gem1, data0, data1);
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

    function _addLiquidity(DepositParams memory p, address to) internal returns (uint128 liquidity, uint256 amt0, uint256 amt1) {
        bytes32 key = keccak256(abi.encode(p.gem0, p.gem1, p.fee, p.tickLower, p.tickUpper));
        uint256 tokenId = positions[key];
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
            positions[key] = tokenId;
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

        address buffer_ = buffer;
        GemLike(p.gem0).transferFrom(buffer_, address(this), p.amt0);
        GemLike(p.gem1).transferFrom(buffer_, address(this), p.amt1);
        GemLike(p.gem0).approve(uniV3PositionManager, p.amt0); // TODO: cheaper to SLOAD allowance to check if we need to approve max?
        GemLike(p.gem1).approve(uniV3PositionManager, p.amt1);

        (liquidity, amt0, amt1) = _addLiquidity(p, buffer_);
        Cap memory cap = caps[p.gem0][p.gem1];
        require(amt0 <= cap.cap0 && amt1 <= cap.cap1, "Depositor/exceeds-cap");

        // Send leftover tokens back to buffer
        if(amt0 < p.amt0) GemLike(p.gem0).transfer(buffer_, p.amt0 - amt0);
        if(amt1 < p.amt1) GemLike(p.gem1).transfer(buffer_, p.amt1 - amt1);

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
        uint256 tokenId = positions[key];
        require(tokenId > 0, "Depositor/no-position");
        
        if(p.liquidity > 0) {
            PositionManagerLike.DecreaseLiquidityParams memory params = PositionManagerLike.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: p.liquidity,
                amount0Min: p.minAmt0,
                amount1Min: p.minAmt1,
                deadline: block.timestamp
            });
            (amt0, amt1) = PositionManagerLike(uniV3PositionManager).decreaseLiquidity(params);
        }

        PositionManagerLike.CollectParams memory collection = PositionManagerLike.CollectParams({
            tokenId: tokenId,
            recipient: address(buffer),
            amount0Max: type(uint128).max, // using max instead of amt0 so as to also collect fees
            amount1Max: type(uint128).max  // using max instead of amt1 so as to also collect fees
        });
        PositionManagerLike(uniV3PositionManager).collect(collection);
    }
        
    function withdraw(WithdrawParams memory p) external auth returns (uint256 amt0, uint256 amt1) {
        require(p.gem0 < p.gem1, "Depositor/wrong-gem-order");

        require(block.timestamp >= zzz[p.gem0][p.gem1] + hops[p.gem0][p.gem1], "Depositor/too-soon");
        zzz[p.gem0][p.gem1] = block.timestamp;

        (amt0, amt1) = _removeLiquidity(p);
        Cap memory cap = caps[p.gem0][p.gem1];
        require(amt0 <= cap.cap0 && amt1 <= cap.cap1, "Depositor/exceeds-cap");

        emit Withdraw(msg.sender, p.gem0, p.gem1, p.liquidity, amt0, amt1);
    }
}
