// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { SwapDepositor } from "src/funnels/SwapDepositor.sol";
import { Swapper } from "src/funnels/Swapper.sol";
import { Depositor } from "src/funnels/Depositor.sol";
import { UniV3SwapperCallee } from "src/funnels/UniV3SwapperCallee.sol";
import { AllocatorRoles } from "src/AllocatorRoles.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";

interface TestGemLike {
    function balanceOf(address) external view returns (uint256);
}

contract SwapDepositorTest is DssTest {
    AllocatorBuffer public buffer;
    Swapper public swapper;
    Depositor public depositor;
    SwapDepositor public swapDepositor;
    UniV3SwapperCallee public uniV3Callee;

    bytes32 constant ilk = "aaa";

    address constant DAI           = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC          = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNIV3_ROUTER  = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNIV3_POS_MGR = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address constant FACILITATOR = address(0x1337);

    uint8 constant SWAPPER_ROLE = uint8(1);
    uint8 constant DEPOSITOR_ROLE = uint8(2);
    uint8 constant SWAP_DEPOSITOR_ROLE = uint8(3);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        buffer = new AllocatorBuffer(ilk);
        AllocatorRoles roles = new AllocatorRoles();
        swapper = new Swapper(address(roles), ilk);
        depositor = new Depositor(address(roles), ilk, UNIV3_POS_MGR);
        swapDepositor = new SwapDepositor(address(roles), ilk, UNIV3_FACTORY);
        uniV3Callee = new UniV3SwapperCallee(UNIV3_ROUTER);

        roles.setIlkAdmin(ilk, address(this));
        roles.setRoleAction(ilk, SWAPPER_ROLE, address(swapper), swapper.swap.selector, true);
        roles.setRoleAction(ilk, DEPOSITOR_ROLE, address(depositor), depositor.deposit.selector, true);
        roles.setRoleAction(ilk, DEPOSITOR_ROLE, address(depositor), depositor.withdraw.selector, true);
        roles.setRoleAction(ilk, SWAP_DEPOSITOR_ROLE, address(swapDepositor), swapDepositor.deposit.selector, true);
        roles.setRoleAction(ilk, SWAP_DEPOSITOR_ROLE, address(swapDepositor), swapDepositor.withdraw.selector, true);
        roles.setUserRole(ilk, address(swapDepositor), SWAPPER_ROLE, true);
        roles.setUserRole(ilk, address(swapDepositor), DEPOSITOR_ROLE, true);
        roles.setUserRole(ilk, FACILITATOR, SWAP_DEPOSITOR_ROLE, true);

        swapper.file("buffer", address(buffer));
        swapper.file("maxSrcAmt", DAI, USDC, 10_000 * WAD);
        swapper.file("maxSrcAmt", USDC, DAI, 10_000 * 10**6);
        swapper.file("hop", DAI, USDC, 3600);
        swapper.file("hop", USDC, DAI, 3600);

        depositor.file("buffer", address(buffer));
        depositor.file("cap", DAI, USDC, 10_000 * WAD * 10_000 * 10**6);
        depositor.file("hop", DAI, USDC, 3600);

        swapDepositor.file("swapper", address(swapper));
        swapDepositor.file("depositor", address(depositor));
        swapDepositor.file("gap", DAI, 10 * WAD);
        swapDepositor.file("gap", USDC, 10 * 10**6);

        deal(DAI,  address(buffer), 1_000_000 * WAD,   true);
        deal(USDC, address(buffer), 1_000_000 * 10**6, true);
        buffer.approve(USDC, address(swapper), type(uint256).max);
        buffer.approve(DAI,  address(swapper), type(uint256).max);
        buffer.approve(USDC, address(depositor), type(uint256).max);
        buffer.approve(DAI,  address(depositor), type(uint256).max);
        buffer.setApprovalForAll(UNIV3_POS_MGR,  address(depositor), true);
    }

    function testSwapDepositor() public {
        assertEq(TestGemLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 0);
        uint256 prevUSDC = TestGemLike(USDC).balanceOf(address(buffer));
        uint256 prevDAI = TestGemLike(DAI).balanceOf(address(buffer));

        bytes memory path = abi.encodePacked(DAI, uint24(100), USDC);
        int24 refTick = -276324; // ~=  math.log(10**(-12) gem0/gem1)/math.log(1.0001)
        SwapDepositor.SwapDepositParams memory dp = SwapDepositor.SwapDepositParams({ 
            gem0: DAI,
            gem1: USDC,
            amt0: 1000 * WAD, 
            amt1: 0 * 10**6, 
            minAmt0: 490 * WAD, 
            minAmt1: 490 * 10**6, 
            minSwappedOut: 490 * 10**6,
            fee: uint24(100), 
            tickLower: refTick-100, 
            tickUpper: refTick+100, 
            swapperCallee: address(uniV3Callee), 
            swapperData: path
        });
        vm.prank(FACILITATOR); (uint128 liq1,,) = swapDepositor.deposit(dp);

        assertLt(TestGemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertGe(TestGemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(TestGemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(TestGemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(TestGemLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);
        prevUSDC = TestGemLike(USDC).balanceOf(address(buffer));
        prevDAI = TestGemLike(DAI).balanceOf(address(buffer));

        vm.warp(block.timestamp + 3600);
        vm.prank(FACILITATOR);  (uint128 liq2,,) = swapDepositor.deposit(dp);

        assertLt(TestGemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertGe(TestGemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(TestGemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(TestGemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(TestGemLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);
        prevUSDC = TestGemLike(USDC).balanceOf(address(buffer));
        prevDAI = TestGemLike(DAI).balanceOf(address(buffer));

        path = abi.encodePacked(USDC, uint24(100), DAI);
        SwapDepositor.WithdrawSwapParams memory wp = SwapDepositor.WithdrawSwapParams({ 
            gem0: DAI,
            gem1: USDC,
            liquidity: liq1 + liq2,
            minAmt0: 880 * WAD, 
            minAmt1: 880 * 10**6, 
            swappedAmt0: 0,
            swappedAmt1: type(uint256).max,
            minSwappedOut: 880 * 10**6,
            fee: uint24(100), 
            tickLower: refTick-100, 
            tickUpper: refTick+100, 
            swapperCallee: address(uniV3Callee), 
            swapperData: path
        });
        vm.warp(block.timestamp + 3600);
        vm.prank(FACILITATOR); swapDepositor.withdraw(wp);
        
        assertGt(TestGemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertEq(TestGemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(TestGemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(TestGemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(TestGemLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);
    }
}
