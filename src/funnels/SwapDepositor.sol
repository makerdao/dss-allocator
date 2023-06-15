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
import "./Depositor.sol";

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

contract SwapDepositor {
    mapping (address => uint256) public wards;

    address public roles;                           // Contract managing access control for this SwapDepositor
    address public swapper;                         // Swapper contract
    address public depositor;                       // Depositor contract

    uint256 internal constant WAD = 10 ** 18;

    address internal immutable uniV3Factory; // 0x1F98431c8aD98523631AE4a59f267346ea31F984

    event Rely (address indexed usr);
    event Deny (address indexed usr);
    event File (bytes32 indexed what, address data);

    constructor(address _uniV3Factory) {
        uniV3Factory = _uniV3Factory;
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
        require(access || wards[msg.sender] == 1, "SwapDepositor/not-authorized");
        _;
    }

    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }

    function file(bytes32 what, address data) external auth {
        if      (what == "roles")      roles   = data;
        else if (what == "swapper")    swapper = data;
        else if (what == "depositor")  depositor = data;
        else revert("SwapDepositor/file-unrecognized-param");
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

    struct SwapDepositParams {
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

    function sortDepositedTokens(SwapDepositParams memory p) internal pure returns (SwapDepositParams memory) {
        (p.gem0, p.gem1, p.amt0, p.amt1, p.minAmt0, p.minAmt1) 
            = p.gem0 < p.gem1 ? (p.gem0, p.gem1, p.amt0, p.amt1, p.minAmt0, p.minAmt1) : (p.gem1, p.gem0, p.amt1, p.amt0, p.minAmt1, p.minAmt0);
        return p;
    }

    function getConvertedAmounts(SwapDepositParams memory p) internal view returns (uint256 amt0_1, uint256 amt1_0) {
        (uint160 sqrtPriceX96,,,,,,) = UniV3PoolLike(getPoolAddress(p.gem0, p.gem1, p.fee)).slot0();
        uint256 p0 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) * WAD / uint256(2 ** 192);
        amt0_1 = p.amt0 * p0 / WAD;
        amt1_0 = p.amt1 * WAD / p0;
    }

    function swapBeforeDeposit(SwapDepositParams memory p) internal returns (uint256 amt0, uint256 amt1) {
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


    function deposit(SwapDepositParams memory p) external auth returns (uint128 liquidity, uint256 amt0, uint256 amt1) {
        p = sortDepositedTokens(p);
        (amt0, amt1) = swapBeforeDeposit(p);
        Depositor.DepositParams memory depositParams = Depositor.DepositParams({
            gem0: p.gem0,
            gem1: p.gem1,
            amt0: amt0,
            amt1: amt1,
            minAmt0: p.minAmt0,
            minAmt1: p.minAmt1,
            fee: p.fee,
            tickLower: p.tickLower,
            tickUpper: p.tickUpper
        });
        (liquidity, amt0, amt1) = Depositor(depositor).deposit(depositParams);
    }

    struct WithdrawSwapParams {
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

    function sortWithdrawnTokens(WithdrawSwapParams memory p) internal pure returns (WithdrawSwapParams memory) {
        (p.gem0, p.gem1, p.minAmt0, p.minAmt1, p.swappedAmt0, p.swappedAmt1) 
            = p.gem0 < p.gem1 ? (p.gem0, p.gem1, p.minAmt0, p.minAmt1, p.swappedAmt0, p.swappedAmt1) : (p.gem1, p.gem0, p.minAmt1, p.minAmt0, p.swappedAmt1, p.swappedAmt0);
        return p;
    }

    function swapAfterWithdraw(WithdrawSwapParams memory p, uint256 bal0, uint256 bal1) internal returns (uint256 amt0, uint256 amt1) {
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
        
    function withdraw(WithdrawSwapParams memory p) external auth returns (uint256 amt0, uint256 amt1) {
        require(p.swappedAmt0 == 0 || p.swappedAmt1 == 0, "SwapDepositor/cannot-swap-both-gems");
        p = sortWithdrawnTokens(p);
        Depositor.WithdrawParams memory withdrawParams = Depositor.WithdrawParams({
            gem0: p.gem0,
            gem1: p.gem1,
            liquidity: p.liquidity,
            minAmt0: p.minAmt0,
            minAmt1: p.minAmt1,
            fee: p.fee,
            tickLower: p.tickLower,
            tickUpper: p.tickUpper
        });
        (amt0, amt1) = Depositor(depositor).withdraw(withdrawParams);
        (amt0, amt1) = swapAfterWithdraw(p, amt0, amt1);
    }
}
