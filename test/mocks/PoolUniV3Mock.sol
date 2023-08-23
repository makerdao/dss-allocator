// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

interface DepositorLike {
    function uniswapV3MintCallback(uint256, uint256, bytes calldata) external;
}

contract PoolUniV3Mock {
    address public gem0;
    address public gem1;
    uint24  public fee;

    uint256 public random0;
    uint256 public random1;

    function mint(address, int24, int24, uint128, bytes calldata) external returns (uint256, uint256) {
        DepositorLike(msg.sender).uniswapV3MintCallback(random0, random1, abi.encode(gem0, gem1, fee));
        
        return (random0, random1);
    }
}
