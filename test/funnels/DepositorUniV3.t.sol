// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { DepositorUniV3 } from "src/funnels/DepositorUniV3.sol";
import { SwapperCalleeUniV3 } from "src/funnels/callees/SwapperCalleeUniV3.sol";
import { AllocatorRoles } from "src/AllocatorRoles.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";

import { UniV3Utils } from "test/funnels/UniV3Utils.sol";

interface GemLike {
    function approve(address, uint256) external;
    function balanceOf(address) external view returns (uint256);
}

interface SwapRouterLike {
    function exactInput(ExactInputParams calldata params) external returns (uint256 amountOut);

    struct ExactInputParams {
        bytes   path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
}

contract DepositorUniV3Test is DssTest {
    event SetLimits(address indexed gem0, address indexed gem1, uint24 indexed fee, uint96 cap0, uint96 cap1, uint32 era);
    event Deposit(address indexed sender, address indexed gem0, address indexed gem1, uint24 fee, uint128 liquidity, uint256 amt0, uint256 amt1);
    event Withdraw(address indexed sender, address indexed gem0, address indexed gem1, uint24 fee, uint128 liquidity, uint256 amt0, uint256 amt1, uint256 fees0, uint256 fees1);
    event Collect(address indexed sender, address indexed gem0, address indexed gem1, uint24 fee, uint256 fees0, uint256 fees1);

    AllocatorRoles  public roles;
    AllocatorBuffer public buffer;
    DepositorUniV3  public depositor;

    bytes32 constant ilk = "aaa";
    bytes constant DAI_USDC_PATH = abi.encodePacked(DAI, uint24(100), USDC);

    address constant DAI           = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC          = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI_USDC_POOL = 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168;
    address constant UNIV3_ROUTER  = UniV3Utils.UNIV3_ROUTER;
    address constant UNIV3_FACTORY = UniV3Utils.UNIV3_FACTORY;

    address constant FACILITATOR    = address(0x1337);
    uint8   constant DEPOSITOR_ROLE = uint8(2);

    int24 REF_TICK;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        buffer = new AllocatorBuffer();
        roles = new AllocatorRoles();
        depositor = new DepositorUniV3(address(roles), ilk, UNIV3_FACTORY, address(buffer));

        roles.setIlkAdmin(ilk, address(this));
        roles.setRoleAction(ilk, DEPOSITOR_ROLE, address(depositor), depositor.deposit.selector, true);
        roles.setRoleAction(ilk, DEPOSITOR_ROLE, address(depositor), depositor.withdraw.selector, true);
        roles.setRoleAction(ilk, DEPOSITOR_ROLE, address(depositor), depositor.collect.selector, true);
        roles.setUserRole(ilk, FACILITATOR, DEPOSITOR_ROLE, true);

        depositor.setLimits(DAI, USDC, 100, uint96(10_000 * WAD), uint96(10_000 * 10**6), 3600 seconds);

        deal(DAI,  address(buffer), 1_000_000 * WAD,   true);
        deal(USDC, address(buffer), 1_000_000 * 10**6, true);
        buffer.approve(USDC, address(depositor), type(uint256).max);
        buffer.approve(DAI,  address(depositor), type(uint256).max);

        REF_TICK = UniV3Utils.getCurrentTick(DAI, USDC, uint24(100));
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        DepositorUniV3 d = new DepositorUniV3(address(0xBEEF), "SubDAO 1", address(0xAAA), address(0xCCC));
        assertEq(address(d.roles()),  address(0xBEEF));
        assertEq(d.ilk(), "SubDAO 1");
        assertEq(d.uniV3Factory(), address(0xAAA));
        assertEq(d.buffer(), address(0xCCC));
        assertEq(d.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(depositor), "DepositorUniV3");
    }

    function testModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](4);
        authedMethods[0] = depositor.setLimits.selector;
        authedMethods[1] = depositor.deposit.selector;
        authedMethods[2] = depositor.withdraw.selector;
        authedMethods[3] = depositor.collect.selector;

        vm.startPrank(address(0xBEEF));
        checkModifier(address(depositor), "DepositorUniV3/not-authorized", authedMethods);
        vm.stopPrank();
    }

    function testSetLimits() public {
        // deposit to make sure end and both due are set
        DepositorUniV3.LiquidityParams memory dp = _getTestDepositParams(0, 500 * WAD, 500 * 10**6);
        vm.prank(FACILITATOR); depositor.deposit(dp);

        (,,, uint96 due0Before, uint96 due1Before, uint32 endBefore) = depositor.limits(DAI, USDC, 100);
        assertGt(due0Before, 0);
        assertGt(due1Before, 0);
        assertGt(endBefore, 0);

        vm.warp(block.timestamp + 1 hours);

        vm.expectEmit(true, true, true, true);
        emit SetLimits(DAI, USDC, 100, 3, 4, 5);
        vm.prank(address(this)); depositor.setLimits(DAI, USDC, 100, 3, 4, 5);
        (uint96 cap0, uint96 cap1, uint32 era, uint96 due0, uint96 due1, uint32 end) = depositor.limits(DAI, USDC, 100);
        assertEq(cap0, 3);
        assertEq(cap1, 4);
        assertEq(era,  5);
        assertEq(due0, 0);
        assertEq(due1, 0);
        assertEq(end,  0);
    }

    function testRoles() public {
        vm.expectRevert("DepositorUniV3/not-authorized");
        vm.prank(address(0xBEEF)); depositor.setLimits(address(0), address(1), 0, 0, 0, 0);
        roles.setRoleAction(ilk, uint8(0xF1), address(depositor), depositor.setLimits.selector, true);
        roles.setUserRole(ilk, address(0xBEEF), uint8(0xF1), true);
        vm.prank(address(0xBEEF)); depositor.setLimits(address(0), address(1), 0, 0, 0, 0);
    }

    // helps avoid stack too deep errors
    function _getTestDepositParams(uint128 liquidity, uint256 amt0Desired, uint256 amt1Desired) internal view returns (DepositorUniV3.LiquidityParams memory dp) {
        (uint256 expectedAmt0, uint256 expectedAmt1) = UniV3Utils.getExpectedAmounts(DAI, USDC, uint24(100), REF_TICK-100, REF_TICK+100, liquidity, amt0Desired, amt1Desired, false);
        dp = DepositorUniV3.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: liquidity,
            amt0Desired: amt0Desired,
            amt1Desired: amt1Desired,
            amt0Min: expectedAmt0,
            amt1Min: expectedAmt1
        });
    }

    function _getTestWithdrawParams(uint128 liquidity, uint256 amt0Desired, uint256 amt1Desired) internal view returns (DepositorUniV3.LiquidityParams memory dp) {
        (uint256 expectedAmt0, uint256 expectedAmt1) = UniV3Utils.getExpectedAmounts(DAI, USDC, uint24(100), REF_TICK-100, REF_TICK+100, liquidity, amt0Desired, amt1Desired, true);
        dp = DepositorUniV3.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: liquidity,
            amt0Desired: amt0Desired,
            amt1Desired: amt1Desired,
            amt0Min: expectedAmt0,
            amt1Min: expectedAmt1
        });
    }

    function testDeposit() public {
        assertEq(UniV3Utils.getLiquidity(address(depositor), DAI, USDC, 100, REF_TICK-100, REF_TICK+100), 0);
        uint256 prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        uint256 prevDAI = GemLike(DAI).balanceOf(address(buffer));
        uint32 initialTime = uint32(block.timestamp);

        DepositorUniV3.LiquidityParams memory dp = _getTestDepositParams(0, 5_000 * WAD, 5_000 * 10**6);

        uint256 snapshot = vm.snapshot();
        (uint128 liq, uint256 amt0, uint256 amt1) = depositor.deposit(dp);
        vm.revertTo(snapshot);

        vm.expectEmit(true, true, true, true);
        emit Deposit(FACILITATOR, DAI, USDC, uint24(100), liq, amt0, amt1);
        vm.prank(FACILITATOR); depositor.deposit(dp);

        assertLt(GemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertLt(GemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        uint128 liquidityAfterDeposit = UniV3Utils.getLiquidity(address(depositor), DAI, USDC, 100, REF_TICK-100, REF_TICK+100);
        assertGt(liquidityAfterDeposit, 0);
        (,,, uint96 due0, uint96 due1, uint32 end) = depositor.limits(DAI, USDC, 100);
        assertEq(end, initialTime + 3600);
        assertEq(due0, 10_000 * WAD - amt0);
        assertEq(due1, 10_000 * 10**6 - amt1);

        prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        prevDAI = GemLike(DAI).balanceOf(address(buffer));

        dp = _getTestDepositParams(0, 2_000 * WAD, 2_000 * 10**6);

        vm.warp(initialTime + 1800);
        vm.prank(FACILITATOR); depositor.deposit(dp);

        (,,, due0, due1, end) = depositor.limits(DAI, USDC, 100);
        assertEq(end, initialTime + 3600);
        assertLt(GemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertLt(GemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertGt(UniV3Utils.getLiquidity(address(depositor), DAI, USDC, 100, REF_TICK-100, REF_TICK+100), liquidityAfterDeposit);
        assertLt(due0, 10_000 * WAD - amt0);
        assertLt(due1, 10_000 * 10**6 - amt1);

        dp = _getTestDepositParams(0, 8_000 * WAD, 8_000 * 10**6);

        vm.expectRevert("DepositorUniV3/exceeds-due-amt");
        vm.prank(FACILITATOR); depositor.deposit(dp);

        vm.warp(initialTime + 3600);
        vm.prank(FACILITATOR); (, amt0, amt1) = depositor.deposit(dp);

        (,,, due0, due1, end) = depositor.limits(DAI, USDC, 100);
        assertEq(end, initialTime + 7200);
        assertEq(due0, 10_000 * WAD - amt0);
        assertEq(due1, 10_000 * 10**6 - amt1);
    }

    function testGetPosition() public {
        // initially the position doesn't exist
        (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = depositor.getPosition(DAI, USDC, 100, REF_TICK-100, REF_TICK+100);
        assertEq(liquidity, 0);
        assertEq(feeGrowthInside0LastX128, 0);
        assertEq(feeGrowthInside1LastX128, 0);
        assertEq(tokensOwed0, 0);
        assertEq(tokensOwed1, 0);

        // deposit
        DepositorUniV3.LiquidityParams memory dp = DepositorUniV3.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 99777667447878834,
            amt0Desired: 0,
            amt1Desired: 0,
            amt0Min: 0,
            amt1Min: 0
        });
        vm.prank(FACILITATOR); depositor.deposit(dp);

        (
            liquidity,
            feeGrowthInside0LastX128,
            feeGrowthInside1LastX128,
            tokensOwed0,
            tokensOwed1
        ) = depositor.getPosition(DAI, USDC, 100, REF_TICK-100, REF_TICK+100);
        assertEq(liquidity, 99777667447878834);
        assertGe(feeGrowthInside0LastX128, 0); // initial value now that the position is created
        assertGe(feeGrowthInside1LastX128, 0); // initial value now that the position is created
        assertEq(tokensOwed0, 0);
        assertEq(tokensOwed1, 0);

        // execute a trade to generate fees for the LP position
        deal(DAI,  address(this), 1_000_000 * WAD,   true);
        GemLike(DAI).approve(UNIV3_ROUTER, 1_000_000 * WAD);
            SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
            path:             DAI_USDC_PATH,
            recipient:        address(this),
            deadline:         block.timestamp,
            amountIn:         1_000_000 * WAD,
            amountOutMinimum: 990_000 * 10**6
        });
        SwapRouterLike(UNIV3_ROUTER).exactInput(params);

        // withdraw without collecting fees
        vm.warp(block.timestamp + 3600);
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);

        uint256 updatedfeeGrowthInside0LastX128;
        uint256 updatedfeeGrowthInside1LastX128;
        (
            liquidity,
            updatedfeeGrowthInside0LastX128,
            updatedfeeGrowthInside1LastX128,
            tokensOwed0,
            tokensOwed1
        ) = depositor.getPosition(DAI, USDC, 100, REF_TICK-100, REF_TICK+100);
        assertEq(liquidity, 0);
        assertTrue(updatedfeeGrowthInside0LastX128 > feeGrowthInside0LastX128 || updatedfeeGrowthInside1LastX128 > feeGrowthInside1LastX128);
        assertTrue(tokensOwed0 > 0 || tokensOwed1 > 0);
    }

    function testCollect() public {
    
        DepositorUniV3.LiquidityParams memory dp = _getTestDepositParams(0, 500 * WAD, 500 * 10**6);
        vm.prank(FACILITATOR); depositor.deposit(dp);
        uint256 prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        uint256 prevDAI = GemLike(DAI).balanceOf(address(buffer));

        // execute a trade to generate fees for the LP position
        deal(DAI,  address(this), 1_000_000 * WAD,   true);
        GemLike(DAI).approve(UNIV3_ROUTER, 1_000_000 * WAD);
        SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
            path:             DAI_USDC_PATH,
            recipient:        address(this),
            deadline:         block.timestamp,
            amountIn:         1_000_000 * WAD,
            amountOutMinimum: 990_000 * 10**6
        });
        SwapRouterLike(UNIV3_ROUTER).exactInput(params);

        DepositorUniV3.CollectParams memory cp = DepositorUniV3.CollectParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100), 
            tickLower: REF_TICK-100, 
            tickUpper: REF_TICK+100
        });

        uint256 snapshot = vm.snapshot();
        (uint256 expectedFees0, uint256 expectedFees1) = depositor.collect(cp);
        vm.revertTo(snapshot);

        vm.expectEmit(true, true, true, true);
        emit Collect(FACILITATOR, DAI, USDC, uint24(100), expectedFees0, expectedFees1);
        vm.prank(FACILITATOR); (uint256 fees0, uint256 fees1) = depositor.collect(cp);

        assertTrue(fees0 > 0 || fees1 > 0);
        assertEq(GemLike(DAI).balanceOf(address(buffer)), prevDAI + fees0);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), prevUSDC + fees1);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
    }

    function testWithdrawWithNoFeeCollection() public {
        uint256 initialUSDC = GemLike(USDC).balanceOf(address(buffer));
        uint256 initialDAI = GemLike(DAI).balanceOf(address(buffer));
        uint256 initialTime = uint32(block.timestamp);

        DepositorUniV3.LiquidityParams memory dp = _getTestDepositParams(0, 500 * WAD, 500 * 10**6);
        vm.prank(FACILITATOR); (uint128 liq, uint256 deposited0, uint256 deposited1) = depositor.deposit(dp);
        assertGt(UniV3Utils.getLiquidity(address(depositor), DAI, USDC, 100, REF_TICK-100, REF_TICK+100), 0);

        dp = _getTestWithdrawParams(liq, 0, 0);

        uint256 snapshot = vm.snapshot();
        (uint128 liquidity, uint256 withdrawn0, uint256 withdrawn1, uint256 fees0, uint256 fees1) = depositor.withdraw(dp, false);
        vm.revertTo(snapshot);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(FACILITATOR, DAI, USDC, uint24(100), liquidity, withdrawn0, withdrawn1, fees0, fees1);
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);
        
        assertGe(withdrawn0 + 1, deposited0);
        assertGe(withdrawn1 + 1, deposited1);
        assertGe(GemLike(DAI).balanceOf(address(buffer)) + 1, initialDAI);
        assertGe(GemLike(USDC).balanceOf(address(buffer)) + 1, initialUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(UniV3Utils.getLiquidity(address(depositor), DAI, USDC, 100, REF_TICK-100, REF_TICK+100), 0);
        assertEq(fees0, 0);
        assertEq(fees1, 0);
        assertEq(liquidity, liq);
        (,,, uint96 due0, uint96 due1, uint32 end) = depositor.limits(DAI, USDC, 100);
        assertEq(end, initialTime + 3600);
        assertEq(due0, 10_000 * WAD - deposited0 - withdrawn0);
        assertEq(due1, 10_000 * 10**6 - deposited1 - withdrawn1);

        dp = _getTestDepositParams(0, 8_000 * WAD, 8_000 * 10**6);

        vm.warp(initialTime + 1800);
        vm.prank(FACILITATOR); (liq,,) = depositor.deposit(dp);

        (,,, due0, due1, end) = depositor.limits(DAI, USDC, 100);
        assertEq(end, initialTime + 3600);
        assertLt(due0, 10_000 * WAD - deposited0 - withdrawn0);
        assertLt(due1, 10_000 * 10**6 - deposited1 - withdrawn1);

        dp = _getTestWithdrawParams(liq, 0, 0);

        vm.expectRevert("DepositorUniV3/exceeds-due-amt");
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);

        vm.warp(initialTime + 3600);
        vm.prank(FACILITATOR); (, withdrawn0, withdrawn1,,) = depositor.withdraw(dp, false);

        (,,, due0, due1, end) = depositor.limits(DAI, USDC, 100);
        assertEq(end, initialTime + 7200);
        assertEq(due0, 10_000 * WAD - withdrawn0);
        assertEq(due1, 10_000 * 10**6 - withdrawn1);
    }

    function testWithdrawWithFeeCollection() public {
        DepositorUniV3.LiquidityParams memory dp = _getTestDepositParams(0, 500 * WAD, 500 * 10**6);
        vm.prank(FACILITATOR); (uint128 liq,,) = depositor.deposit(dp);
        assertGt(UniV3Utils.getLiquidity(address(depositor), DAI, USDC, 100, REF_TICK-100, REF_TICK+100), 0);
        uint256 prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        uint256 prevDAI = GemLike(DAI).balanceOf(address(buffer));

        // execute a trade to generate fees for the LP position
        deal(DAI,  address(this), 1_000_000 * WAD,   true);
        GemLike(DAI).approve(UNIV3_ROUTER, 1_000_000 * WAD);
        SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
            path:             DAI_USDC_PATH,
            recipient:        address(this),
            deadline:         block.timestamp,
            amountIn:         1_000_000 * WAD,
            amountOutMinimum: 990_000 * 10**6
        });
        SwapRouterLike(UNIV3_ROUTER).exactInput(params);

        dp = _getTestWithdrawParams(liq, 0, 0);
        vm.warp(block.timestamp + 3600);

        uint256 snapshot = vm.snapshot();
        vm.prank(FACILITATOR); (uint128 liquidity, uint256 withdrawn0, uint256 withdrawn1, uint256 fees0, uint256 fees1) = depositor.withdraw(dp, true);
        vm.revertTo(snapshot);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(FACILITATOR, DAI, USDC, uint24(100), liquidity, withdrawn0, withdrawn1, fees0, fees1);
        vm.prank(FACILITATOR); depositor.withdraw(dp, true);

        assertTrue(fees0 > 0 || fees1 > 0);
        assertTrue(withdrawn0 > 0 || withdrawn1 > 0);
        assertEq(GemLike(DAI).balanceOf(address(buffer)), prevDAI + withdrawn0 + fees0);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), prevUSDC + withdrawn1 + fees1);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(UniV3Utils.getLiquidity(address(depositor), DAI, USDC, 100, REF_TICK-100, REF_TICK+100), 0);
        assertEq(liquidity, liq);
    }

    function testWithdrawZeroWithFeeCollection() public {
        DepositorUniV3.LiquidityParams memory dp = _getTestDepositParams(0, 500 * WAD, 500 * 10**6);
        vm.prank(FACILITATOR); (uint128 liq,,) = depositor.deposit(dp);
        assertGt(UniV3Utils.getLiquidity(address(depositor), DAI, USDC, 100, REF_TICK-100, REF_TICK+100), 0);
        uint256 prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        uint256 prevDAI = GemLike(DAI).balanceOf(address(buffer));

        // execute a trade to generate fees for the LP position
        deal(DAI,  address(this), 1_000_000 * WAD,   true);
        GemLike(DAI).approve(UNIV3_ROUTER, 1_000_000 * WAD);
        SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
            path:             DAI_USDC_PATH,
            recipient:        address(this),
            deadline:         block.timestamp,
            amountIn:         1_000_000 * WAD,
            amountOutMinimum: 990_000 * 10**6
        });
        SwapRouterLike(UNIV3_ROUTER).exactInput(params);

        dp.amt0Desired = 0;
        dp.amt1Desired = 0;
        dp.amt0Min = 0;
        dp.amt1Min = 0;
        vm.warp(block.timestamp + 3600);

        uint256 snapshot = vm.snapshot();
        vm.prank(FACILITATOR); (uint128 liquidity, uint256 withdrawn0, uint256 withdrawn1, uint256 fees0, uint256 fees1) = depositor.withdraw(dp, true);
        vm.revertTo(snapshot);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(FACILITATOR, DAI, USDC, uint24(100), liquidity, withdrawn0, withdrawn1, fees0, fees1);
        vm.prank(FACILITATOR); depositor.withdraw(dp, true);

        assertEq(liquidity, 0);
        assertEq(withdrawn0, 0);
        assertEq(withdrawn1, 0);
        assertTrue(fees0 > 0 || fees1 > 0);
        assertEq(GemLike(DAI).balanceOf(address(buffer)), prevDAI + fees0);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), prevUSDC + fees1);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(UniV3Utils.getLiquidity(address(depositor), DAI, USDC, 100, REF_TICK-100, REF_TICK+100), liq);
    }

    function testWithdrawAmounts() public {
        DepositorUniV3.LiquidityParams memory dp = _getTestDepositParams(0, 500 * WAD, 500 * 10**6);
        vm.prank(FACILITATOR); (, uint256 deposited0, uint256 deposited1) = depositor.deposit(dp);
        assertGt(UniV3Utils.getLiquidity(address(depositor), DAI, USDC, 100, REF_TICK-100, REF_TICK+100), 0);

        dp = _getTestWithdrawParams(0, deposited0, deposited1);

        uint256 liquidityBeforeWithdraw = UniV3Utils.getLiquidity(address(depositor), DAI, USDC, 100, REF_TICK-100, REF_TICK+100);

        vm.warp(block.timestamp + 3600);

        uint256 snapshot = vm.snapshot();
        vm.prank(FACILITATOR); (uint128 liquidity, uint256 withdrawn0, uint256 withdrawn1, uint256 fees0, uint256 fees1) = depositor.withdraw(dp, true);
        vm.revertTo(snapshot);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(FACILITATOR, DAI, USDC, uint24(100), liquidity, withdrawn0, withdrawn1, fees0, fees1);
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);

        // due to liquidity from amounts calculation there is rounding dust
        assertGe(withdrawn0 * 100001 / 100000, deposited0);
        assertGe(withdrawn1 * 100001 / 100000, deposited1);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertLt(UniV3Utils.getLiquidity(address(depositor), DAI, USDC, 100, REF_TICK-100, REF_TICK+100), liquidityBeforeWithdraw);
        assertEq(fees0, 0);
        assertEq(fees1, 0);
        assertGt(liquidity, 0);
    }

    function testDepositWrongGemOrder() public {
        DepositorUniV3.LiquidityParams memory dp = DepositorUniV3.LiquidityParams({
            gem0: USDC,
            gem1: DAI,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 0,
            amt0Desired: 0,
            amt1Desired: 0,
            amt0Min: 0,
            amt1Min: 0
        });
        vm.expectRevert("DepositorUniV3/wrong-gem-order");
        vm.prank(FACILITATOR); depositor.deposit(dp);
    }

    function testDepositExceedingAmt() public {
        DepositorUniV3.LiquidityParams memory dp = DepositorUniV3.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 0,
            amt0Desired: 2 * uint128(1 * WAD),
            amt1Desired: 2 * uint128(1 * 10**6),
            amt0Min: 0,
            amt1Min: 0
        });
        depositor.setLimits(DAI, USDC, 100, uint96(1 * WAD), type(uint96).max, 3600);

        vm.expectRevert("DepositorUniV3/exceeds-due-amt");
        vm.prank(FACILITATOR); depositor.deposit(dp);

        depositor.setLimits(DAI, USDC, 100, type(uint96).max, 1 * 10**6, 3600);

        vm.expectRevert("DepositorUniV3/exceeds-due-amt");
        vm.prank(FACILITATOR); depositor.deposit(dp);

        depositor.setLimits(DAI, USDC, 100, type(uint96).max, type(uint96).max, 3600);

        vm.prank(FACILITATOR); depositor.deposit(dp);
    }

    function testDepositExceedingSlippage() public {
        DepositorUniV3.LiquidityParams memory dp = DepositorUniV3.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 0,
            amt0Desired: 500 * WAD,
            amt1Desired: 500 * 10**6,
            amt0Min: 3 * 500 * WAD,
            amt1Min: 0
        });

        vm.expectRevert("DepositorUniV3/exceeds-slippage");
        vm.prank(FACILITATOR); depositor.deposit(dp);

        dp.amt0Min = 0;
        dp.amt1Min = 3 * 500 * 10**6;

        vm.expectRevert("DepositorUniV3/exceeds-slippage");
        vm.prank(FACILITATOR); depositor.deposit(dp);
    }

    function testWithdrawWrongGemOrder() public {
        DepositorUniV3.LiquidityParams memory dp = DepositorUniV3.LiquidityParams({
            gem0: USDC,
            gem1: DAI,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 0,
            amt0Desired: 0,
            amt1Desired: 0,
            amt0Min: 0,
            amt1Min: 0
        });

        vm.expectRevert("DepositorUniV3/wrong-gem-order");
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);
    }

    function testWithdrawNoPosition() public {
        DepositorUniV3.LiquidityParams memory dp = DepositorUniV3.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 1,
            amt0Desired: 0,
            amt1Desired: 0,
            amt0Min: 0,
            amt1Min: 0
        });

        // "Liquidity Sub" error - https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/libraries/LiquidityMath.sol#L12
        vm.expectRevert(bytes("LS"));
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);
    }

    function testWithdrawExceedingAmt() public {
        DepositorUniV3.LiquidityParams memory dp = DepositorUniV3.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 0,
            amt0Desired: 2 * WAD,
            amt1Desired: 2 * 10**6,
            amt0Min: 0,
            amt1Min: 0
        });
        vm.prank(FACILITATOR); (uint128 liq,,) = depositor.deposit(dp);
        dp.liquidity = liq;
        vm.warp(block.timestamp + 3600);

        depositor.setLimits(DAI, USDC, 100, type(uint96).max, 1 * 10**6, 3600);
        
        vm.expectRevert("DepositorUniV3/exceeds-due-amt");
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);

        depositor.setLimits(DAI, USDC, 100, uint96(1 * WAD), type(uint96).max, 3600);

        vm.expectRevert("DepositorUniV3/exceeds-due-amt");
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);

        depositor.setLimits(DAI, USDC, 100, type(uint96).max, type(uint96).max, 3600);

        vm.prank(FACILITATOR); depositor.withdraw(dp, false);
    }

    function testWithdrawExceedingSlippage() public {
        DepositorUniV3.LiquidityParams memory dp = DepositorUniV3.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 0,
            amt0Desired: 500 * WAD,
            amt1Desired: 500 * 10**6,
            amt0Min: 0,
            amt1Min: 0
        });
        vm.prank(FACILITATOR); (uint128 liq,,) = depositor.deposit(dp);
        dp.liquidity = liq;
        vm.warp(block.timestamp + 3600);
        dp.amt0Min =  3 * 500 * WAD;

        vm.expectRevert("DepositorUniV3/exceeds-slippage");
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);

        dp.amt0Min = 0;
        dp.amt1Min = 3 * 500 * 10**6;

        vm.expectRevert("DepositorUniV3/exceeds-slippage");
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);
    }

    function testCollectWrongGemOrder() public {
        DepositorUniV3.CollectParams memory cp = DepositorUniV3.CollectParams({
            gem0: USDC,
            gem1: DAI,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100
        });

        vm.expectRevert("DepositorUniV3/wrong-gem-order");
        vm.prank(FACILITATOR); depositor.collect(cp);
    }

    function testCollectNoPosition() public {
        DepositorUniV3.CollectParams memory cp = DepositorUniV3.CollectParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100
        });

        // 0 liquidity position - https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/libraries/Position.sol#L54
        vm.expectRevert(bytes("NP"));
        vm.prank(FACILITATOR); depositor.collect(cp);
    }

    function testMintCallback() public {
        uint256 initialDAI      = GemLike(DAI).balanceOf(address(buffer));
        uint256 initialPoolDAI  = GemLike(DAI).balanceOf(DAI_USDC_POOL);
        uint256 initialUSDC     = GemLike(USDC).balanceOf(address(buffer));
        uint256 initialPoolUSDC = GemLike(USDC).balanceOf(DAI_USDC_POOL);

        vm.prank(DAI_USDC_POOL);
            depositor.uniswapV3MintCallback({
            amt0Owed: 1,
            amt1Owed: 0,
            data: abi.encode(DepositorUniV3.MintCallbackData({gem0: DAI, gem1: USDC, fee: 100}))
        });

        assertEq(GemLike(DAI).balanceOf(address(buffer)), initialDAI - 1);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), initialUSDC);
        assertEq(GemLike(DAI).balanceOf(DAI_USDC_POOL), initialPoolDAI + 1);
        assertEq(GemLike(USDC).balanceOf(DAI_USDC_POOL), initialPoolUSDC);

        vm.prank(DAI_USDC_POOL);
            depositor.uniswapV3MintCallback({
            amt0Owed: 0,
            amt1Owed: 2,
            data: abi.encode(DepositorUniV3.MintCallbackData({gem0: DAI, gem1: USDC, fee: 100}))
        });

        assertEq(GemLike(DAI).balanceOf(address(buffer)), initialDAI - 1);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), initialUSDC - 2);
        assertEq(GemLike(DAI).balanceOf(DAI_USDC_POOL), initialPoolDAI + 1);
        assertEq(GemLike(USDC).balanceOf(DAI_USDC_POOL), initialPoolUSDC + 2);

        vm.prank(DAI_USDC_POOL);
            depositor.uniswapV3MintCallback({
            amt0Owed: 10,
            amt1Owed: 20,
            data: abi.encode(DepositorUniV3.MintCallbackData({gem0: DAI, gem1: USDC, fee: 100}))
        });

        assertEq(GemLike(DAI).balanceOf(address(buffer)), initialDAI - 11);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), initialUSDC - 22);
        assertEq(GemLike(DAI).balanceOf(DAI_USDC_POOL), initialPoolDAI + 11);
        assertEq(GemLike(USDC).balanceOf(DAI_USDC_POOL), initialPoolUSDC + 22);
    }

    function testMintCallbackNotFromPool() public {
        vm.expectRevert("DepositorUniV3/sender-not-a-pool");
        depositor.uniswapV3MintCallback({
            amt0Owed: 1,
            amt1Owed: 2,
            data: abi.encode(DepositorUniV3.MintCallbackData({gem0: DAI, gem1: USDC, fee: 100}))
        });
    }
}
