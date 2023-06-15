// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "../../funnels/Depositor.sol";
import "../../funnels/Swapper.sol";
import "../../funnels/UniV3SwapperCallee.sol";
import "../../AllocatorRoles.sol";
import "../../AllocatorBuffer.sol";
import "dss-test/DssTest.sol";

contract DepositorTest is DssTest {
    AllocatorBuffer public buffer;
    Swapper public swapper;
    Depositor public depositor;
    UniV3SwapperCallee public uniV3Callee;

    address constant DAI           = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC          = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNIV3_ROUTER  = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNIV3_POS_MGR = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address constant FACILITATOR = address(0x1337);
    address constant KEEPER      = address(0xb0b);

    uint8 constant DEPOSITOR_ROLE = uint8(2);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        buffer = new AllocatorBuffer();
        swapper = new Swapper();
        depositor = new Depositor(UNIV3_POS_MGR, UNIV3_FACTORY);
        uniV3Callee = new UniV3SwapperCallee(UNIV3_ROUTER);
        AllocatorRoles roles = new AllocatorRoles();

        swapper.rely(address(depositor));

        roles.setRoleAction(DEPOSITOR_ROLE, address(depositor), depositor.deposit.selector, true);
        roles.setRoleAction(DEPOSITOR_ROLE, address(depositor), depositor.withdraw.selector, true);
        roles.setUserRole(FACILITATOR, DEPOSITOR_ROLE, true);

        swapper.file("buffer", address(buffer));
        swapper.file("roles", address(roles));
        swapper.file("maxSrcAmt", DAI, USDC, 10_000 * WAD);
        swapper.file("maxSrcAmt", USDC, DAI, 10_000 * 10**6);
        swapper.file("hop", DAI, USDC, 3600);
        swapper.file("hop", USDC, DAI, 3600);

        depositor.file("buffer", address(buffer));
        depositor.file("roles", address(roles));
        depositor.file("swapper", address(swapper));

        deal(DAI,  address(buffer), 1_000_000 * WAD,   true);
        deal(USDC, address(buffer), 1_000_000 * 10**6, true);
        buffer.approve(USDC, address(swapper), type(uint256).max);
        buffer.approve(DAI,  address(swapper), type(uint256).max);
        buffer.approve(USDC, address(depositor), type(uint256).max);
        buffer.approve(DAI,  address(depositor), type(uint256).max);
        buffer.setApprovalForAll(UNIV3_POS_MGR,  address(depositor), true);
    }

    function testDepositor() public {
        assertEq(GemLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 0);
        uint256 prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        uint256 prevDAI = GemLike(DAI).balanceOf(address(buffer));

        bytes memory path = abi.encodePacked(DAI, uint24(100), USDC);
        int24 refTick = -276324; // ~=  math.log(10**(-12) gem0/gem1)/math.log(1.0001)
        Depositor.DepositParams memory dp = Depositor.DepositParams({ 
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
        vm.prank(FACILITATOR); (uint128 liq1,,) = depositor.deposit(dp);

        assertLt(GemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(GemLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);
        prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        prevDAI = GemLike(DAI).balanceOf(address(buffer));

        vm.warp(block.timestamp + 3600);
        vm.prank(FACILITATOR);  (uint128 liq2,,) = depositor.deposit(dp);

        assertLt(GemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(GemLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);
        prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        prevDAI = GemLike(DAI).balanceOf(address(buffer));

        path = abi.encodePacked(USDC, uint24(100), DAI);
        Depositor.WithdrawParams memory wp = Depositor.WithdrawParams({ 
            gem0: DAI,
            gem1: USDC,
            liquidity: liq1 + liq2,
            minAmt0: 880 * WAD, 
            minAmt1: 880 * 10**6, 
            swappedAmt0: 0,
            swappedAmt1: 1000 * 10**6,
            minSwappedOut: 880 * 10**6,
            fee: uint24(100), 
            tickLower: refTick-100, 
            tickUpper: refTick+100, 
            swapperCallee: address(uniV3Callee), 
            swapperData: path
        });
        vm.prank(FACILITATOR); depositor.withdraw(wp);
        
        assertGt(GemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertEq(GemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(GemLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);
    }
}
