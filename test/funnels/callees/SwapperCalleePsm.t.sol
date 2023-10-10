// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { SwapperCalleePsm } from "src/funnels/callees/SwapperCalleePsm.sol";
import { PsmMock } from "test/mocks/PsmMock.sol";

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external;
    function decimals() external view returns (uint8);
}

contract SwapperCalleePsmTest is DssTest {

    SwapperCalleePsm public callee;
    PsmMock public psm;

    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        psm = new PsmMock(DAI, USDC);
        callee = new SwapperCalleePsm(address(psm));
        psm.rely(address(callee));
        callee.rely(address(this));

        deal(DAI,  address(this), 1_000_000 * WAD,   true);
        deal(DAI,  address(psm),  1_000_000 * WAD,   true);
        deal(USDC, address(this), 1_000_000 * 10**6, true);
        deal(USDC, psm.keg(),     1_000_000 * 10**6, true);
    }

    function testConstructor() public {
        SwapperCalleePsm c = new SwapperCalleePsm(address(psm));
        assertEq(c.psm(), address(psm));
        assertEq(c.gem(), USDC);
        assertEq(c.to18ConversionFactor(),  10**12);
        assertEq(c.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(callee), "SwapperCalleePsm");
    }

    function testModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](1);
        authedMethods[0] = callee.swapCallback.selector;

        vm.startPrank(address(0xBEEF));
        checkModifier(address(callee), "SwapperCalleePsm/not-authorized", authedMethods);
        vm.stopPrank();
    }

    function checkPsmSwap(address from, address to) public {
        uint256 prevFrom = GemLike(from).balanceOf(address(this));
        uint256 prevTo = GemLike(to).balanceOf(address(this));
        uint8 fromDecimals = GemLike(from).decimals();
        uint8 toDecimals = GemLike(to).decimals();

        GemLike(from).transfer(address(callee), 10_000 * 10**fromDecimals);
        callee.swapCallback(from, to, 10_000 * 10**fromDecimals, 0, address(this), "");
        
        assertEq(GemLike(from).balanceOf(address(this)), prevFrom - 10_000 * 10**fromDecimals);
        assertEq(GemLike(to  ).balanceOf(address(this)), prevTo   + 10_000 * 10**toDecimals  );
        assertEq(GemLike(from).balanceOf(address(callee)), 0);
        assertEq(GemLike(to  ).balanceOf(address(callee)), 0);
    }

    function testDaiToGemSwap() public {
        checkPsmSwap(DAI, USDC);
    }

    function testGemToDaiSwap() public {
        checkPsmSwap(USDC, DAI);
    }
}
