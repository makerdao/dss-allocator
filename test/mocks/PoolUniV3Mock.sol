// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

interface DepositorLike {
    function uniswapV3MintCallback(uint256, uint256, bytes calldata) external;
}

interface GemLike {
    function transfer(address, uint256) external;
}

contract PoolUniV3Mock {
    address public gem0;
    address public gem1;
    uint24  public fee;

    uint128 public random0;
    uint128 public random1;
    uint128 public random2;
    uint128 public random3;

    mapping (bytes32 => Position) public positions;

    struct Position {
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    function mint(address, int24, int24, uint128, bytes calldata) external returns (uint128, uint128) {
        DepositorLike(msg.sender).uniswapV3MintCallback(random0, random1, abi.encode(gem0, gem1, fee));
        
        return (random0, random1);
    }

    function burn(int24, int24, uint128) external view returns (uint128, uint128) {
        return (random0, random1);
    }

    function collect(address recipient, int24, int24, uint128 amt0R, uint128 amt1R) external returns (uint128, uint128) {
        uint128 col0 = amt0R > random2 ? random2 : amt0R;
        uint128 col1 = amt1R > random3 ? random3 : amt1R;
        GemLike(gem0).transfer(recipient, col0);
        GemLike(gem1).transfer(recipient, col1);
        return (col0, col1);
    }
}
