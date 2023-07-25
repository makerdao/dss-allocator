// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { Depositor } from "src/funnels/Depositor.sol";
import { StableDepositor } from "src/funnels/automation/StableDepositor.sol";
import { AllocatorRoles } from "src/AllocatorRoles.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external;
    function approve(address, uint256) external;
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

contract StableDepositorTest is DssTest {
    event Kiss(address indexed usr);
    event Diss(address indexed usr);
    event SetConfig(address indexed gem0, address indexed gem1, uint32 count, uint64 hop, uint24 fee, int24 tickLower, int24 tickUpper, uint128 amt0, uint128 amt1, uint128 amt0Req, uint128 amt1Req);
    
    AllocatorBuffer public buffer;
    Depositor       public depositor;
    StableDepositor public stableDepositor;

    bytes32 constant ilk = "aaa";
    bytes constant DAI_USDC_PATH = abi.encodePacked(DAI, uint24(100), USDC);

    address constant DAI           = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC          = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNIV3_ROUTER  = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address constant FACILITATOR = address(0x1337);
    address constant KEEPER      = address(0xb0b);

    uint8 constant DEPOSITOR_ROLE = uint8(1);

    int24 constant REF_TICK = -276324; // tick corresponding to 1 DAI = 1 USDC calculated as ~= math.log(10**(-12))/math.log(1.0001)

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        buffer = new AllocatorBuffer();
        AllocatorRoles roles = new AllocatorRoles();
        depositor = new Depositor(address(roles), ilk, UNIV3_FACTORY, address(buffer));
        stableDepositor = new StableDepositor(address(depositor));

        roles.setIlkAdmin(ilk, address(this));
        roles.setRoleAction(ilk, DEPOSITOR_ROLE, address(depositor), depositor.deposit.selector, true);
        roles.setRoleAction(ilk, DEPOSITOR_ROLE, address(depositor), depositor.withdraw.selector, true);
        roles.setRoleAction(ilk, DEPOSITOR_ROLE, address(depositor), depositor.collect.selector, true);
        roles.setUserRole(ilk, FACILITATOR, DEPOSITOR_ROLE, true);
        roles.setUserRole(ilk, address(stableDepositor), DEPOSITOR_ROLE, true);

        depositor.setLimits(DAI, USDC, uint128(10_000 * WAD), uint128(10_000 * 10**6), 3600 seconds);

        deal(DAI,  address(buffer), 1_000_000 * WAD,   true);
        deal(USDC, address(buffer), 1_000_000 * 10**6, true);
        buffer.approve(USDC, address(depositor), type(uint256).max);
        buffer.approve(DAI,  address(depositor), type(uint256).max);

        stableDepositor.rely(FACILITATOR);
        vm.startPrank(FACILITATOR); 
        stableDepositor.setConfig(DAI, USDC, 10, 3600, uint24(100), REF_TICK-100, REF_TICK+100, uint128(500 * WAD), uint128(500 * 10**6), uint128(490 * WAD), uint128(490 * 10**6));

        stableDepositor.kiss(KEEPER);
        vm.stopPrank();
    }

    function testConstructor() public {
        StableDepositor s = new StableDepositor(address(0xABC));
        assertEq(address(s.depositor()),  address(0xABC));
        assertEq(s.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(stableDepositor), "StableDepositor");
    }

    function testModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](3);
        authedMethods[0] = stableDepositor.kiss.selector;
        authedMethods[1] = stableDepositor.diss.selector;
        authedMethods[2] = stableDepositor.setConfig.selector;

        vm.startPrank(address(0xBEEF));
        checkModifier(address(stableDepositor), "StableDepositor/not-authorized", authedMethods);
        vm.stopPrank();
    }

    function testKissDiss() public {
        address testAddress = address(0x123);

        assertEq(stableDepositor.buds(testAddress), 0);
        vm.expectEmit(true, true, true, true);
        emit Kiss(testAddress);
        stableDepositor.kiss(testAddress);
        assertEq(stableDepositor.buds(testAddress), 1);
        vm.expectEmit(true, true, true, true);
        emit Diss(testAddress);
        stableDepositor.diss(testAddress);
        assertEq(stableDepositor.buds(testAddress), 0);
    }

    function testSetConfig() public {
        vm.expectRevert("StableDepositor/wrong-gem-order");
        stableDepositor.setConfig(address(0x456), address(0x123), 23, 3600, uint24(314), 5, 6, uint128(7), uint128(8), uint128(9), uint128(10));

        vm.expectEmit(true, true, true, true);
        emit SetConfig(address(0x123), address(0x456), 23, 3600, uint24(314), 5, 6, uint128(7), uint128(8), uint128(9), uint128(10));
        stableDepositor.setConfig(address(0x123), address(0x456), 23, 3600, uint24(314), 5, 6, uint128(7), uint128(8), uint128(9), uint128(10));

        (
            uint32  count,
            uint64  hop,
            ,
            uint24  fee,
            int24   tickLower,
            int24   tickUpper,
            uint128 amt0,
            uint128 amt1,
            uint128 amt0Req,
            uint128 amt1Req
        ) = stableDepositor.configs(address(0x123), address(0x456));
        assertEq(count    , 23);
        assertEq(hop      , 3600);
        assertEq(fee      , uint24(314));
        assertEq(tickLower, 5);
        assertEq(tickUpper, 6);
        assertEq(amt0     , uint128(7));
        assertEq(amt1     , uint128(8));
        assertEq(amt0Req  , uint128(9));
        assertEq(amt1Req  , uint128(10));
    }

    function testDepositWithdrawByKeeper() public {
        uint256 prevDai = GemLike(DAI).balanceOf(address(buffer));
        uint256 prevUsdc = GemLike(USDC).balanceOf(address(buffer));
        (uint32 prevCount,,,,,,,,,) = stableDepositor.configs(DAI, USDC);

        vm.prank(KEEPER); stableDepositor.deposit(DAI, USDC, uint128(491 * WAD), uint128(491 * 10**6));

        uint256 afterDepositDai  = GemLike(DAI).balanceOf(address(buffer));
        uint256 afterDepositUsdc = GemLike(USDC).balanceOf(address(buffer));
        (uint32 afterDepositCount,,,,,,,,,) = stableDepositor.configs(DAI, USDC);
        assertLt(afterDepositDai, prevDai);
        assertLt(afterDepositUsdc, prevUsdc);
        assertEq(afterDepositCount, prevCount - 1);

        vm.warp(block.timestamp + 3600);
        vm.prank(KEEPER); stableDepositor.withdraw(DAI, USDC, uint128(491 * WAD), uint128(491 * 10**6));
        (uint32 afterWithdrawCount,,,,,,,,,) = stableDepositor.configs(DAI, USDC);

        assertGt(GemLike(DAI).balanceOf(address(buffer)), afterDepositDai);
        assertGt(GemLike(USDC).balanceOf(address(buffer)), afterDepositUsdc);
        assertEq(afterWithdrawCount, afterDepositCount - 1);
    }

    function testDepositWithdrawMinZero() public {
        uint256 prevDai = GemLike(DAI).balanceOf(address(buffer));
        uint256 prevUsdc = GemLike(USDC).balanceOf(address(buffer));

        vm.prank(KEEPER); stableDepositor.deposit(DAI, USDC, 0, 0);

        uint256 afterDepositDai  = GemLike(DAI).balanceOf(address(buffer));
        uint256 afterDepositUsdc = GemLike(USDC).balanceOf(address(buffer));
        assertLt(afterDepositDai, prevDai);
        assertLt(afterDepositUsdc, prevUsdc);

        vm.warp(block.timestamp + 3600);
        vm.prank(KEEPER); stableDepositor.withdraw(DAI, USDC, 0, 0);

        assertGt(GemLike(DAI).balanceOf(address(buffer)), afterDepositDai);
        assertGt(GemLike(USDC).balanceOf(address(buffer)), afterDepositUsdc);
    }

    function testDepositWithdrawExceedingCount() public {
        vm.expectRevert("StableDepositor/exceeds-count");
        vm.prank(KEEPER); stableDepositor.deposit(USDC, DAI, uint128(491 * 10**6), uint128(491 * WAD));

        vm.expectRevert("StableDepositor/exceeds-count");
        vm.prank(KEEPER); stableDepositor.withdraw(USDC, DAI, uint128(491 * 10**6), uint128(491 * WAD));
    }

    function testDepositWithMin0TooSmall() public {
        (,,,,,,,, uint128 amt0Req,) = stableDepositor.configs(DAI, USDC);

        vm.expectRevert("StableDepositor/min-amt0-too-small");
        vm.prank(KEEPER); stableDepositor.deposit(DAI, USDC, amt0Req - 1, uint128(491 * 10**6));
    }

    function testDepositWithMin1TooSmall() public {
        (,,,,,,,,, uint128 amt1Req) = stableDepositor.configs(DAI, USDC);

        vm.expectRevert("StableDepositor/min-amt1-too-small");
        vm.prank(KEEPER); stableDepositor.deposit(DAI, USDC, uint128(491 * WAD), amt1Req - 1);
    }

    function testCollectByKeeper() public {
        vm.prank(KEEPER); stableDepositor.deposit(DAI, USDC, uint128(491 * WAD), uint128(491 * 10**6));

        uint256 prevDai = GemLike(DAI).balanceOf(address(buffer));
        uint256 prevUsdc = GemLike(USDC).balanceOf(address(buffer));

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

        vm.prank(KEEPER); (uint256 fees0, uint256 fees1) = stableDepositor.collect(DAI, USDC);

        assertTrue(fees0 > 0 || fees1 > 0);
        assertEq(GemLike(DAI).balanceOf(address(buffer)), prevDai + fees0);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), prevUsdc + fees1);
    }

    function testOperationsNonKeeper() public {
        assertEq(stableDepositor.buds(address(this)), 0);

        vm.expectRevert("StableDepositor/non-keeper");
        stableDepositor.deposit(DAI, USDC, uint128(491 * WAD), uint128(491 * 10**6));

        vm.expectRevert("StableDepositor/non-keeper");
        stableDepositor.withdraw(DAI, USDC, uint128(491 * WAD), uint128(491 * 10**6));

        vm.expectRevert("StableDepositor/non-keeper");
        vm.prank(address(0x123)); stableDepositor.collect(DAI, USDC);
    }
}
