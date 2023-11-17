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

    PsmMock psm;
    PsmMock psmUSDT;
    SwapperCalleePsm callee;
    SwapperCalleePsm calleeUSDT;

    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        psm = new PsmMock(DAI, USDC);
        callee = new SwapperCalleePsm(address(psm));
        psm.rely(address(callee));
        callee.rely(address(this));

        psmUSDT = new PsmMock(DAI, USDT);
        calleeUSDT = new SwapperCalleePsm(address(psmUSDT));
        psmUSDT.rely(address(calleeUSDT));
        calleeUSDT.rely(address(this));

        deal(DAI,  address(this), 1_000_000 * WAD,   true);
        deal(DAI,  address(psm),  1_000_000 * WAD,   true);
        deal(DAI,  address(psmUSDT),  1_000_000 * WAD,   true);
        deal(USDC, address(this), 1_000_000 * 10**6, true);
        deal(USDC, psm.pocket(),     1_000_000 * 10**6, true);
        deal(USDT, address(this), 1_000_000 * 10**6, true);
        deal(USDT, psmUSDT.pocket(),     1_000_000 * 10**6, true);
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
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

    function checkPsmSwap(SwapperCalleePsm callee_, address from, address to) public {
        uint256 prevFrom = GemLike(from).balanceOf(address(this));
        uint256 prevTo = GemLike(to).balanceOf(address(this));
        uint8 fromDecimals = GemLike(from).decimals();
        uint8 toDecimals = GemLike(to).decimals();

        GemLike(from).transfer(address(callee_), 10_000 * 10**fromDecimals);
        callee_.swapCallback(from, to, 10_000 * 10**fromDecimals, 0, address(this), "");
        
        assertEq(GemLike(from).balanceOf(address(this)), prevFrom - 10_000 * 10**fromDecimals);
        assertEq(GemLike(to  ).balanceOf(address(this)), prevTo   + 10_000 * 10**toDecimals  );
        assertEq(GemLike(from).balanceOf(address(callee_)), 0);
        assertEq(GemLike(to  ).balanceOf(address(callee_)), 0);
    }

    function testDaiToGemSwap() public {
        checkPsmSwap(callee, DAI, USDC);
        checkPsmSwap(calleeUSDT, DAI, USDT);
    }

    function testGemToDaiSwap() public {
        checkPsmSwap(callee, USDC, DAI);
        checkPsmSwap(calleeUSDT, DAI, USDT);
    }

    function testInvalidSwapAmt() public {
        uint256 amt = 10_000 * 10**18 + 10**12 - 1;
        GemLike(DAI).transfer(address(callee), amt);
        vm.expectRevert("SwapperCalleePsm/invalid-amt");
        callee.swapCallback(DAI, USDC, amt, 0, address(this), "");
    }
}
