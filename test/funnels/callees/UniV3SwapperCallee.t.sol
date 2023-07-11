// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { UniV3SwapperCallee } from "src/funnels/callees/UniV3SwapperCallee.sol";

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external;
    function decimals() external view returns (uint8);
}

contract UniV3SwapperCalleeTest is DssTest {

    UniV3SwapperCallee public callee;

    address constant DAI          = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC         = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH         = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        callee = new UniV3SwapperCallee(UNIV3_ROUTER);

        deal(DAI,  address(this), 1_000_000 * WAD,   true);
        deal(USDC, address(this), 1_000_000 * 10**6, true);
    }

    function testConstructor() public {
        UniV3SwapperCallee c = new UniV3SwapperCallee(address(0xBEEF));
        assertEq(address(c.uniV3Router()),  address(0xBEEF));
    }


    function checkStableSwap(address from, address to, bytes memory path) public {
        uint256 prevFrom = GemLike(from).balanceOf(address(this));
        uint256 prevTo = GemLike(to).balanceOf(address(this));
        uint8 fromDecimals = GemLike(from).decimals();
        uint8 toDecimals = GemLike(to).decimals();

        GemLike(from).transfer(address(callee), 10_000 * 10**fromDecimals);
        callee.swap(from, to, 10_000 * 10**fromDecimals, 9900 * 10**toDecimals, address(this), path);
        
        assertEq(GemLike(from).balanceOf(address(this)), prevFrom - 10_000 * 10**fromDecimals);
        assertGe(GemLike(to).balanceOf(address(this)), prevTo + 9900 * 10**toDecimals);
        assertEq(GemLike(from).balanceOf(address(callee)), 0);
        assertEq(GemLike(to).balanceOf(address(callee)), 0);

    }

    function testSwapShortPath() public {
        bytes memory DAI_USDC_PATH = abi.encodePacked(DAI, uint24(100), USDC);
        checkStableSwap(DAI, USDC, DAI_USDC_PATH);
    }

    function testSwapLongPath() public {
        bytes memory USDC_WETH_DAI_PATH = abi.encodePacked(USDC, uint24(100), WETH, uint24(100), DAI);
        checkStableSwap(USDC, DAI, USDC_WETH_DAI_PATH);
    }

    function testSwapInvalidPath() public {
        bytes memory USDC_WETH_DAI_PATH = abi.encodePacked(USDC, uint24(100), WETH, uint24(100), DAI);

        vm.expectRevert("UniV3SwapperCallee/invalid-path");
        this.checkStableSwap(DAI, USDC, USDC_WETH_DAI_PATH);
    }

}
