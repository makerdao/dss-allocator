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

interface ApproveLike {
    function approve(address, uint256) external returns (bool);
}

// https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/SwapRlefter.sol
interface SwapRouterLike {
    function exactInput(ExactInputParams calldata params) external returns (uint256 amountOut);

    // https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/interfaces/ISwapRouter.sol#L26
    // https://docs.uniswap.org/protocol/guides/swaps/multihop-swaps#input-parameters
    struct ExactInputParams {
        bytes   path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
}

contract SwapperCalleeUniV3 {
    address public immutable uniV3Router;

    constructor(address _uniV3Router) {
        uniV3Router = _uniV3Router;
    }

    function swapCallback(address src, address /* dst */, uint256 amt, uint256 minOut, address to, bytes calldata data) external {
        ApproveLike(src).approve(uniV3Router, amt);
        SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
            path:             data,
            recipient:        to,
            deadline:         block.timestamp,
            amountIn:         amt,
            amountOutMinimum: minOut
        });
        SwapRouterLike(uniV3Router).exactInput(params);
    }
}
