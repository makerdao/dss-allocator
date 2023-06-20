// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import "src/funnels/Depositor.sol";
import "src/funnels/UniV3SwapperCallee.sol";
import "src/AllocatorRoles.sol";
import "src/AllocatorBuffer.sol";

interface TestGemLike {
    function balanceOf(address) external view returns (uint256);
}

contract DepositorTest is DssTest {
    AllocatorBuffer public buffer;
    Depositor public depositor;
    UniV3SwapperCallee public uniV3Callee;

    address constant DAI           = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC          = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNIV3_POS_MGR = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    address constant FACILITATOR = address(0x1337);

    uint8 constant DEPOSITOR_ROLE = uint8(2);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        buffer = new AllocatorBuffer();
        depositor = new Depositor(UNIV3_POS_MGR);
        AllocatorRoles roles = new AllocatorRoles();

        roles.setRoleAction(DEPOSITOR_ROLE, address(depositor), depositor.deposit.selector, true);
        roles.setRoleAction(DEPOSITOR_ROLE, address(depositor), depositor.withdraw.selector, true);
        roles.setUserRole(FACILITATOR, DEPOSITOR_ROLE, true);

        depositor.file("buffer", address(buffer));
        depositor.file("roles", address(roles));
        depositor.file("cap", DAI, USDC, 10_000 * WAD * 10_000 * 10**6);
        depositor.file("hop", DAI, USDC, 3600);

        deal(DAI,  address(buffer), 1_000_000 * WAD,   true);
        deal(USDC, address(buffer), 1_000_000 * 10**6, true);
        buffer.approve(USDC, address(depositor), type(uint256).max);
        buffer.approve(DAI,  address(depositor), type(uint256).max);
        buffer.setApprovalForAll(UNIV3_POS_MGR,  address(depositor), true);
    }

    function testDepositor() public {
        assertEq(TestGemLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 0);
        uint256 prevUSDC = TestGemLike(USDC).balanceOf(address(buffer));
        uint256 prevDAI = TestGemLike(DAI).balanceOf(address(buffer));

        bytes memory path = abi.encodePacked(DAI, uint24(100), USDC);
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

        assertLt(TestGemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertLt(TestGemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(TestGemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(TestGemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(TestGemLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);
        prevUSDC = TestGemLike(USDC).balanceOf(address(buffer));
        prevDAI = TestGemLike(DAI).balanceOf(address(buffer));

        vm.warp(block.timestamp + 3600);
        vm.prank(FACILITATOR);  (uint128 liq2,,) = depositor.deposit(dp);

        assertLt(TestGemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertLt(TestGemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(TestGemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(TestGemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(TestGemLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);
        prevUSDC = TestGemLike(USDC).balanceOf(address(buffer));
        prevDAI = TestGemLike(DAI).balanceOf(address(buffer));

        path = abi.encodePacked(USDC, uint24(100), DAI);
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
        
        assertGt(TestGemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertGt(TestGemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(TestGemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(TestGemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(TestGemLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);
    }
}
