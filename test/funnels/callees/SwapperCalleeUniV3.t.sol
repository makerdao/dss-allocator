// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { SwapperCalleeUniV3 } from "src/funnels/callees/SwapperCalleeUniV3.sol";

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external;
    function decimals() external view returns (uint8);
}

contract SwapperCalleeUniV3Test is DssTest {

    SwapperCalleeUniV3 public callee;

    address constant DAI          = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC         = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT         = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        callee = new SwapperCalleeUniV3(UNIV3_ROUTER);

        deal(DAI,  address(this), 1_000_000 * WAD,   true);
        deal(USDC, address(this), 1_000_000 * 10**6, true);
    }

    function testConstructor() public {
        SwapperCalleeUniV3 c = new SwapperCalleeUniV3(address(0xBEEF));
        assertEq(address(c.uniV3Router()),  address(0xBEEF));
    }

    function checkStableSwap(address from, address to, bytes memory path) public {
        uint256 prevFrom = GemLike(from).balanceOf(address(this));
        uint256 prevTo = GemLike(to).balanceOf(address(this));
        uint8 fromDecimals = GemLike(from).decimals();
        uint8 toDecimals = GemLike(to).decimals();

        GemLike(from).transfer(address(callee), 10_000 * 10**fromDecimals);
        callee.swapCallback(from, to, 10_000 * 10**fromDecimals, 9000 * 10**toDecimals, address(this), path);
        
        assertEq(GemLike(from).balanceOf(address(this)), prevFrom - 10_000 * 10**fromDecimals);
        assertGe(GemLike(to).balanceOf(address(this)), prevTo + 9000 * 10**toDecimals);
        assertEq(GemLike(from).balanceOf(address(callee)), 0);
        assertEq(GemLike(to).balanceOf(address(callee)), 0);
    }

    function testSwapShortPath() public {
        bytes memory DAI_USDC_PATH = abi.encodePacked(DAI, uint24(100), USDC);
        checkStableSwap(DAI, USDC, DAI_USDC_PATH);
    }

    function testSwapLongPath() public {
        bytes memory USDC_USDT_DAI_PATH = abi.encodePacked(USDC, uint24(100), USDT, uint24(100), DAI);
        checkStableSwap(USDC, DAI, USDC_USDT_DAI_PATH);
    }
}
