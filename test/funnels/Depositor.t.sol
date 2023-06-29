// SPDX-License-Identifier: UNLICENSED
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
    AllocatorRoles public roles;
    AllocatorBuffer public buffer;
    Depositor public depositor;
    UniV3SwapperCallee public uniV3Callee;

    bytes32 constant ilk = "aaa";

    address constant DAI           = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC          = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNIV3_POS_MGR = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant UNIV3_ROUTER  = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address constant FACILITATOR = address(0x1337);

    uint8 constant DEPOSITOR_ROLE = uint8(2);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        buffer = new AllocatorBuffer(ilk);
        roles = new AllocatorRoles();
        depositor = new Depositor(address(roles), ilk, UNIV3_POS_MGR, address(buffer));

        roles.setIlkAdmin(ilk, address(this));
        roles.setRoleAction(ilk, DEPOSITOR_ROLE, address(depositor), depositor.deposit.selector, true);
        roles.setRoleAction(ilk, DEPOSITOR_ROLE, address(depositor), depositor.withdraw.selector, true);
        roles.setRoleAction(ilk, DEPOSITOR_ROLE, address(depositor), depositor.collect.selector, true);
        roles.setUserRole(ilk, FACILITATOR, DEPOSITOR_ROLE, true);

        depositor.file("cap", DAI, USDC, uint128(10_000 * WAD), 10_000 * 10**6);
        depositor.file("hop", DAI, USDC, 3600);

        deal(DAI,  address(buffer), 1_000_000 * WAD,   true);
        deal(USDC, address(buffer), 1_000_000 * 10**6, true);
        buffer.approve(USDC, address(depositor), type(uint256).max);
        buffer.approve(DAI,  address(depositor), type(uint256).max);
        buffer.setApprovalForAll(UNIV3_POS_MGR,  address(depositor), true);
    }

    function testConstructor() public {
        Depositor d = new Depositor(address(0xBEEF), "SubDAO 1", address(0xABC), address(0xAAA));
        assertEq(address(d.roles()),  address(0xBEEF));
        assertEq(d.ilk(), "SubDAO 1");
        assertEq(d.uniV3PositionManager(), address(0xABC));
        assertEq(d.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(depositor), "Depositor");
    }

    function testModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](3);
        authedMethods[0] = depositor.deposit.selector;
        authedMethods[1] = depositor.withdraw.selector;
        authedMethods[2] = depositor.collect.selector;

        vm.startPrank(address(0xBEEF));
        checkModifierForLargeArgs(address(depositor), "Depositor/not-authorized", authedMethods);
        vm.stopPrank();
    }

    function testFile() public {
        checkFileUintForGemPair(address(depositor), "Depositor", ["hop"]);
        checkFileUint128PairForGemPair(address(depositor), "Depositor", ["cap"]);
    }

    function testRoles() public {
        vm.expectRevert("Depositor/not-authorized");
        vm.prank(address(0xBEEF)); depositor.file("hop", address(0), address(0), 0);
        roles.setRoleAction(ilk, uint8(0xF1), address(depositor), bytes4(keccak256("file(bytes32,address,address,uint256)")), true);
        roles.setUserRole(ilk, address(0xBEEF), uint8(0xF1), true);
        vm.prank(address(0xBEEF)); depositor.file("hop", address(0), address(0), 0);
    }

    function testDepositor() public {
        assertEq(GemLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 0);
        uint256 prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        uint256 prevDAI = GemLike(DAI).balanceOf(address(buffer));

        int24 refTick = -276324; // ~=  math.log(10**(-12) gem0/gem1)/math.log(1.0001)
        Depositor.DepositParams memory dp = Depositor.DepositParams({ 
            gem0: DAI,
            gem1: USDC,
            amt0: 500 * WAD, 
            amt1: 500 * 10**6, 
            minAmt0: 490 * WAD, 
            minAmt1: 490 * 10**6, 
            fee: uint24(100), 
            tickLower: refTick-100, 
            tickUpper: refTick+100
        });
        vm.prank(FACILITATOR); (uint128 liq1,,) = depositor.deposit(dp);

        assertLt(GemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertLt(GemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(GemLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);
        prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        prevDAI = GemLike(DAI).balanceOf(address(buffer));

        vm.warp(block.timestamp + 3600);
        vm.prank(FACILITATOR);  (uint128 liq2,,) = depositor.deposit(dp);

        assertLt(GemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertLt(GemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(GemLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);
        prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        prevDAI = GemLike(DAI).balanceOf(address(buffer));

        // execute a trade to generate fees for the LP position
        deal(DAI,  address(this), 1_000_000 * WAD,   true);
        GemLike(DAI).approve(UNIV3_ROUTER, 1_000_000 * WAD);
        bytes memory path = abi.encodePacked(DAI, uint24(100), USDC);
        SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
            path:             path,
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
            tickLower: refTick-100, 
            tickUpper: refTick+100
        });
        vm.prank(FACILITATOR); (uint256 amt0, uint256 amt1) = depositor.collect(cp);
        assertTrue(amt0 > 0 || amt1 > 0);

        Depositor.WithdrawParams memory wp = Depositor.WithdrawParams({ 
            gem0: DAI,
            gem1: USDC,
            liquidity: liq1 + liq2,
            minAmt0: 880 * WAD, 
            minAmt1: 880 * 10**6,
            fee: uint24(100), 
            tickLower: refTick-100, 
            tickUpper: refTick+100
        });
        vm.warp(block.timestamp + 3600);
        vm.prank(FACILITATOR); depositor.withdraw(wp);
        
        assertGt(GemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertGt(GemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(GemLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);        
    }
}
