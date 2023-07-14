// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { Depositor } from "src/funnels/Depositor.sol";
import { UniV3SwapperCallee } from "src/funnels/callees/UniV3SwapperCallee.sol";
import { AllocatorRoles } from "src/AllocatorRoles.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";
import { TestUtils } from "test/utils/TestUtils.sol";

interface GemLike {
    function approve(address, uint256) external;
    function balanceOf(address) external view returns (uint256);
}

interface UniV3PoolLike {
    struct PositionInfo {
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    function positions(bytes32) external view returns (PositionInfo memory);
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

contract DepositorTest is DssTest, TestUtils {
    event SetLimits(address indexed gem0, address indexed gem1, uint64 hop, uint128 cap0, uint128 cap1);
    event Deposit(address indexed sender, address indexed gem0, address indexed gem1, uint128 liquidity, uint256 amt0, uint256 amt1);
    event Withdraw(address indexed sender, address indexed gem0, address indexed gem1, uint128 liquidity, uint256 amt0, uint256 amt1, uint256 fees0, uint256 fees1);
    event Collect(address indexed sender, address indexed gem0, address indexed gem1, uint256 fees0, uint256 fees1);

    AllocatorRoles public roles;
    AllocatorBuffer public buffer;
    Depositor public depositor;

    bytes32 constant ilk = "aaa";
    bytes constant DAI_USDC_PATH = abi.encodePacked(DAI, uint24(100), USDC);

    address constant DAI           = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC          = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DAI_USDC_POOL = 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168;
    address constant UNIV3_ROUTER  = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address constant FACILITATOR    = address(0x1337);
    uint8   constant DEPOSITOR_ROLE = uint8(2);

    int24 constant REF_TICK = -276324; // tick corresponding to 1 DAI = 1 USDC calculated as ~= math.log(10**(-12))/math.log(1.0001)

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        buffer = new AllocatorBuffer();
        roles = new AllocatorRoles();
        depositor = new Depositor(address(roles), ilk, UNIV3_FACTORY, address(buffer));

        roles.setIlkAdmin(ilk, address(this));
        roles.setRoleAction(ilk, DEPOSITOR_ROLE, address(depositor), depositor.deposit.selector, true);
        roles.setRoleAction(ilk, DEPOSITOR_ROLE, address(depositor), depositor.withdraw.selector, true);
        roles.setRoleAction(ilk, DEPOSITOR_ROLE, address(depositor), depositor.collect.selector, true);
        roles.setUserRole(ilk, FACILITATOR, DEPOSITOR_ROLE, true);

        depositor.setLimits(DAI, USDC, 3600 seconds, uint128(10_000 * WAD), uint128(10_000 * 10**6));

        deal(DAI,  address(buffer), 1_000_000 * WAD,   true);
        deal(USDC, address(buffer), 1_000_000 * 10**6, true);
        buffer.approve(USDC, address(depositor), type(uint256).max);
        buffer.approve(DAI,  address(depositor), type(uint256).max);
    }

    function testConstructor() public {
        Depositor d = new Depositor(address(0xBEEF), "SubDAO 1", address(0xAAA), address(0xCCC));
        assertEq(address(d.roles()),  address(0xBEEF));
        assertEq(d.ilk(), "SubDAO 1");
        assertEq(d.uniV3Factory(), address(0xAAA));
        assertEq(d.buffer(), address(0xCCC));
        assertEq(d.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(depositor), "Depositor");
    }

    function testModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](4);
        authedMethods[0] = depositor.setLimits.selector;
        authedMethods[1] = depositor.deposit.selector;
        authedMethods[2] = depositor.withdraw.selector;
        authedMethods[3] = depositor.collect.selector;

        vm.startPrank(address(0xBEEF));
        checkModifierForLargeArgs(address(depositor), "Depositor/not-authorized", authedMethods);
        vm.stopPrank();
    }

    function testSetLimits() public {
        // deposit to make sure zzz is set
        Depositor.LiquidityParams memory dp = Depositor.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 0,
            amt0Desired: 500 * WAD,
            amt1Desired: 500 * 10**6,
            amt0Min: 490 * WAD,
            amt1Min: 490 * 10**6
        });
        vm.prank(FACILITATOR); depositor.deposit(dp);

        (, uint64 zzzBeforeSetLimit,,) = depositor.limits(DAI, USDC);
        assertEq(zzzBeforeSetLimit, block.timestamp);

        vm.warp(block.timestamp + 1 hours);

        vm.expectEmit(true, true, true, true);
        emit SetLimits(DAI, USDC, 3, 4, 5);
        vm.prank(address(this)); depositor.setLimits(DAI, USDC, 3, 4, 5);
        (uint64 hop, uint64 zzz, uint128 cap0, uint128 cap1) = depositor.limits(DAI, USDC);
        assertEq(hop, 3);
        assertEq(zzz, zzzBeforeSetLimit);
        assertEq(cap0, 4);
        assertEq(cap1, 5);
    }

    function testRoles() public {
        vm.expectRevert("Depositor/not-authorized");
        vm.prank(address(0xBEEF)); depositor.setLimits(address(0), address(1), 0, 0, 0);
        roles.setRoleAction(ilk, uint8(0xF1), address(depositor), bytes4(keccak256("setLimits(address,address,uint64,uint128,uint128)")), true);
        roles.setUserRole(ilk, address(0xBEEF), uint8(0xF1), true);
        vm.prank(address(0xBEEF)); depositor.setLimits(address(0), address(1), 0, 0, 0);
    }

    // https://github.com/Uniswap/v3-periphery/blob/464a8a49611272f7349c970e0fadb7ec1d3c1086/contracts/libraries/PoolAddress.sol#L33
    function _getPool(address gem0, address gem1, uint24 fee) internal pure returns (UniV3PoolLike pool) {
        pool = UniV3PoolLike(address(uint160(uint256(keccak256(abi.encodePacked(
                hex'ff',
                UNIV3_FACTORY,
                keccak256(abi.encode(gem0, gem1, fee)),
                bytes32(0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54) // POOL_INIT_CODE_HASH
            ))))));
    }

    function _getLiquidity(address gem0, address gem1, uint24 fee, int24 tickLower, int24 tickUpper)
        internal
        view
        returns (uint128 liquidity)
    {
        return (_getPool(gem0, gem1, fee).
            positions(keccak256(abi.encodePacked(address(depositor), tickLower, tickUpper)))).liquidity;

    }

    function testDeposit() public {
        assertEq(_getLiquidity(DAI, USDC, 100, REF_TICK-100, REF_TICK+100), 0);
        uint256 prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        uint256 prevDAI = GemLike(DAI).balanceOf(address(buffer));

        Depositor.LiquidityParams memory dp = Depositor.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 0,
            amt0Desired: 500 * WAD,
            amt1Desired: 500 * 10**6,
            amt0Min: 490 * WAD,
            amt1Min: 490 * 10**6
        });

        uint256 snapshot = vm.snapshot();
        (uint128 expectedLiquidity, uint256 expectedAmt0, uint256 expectedAmt1) = depositor.deposit(dp);
        vm.revertTo(snapshot);

        vm.expectEmit(true, true, true, true);
        emit Deposit(FACILITATOR, DAI, USDC, expectedLiquidity, expectedAmt0, expectedAmt1);
        vm.prank(FACILITATOR); depositor.deposit(dp);

        assertLt(GemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertLt(GemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        uint128 liquidityAfterDeposit = _getLiquidity(DAI, USDC, 100, REF_TICK-100, REF_TICK+100);
        assertGt(liquidityAfterDeposit, 0);
        prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        prevDAI = GemLike(DAI).balanceOf(address(buffer));

        vm.warp(block.timestamp + 3600);

        snapshot = vm.snapshot();
        vm.prank(FACILITATOR); (expectedLiquidity, expectedAmt0, expectedAmt1) = depositor.deposit(dp);
        vm.revertTo(snapshot);

        vm.expectEmit(true, true, true, true);
        emit Deposit(FACILITATOR, DAI, USDC, expectedLiquidity, expectedAmt0, expectedAmt1);
        vm.prank(FACILITATOR); depositor.deposit(dp);

        assertLt(GemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertLt(GemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertGt(_getLiquidity(DAI, USDC, 100, REF_TICK-100, REF_TICK+100), liquidityAfterDeposit);
    }

    function testCollect() public {
        Depositor.LiquidityParams memory dp = Depositor.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 0,
            amt0Desired: 500 * WAD,
            amt1Desired: 500 * 10**6,
            amt0Min: 490 * WAD,
            amt1Min: 490 * 10**6
        });
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

        Depositor.CollectParams memory cp = Depositor.CollectParams({
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
        emit Collect(FACILITATOR, DAI, USDC, expectedFees0, expectedFees1);
        vm.prank(FACILITATOR); (uint256 fees0, uint256 fees1) = depositor.collect(cp);

        assertTrue(
            (fees0 > 0 && GemLike(DAI ).balanceOf(address(buffer)) > prevDAI ) ||
            (fees1 > 0 && GemLike(USDC).balanceOf(address(buffer)) > prevUSDC)
        );
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
    }

    function testWithdrawWithNoFeeCollection() public {
        uint256 initialUSDC = GemLike(USDC).balanceOf(address(buffer));
        uint256 initialDAI = GemLike(DAI).balanceOf(address(buffer));
        Depositor.LiquidityParams memory dp = Depositor.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 0,
            amt0Desired: 500 * WAD,
            amt1Desired: 500 * 10**6,
            amt0Min: 490 * WAD,
            amt1Min: 490 * 10**6
        });
        vm.prank(FACILITATOR); (uint128 liq, uint256 deposited0, uint256 deposited1) = depositor.deposit(dp);
        assertGt(_getLiquidity(DAI, USDC, 100, REF_TICK-100, REF_TICK+100), 0);

        dp.liquidity = liq;

        vm.warp(block.timestamp + 3600);

        uint256 snapshot = vm.snapshot();
        (uint128 liquidity, uint256 withdrawn0, uint256 withdrawn1, uint256 fees0, uint256 fees1) = depositor.withdraw(dp, false);
        vm.revertTo(snapshot);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(FACILITATOR, DAI, USDC, liquidity, withdrawn0, withdrawn1, fees0, fees1);
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);
        
        assertEq(fees0, 0);
        assertEq(fees1, 0);
        assertGe(withdrawn0 + 1, deposited0);
        assertGe(withdrawn1 + 1, deposited1);
        assertGe(GemLike(DAI).balanceOf(address(buffer)) + 1, initialDAI);
        assertGe(GemLike(USDC).balanceOf(address(buffer)) + 1, initialUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(_getLiquidity(DAI, USDC, 100, REF_TICK-100, REF_TICK+100), 0);
        assertEq(fees0, 0);
        assertEq(fees1, 0);
    }

    function testWithdrawWithFeeCollection() public {
        uint256 initialUSDC = GemLike(USDC).balanceOf(address(buffer));
        uint256 initialDAI = GemLike(DAI).balanceOf(address(buffer));
        Depositor.LiquidityParams memory dp = Depositor.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 0,
            amt0Desired: 500 * WAD,
            amt1Desired: 500 * 10**6,
            amt0Min: 490 * WAD,
            amt1Min: 490 * 10**6
        });
        vm.prank(FACILITATOR); (uint128 liq, uint256 deposited0, uint256 deposited1) = depositor.deposit(dp);
        assertGt(_getLiquidity(DAI, USDC, 100, REF_TICK-100, REF_TICK+100), 0);
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

        dp.liquidity = liq;
        vm.warp(block.timestamp + 3600);

        uint256 snapshot = vm.snapshot();
        vm.prank(FACILITATOR); (, uint256 withdrawn0, uint256 withdrawn1, uint256 fees0, uint256 fees1) = depositor.withdraw(dp, true);
        vm.revertTo(snapshot);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(FACILITATOR, DAI, USDC, liq, withdrawn0, withdrawn1, fees0, fees1);
        vm.prank(FACILITATOR); depositor.withdraw(dp, true);

        assertTrue(fees0 > 0 || fees1 > 0);
        assertTrue(
            (fees0 > 0 && withdrawn0 > deposited0 && GemLike(DAI ).balanceOf(address(buffer)) > initialDAI ) ||
            (fees1 > 0 && withdrawn1 > deposited1 && GemLike(USDC).balanceOf(address(buffer)) > initialUSDC)
        );
        assertGe(GemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertGe(GemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(_getLiquidity(DAI, USDC, 100, REF_TICK-100, REF_TICK+100), 0);
    }

    function testWithdrawZeroWithFeeCollection() public {
        Depositor.LiquidityParams memory dp = Depositor.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 0,
            amt0Desired: 500 * WAD,
            amt1Desired: 500 * 10**6,
            amt0Min: 490 * WAD,
            amt1Min: 490 * 10**6
        });
        vm.prank(FACILITATOR); (uint128 liq,,) = depositor.deposit(dp);
        assertGt(_getLiquidity(DAI, USDC, 100, REF_TICK-100, REF_TICK+100), 0);
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
        vm.prank(FACILITATOR); (uint128 liq_, uint256 withdrawn0, uint256 withdrawn1, uint256 fees0, uint256 fees1) = depositor.withdraw(dp, true);
        vm.revertTo(snapshot);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(FACILITATOR, DAI, USDC, liq_, withdrawn0, withdrawn1, fees0, fees1);
        vm.prank(FACILITATOR); depositor.withdraw(dp, true);

        assertEq(liq_, 0);
        assertTrue(fees0 > 0 || fees1 > 0);
        assertEq(withdrawn0, 0);
        assertEq(withdrawn1, 0);
        assertTrue(
            (fees0 > 0 && GemLike(DAI ).balanceOf(address(buffer)) > prevDAI ) ||
            (fees1 > 0 && GemLike(USDC).balanceOf(address(buffer)) > prevUSDC)
        );
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(_getLiquidity(DAI, USDC, 100, REF_TICK-100, REF_TICK+100), liq);
    }

    function testWithdrawAmounts() public {
        Depositor.LiquidityParams memory dp = Depositor.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 0,
            amt0Desired: 500 * WAD,
            amt1Desired: 500 * 10**6,
            amt0Min: 490 * WAD,
            amt1Min: 490 * 10**6
        });
        vm.prank(FACILITATOR); (, uint256 deposited0, uint256 deposited1) = depositor.deposit(dp);
        assertGt(_getLiquidity(DAI, USDC, 100, REF_TICK-100, REF_TICK+100), 0);

        dp.liquidity = 0;
        dp.amt0Desired = deposited0;
        dp.amt1Desired = deposited1;

        uint256 liquidityBeforeWithdraw = _getLiquidity(DAI, USDC, 100, REF_TICK-100, REF_TICK+100);

        vm.warp(block.timestamp + 3600);

        uint256 snapshot = vm.snapshot();
        vm.prank(FACILITATOR); (uint128 liq_, uint256 withdrawn0, uint256 withdrawn1, uint256 fees0, uint256 fees1) = depositor.withdraw(dp, false);
        vm.revertTo(snapshot);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(FACILITATOR, DAI, USDC, liq_, withdrawn0, withdrawn1, fees0, fees1);
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);

        assertGt(liq_, 0);
        assertEq(fees0, 0);
        assertEq(fees1, 0);
        // due to liquidity from amounts calculation there is rounding dust
        assertGe(withdrawn0 * 100001 / 100000, deposited0);
        assertGe(withdrawn1 * 100001 / 100000, deposited1);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertLt(_getLiquidity(DAI, USDC, 100, REF_TICK-100, REF_TICK+100), liquidityBeforeWithdraw);
        assertEq(fees0, 0);
        assertEq(fees1, 0);
    }

    function testDepositWrongGemOrder() public {
        Depositor.LiquidityParams memory dp = Depositor.LiquidityParams({
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
        vm.expectRevert("Depositor/wrong-gem-order");
        vm.prank(FACILITATOR); depositor.deposit(dp);
    }

    function testDepositTooSoon() public {
        Depositor.LiquidityParams memory dp = Depositor.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 0,
            amt0Desired: 500 * WAD,
            amt1Desired: 500 * 10**6,
            amt0Min: 490 * WAD,
            amt1Min: 490 * 10**6
        });
        vm.prank(FACILITATOR); depositor.deposit(dp);
        vm.expectRevert("Depositor/too-soon");
        vm.prank(FACILITATOR); depositor.deposit(dp);
    }

    function testDepositExceedingCap() public {
        Depositor.LiquidityParams memory dp = Depositor.LiquidityParams({
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
        depositor.setLimits(DAI, USDC, 3600, uint128(1 * WAD), type(uint128).max);

        vm.expectRevert("Depositor/exceeds-cap");
        vm.prank(FACILITATOR); depositor.deposit(dp);

        depositor.setLimits(DAI, USDC, 3600, type(uint128).max, 1 * 10**6);

        vm.expectRevert("Depositor/exceeds-cap");
        vm.prank(FACILITATOR); depositor.deposit(dp);

        depositor.setLimits(DAI, USDC, 3600, type(uint128).max, type(uint128).max);

        vm.prank(FACILITATOR); depositor.deposit(dp);
    }

    function testDepositExceedingSlippage() public {
        Depositor.LiquidityParams memory dp = Depositor.LiquidityParams({
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

        vm.expectRevert("Depositor/exceeds-slippage");
        vm.prank(FACILITATOR); depositor.deposit(dp);

        dp.amt0Min = 0;
        dp.amt1Min = 3 * 500 * 10**6;

        vm.expectRevert("Depositor/exceeds-slippage");
        vm.prank(FACILITATOR); depositor.deposit(dp);
    }

    function testWithdrawWrongGemOrder() public {
        Depositor.LiquidityParams memory dp = Depositor.LiquidityParams({
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

        vm.expectRevert("Depositor/wrong-gem-order");
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);
    }

    function testWithdrawTooSoon() public {
        Depositor.LiquidityParams memory dp = Depositor.LiquidityParams({
            gem0: DAI,
            gem1: USDC,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100,
            liquidity: 0,
            amt0Desired: 500 * WAD,
            amt1Desired: 500 * 10**6,
            amt0Min: 490 * WAD,
            amt1Min: 490 * 10**6
        });

        vm.prank(FACILITATOR); (uint128 liq,,) = depositor.deposit(dp);
        dp.liquidity = liq;

        vm.expectRevert("Depositor/too-soon");
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);
    }

    function testWithdrawNoPosition() public {
        Depositor.LiquidityParams memory dp = Depositor.LiquidityParams({
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

    function testWithdrawExceedingCap() public {
        Depositor.LiquidityParams memory dp = Depositor.LiquidityParams({
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

        depositor.setLimits(DAI, USDC, 3600, type(uint128).max, 1 * 10**6);
        
        vm.expectRevert("Depositor/exceeds-cap");
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);

        depositor.setLimits(DAI, USDC, 3600, uint128(1 * WAD), type(uint128).max);

        vm.expectRevert("Depositor/exceeds-cap");
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);

        depositor.setLimits(DAI, USDC, 3600, type(uint128).max, type(uint128).max);

        vm.prank(FACILITATOR); depositor.withdraw(dp, false);
    }

    function testWithdrawExceedingSlippage() public {
        Depositor.LiquidityParams memory dp = Depositor.LiquidityParams({
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

        vm.expectRevert("Depositor/exceeds-slippage");
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);

        dp.amt0Min = 0;
        dp.amt1Min = 3 * 500 * 10**6;

        vm.expectRevert("Depositor/exceeds-slippage");
        vm.prank(FACILITATOR); depositor.withdraw(dp, false);
    }

    function testCollectWrongGemOrder() public {
        Depositor.CollectParams memory cp = Depositor.CollectParams({
            gem0: USDC,
            gem1: DAI,
            fee: uint24(100),
            tickLower: REF_TICK-100,
            tickUpper: REF_TICK+100
        });

        vm.expectRevert("Depositor/wrong-gem-order");
        vm.prank(FACILITATOR); depositor.collect(cp);
    }

    function testCollectNoPosition() public {
        Depositor.CollectParams memory cp = Depositor.CollectParams({
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
            amt1Owed: 2,
            data: abi.encode(Depositor.MintCallbackData({gem0: DAI, gem1: USDC, fee: 100}))
        });

        assertEq(GemLike(DAI).balanceOf(address(buffer)), initialDAI - 1);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), initialUSDC - 2);
        assertEq(GemLike(DAI).balanceOf(DAI_USDC_POOL), initialPoolDAI + 1);
        assertEq(GemLike(USDC).balanceOf(DAI_USDC_POOL), initialPoolUSDC + 2);
    }

    function testMintCallbackNotFromPool() public {
        vm.expectRevert("Depositor/sender-not-a-pool");
        depositor.uniswapV3MintCallback({
            amt0Owed: 1,
            amt1Owed: 2,
            data: abi.encode(Depositor.MintCallbackData({gem0: DAI, gem1: USDC, fee: 100}))
        });
    }
}
