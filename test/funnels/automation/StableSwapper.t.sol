// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { Swapper, GemLike } from "src/funnels/Swapper.sol";
import { StableSwapper } from "src/funnels/automation/StableSwapper.sol";
import { UniV3SwapperCallee } from "src/funnels/callees/UniV3SwapperCallee.sol";
import { AllocatorRoles } from "src/AllocatorRoles.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";
import { TestUtils } from "test/utils/TestUtils.sol";

contract StableSwapperTest is DssTest, TestUtils {
    AllocatorBuffer public buffer;
    Swapper public swapper;
    StableSwapper public stableSwapper;
    UniV3SwapperCallee public uniV3Callee;

    bytes32 constant ilk = "aaa";

    address constant DAI          = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC         = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address constant FACILITATOR = address(0x1337);
    address constant KEEPER      = address(0xb0b);

    uint8 constant SWAPPER_ROLE = uint8(1);


    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        buffer = new AllocatorBuffer(ilk);
        AllocatorRoles roles = new AllocatorRoles();
        swapper = new Swapper(address(roles), ilk, address(buffer));
        uniV3Callee = new UniV3SwapperCallee(UNIV3_ROUTER);
        vm.prank(FACILITATOR); stableSwapper = new StableSwapper(address(swapper));

        roles.setIlkAdmin(ilk, address(this));
        roles.setRoleAction(ilk, SWAPPER_ROLE, address(swapper), swapper.swap.selector, true);
        roles.setUserRole(ilk, FACILITATOR, SWAPPER_ROLE, true);
        roles.setUserRole(ilk, address(stableSwapper), SWAPPER_ROLE, true);

        swapper.file("cap", DAI, USDC, 10_000 * WAD);
        swapper.file("cap", USDC, DAI, 10_000 * 10**6);
        swapper.file("hop", DAI, USDC, 3600);
        swapper.file("hop", USDC, DAI, 3600);

        deal(DAI,  address(buffer), 1_000_000 * WAD,   true);
        deal(USDC, address(buffer), 1_000_000 * 10**6, true);
        buffer.approve(USDC, address(swapper), type(uint256).max);
        buffer.approve(DAI,  address(swapper), type(uint256).max);

        vm.startPrank(FACILITATOR); 
        stableSwapper.setConfig(DAI, USDC, StableSwapper.PairConfig({ 
               count: 10,
                 lot: uint112(10_000 * WAD), 
              reqOut: uint112(9900 * 10**6)
        }));
        stableSwapper.setConfig(USDC, DAI, StableSwapper.PairConfig({ 
               count: 10,
                 lot: uint96(10_000 * 10**6), 
              reqOut: uint112(9900 * WAD)
        }));
        stableSwapper.kiss(KEEPER);
        vm.stopPrank();
    }

    function testConstructor() public {
        StableSwapper s = new StableSwapper(address(0xABC));
        assertEq(address(s.swapper()),  address(0xABC));
        assertEq(s.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(stableSwapper), "StableSwapper");
    }

    function testSwapByKeeper() public {
        vm.warp(block.timestamp + 3600);
        bytes memory path = abi.encodePacked(USDC, uint24(100), DAI);
        uint256 prevDst = GemLike(DAI).balanceOf(address(buffer));
        vm.prank(KEEPER); uint256 out = stableSwapper.swap(USDC, DAI, 9900 * WAD, address(uniV3Callee), path);
        assertGe(GemLike(DAI).balanceOf(address(buffer)), prevDst + 9900 * WAD);

        vm.warp(block.timestamp + 3600);
        path = abi.encodePacked(DAI, uint24(100), USDC);
        prevDst = GemLike(USDC).balanceOf(address(buffer));
        vm.prank(KEEPER); out = stableSwapper.swap(DAI, USDC, 9900 * 10**6, address(uniV3Callee), path);
        assertGe(GemLike(USDC).balanceOf(address(buffer)), prevDst + 9900 * 10**6);
    }

}
