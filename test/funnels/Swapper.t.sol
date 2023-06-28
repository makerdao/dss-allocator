// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import { Swapper, GemLike } from "src/funnels/Swapper.sol";
import { UniV3SwapperCallee } from "src/funnels/callees/UniV3SwapperCallee.sol";
import { AllocatorRoles } from "src/AllocatorRoles.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";
import { TestUtils } from "test/utils/TestUtils.sol";

contract SwapperTest is DssTest, TestUtils {
    AllocatorRoles public roles;
    AllocatorBuffer public buffer;
    Swapper public swapper;
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
        roles = new AllocatorRoles();
        swapper = new Swapper(address(roles), ilk);
        uniV3Callee = new UniV3SwapperCallee(UNIV3_ROUTER);

        roles.setIlkAdmin(ilk, address(this));
        roles.setRoleAction(ilk, SWAPPER_ROLE, address(swapper), swapper.swap.selector, true);
        roles.setUserRole(ilk, FACILITATOR, SWAPPER_ROLE, true);

        swapper.file("buffer", address(buffer));
        swapper.file("cap", DAI, USDC, 10_000 * WAD);
        swapper.file("cap", USDC, DAI, 10_000 * 10**6);
        swapper.file("hop", DAI, USDC, 3600);
        swapper.file("hop", USDC, DAI, 3600);

        deal(DAI,  address(buffer), 1_000_000 * WAD,   true);
        deal(USDC, address(buffer), 1_000_000 * 10**6, true);
        buffer.approve(USDC, address(swapper), type(uint256).max);
        buffer.approve(DAI,  address(swapper), type(uint256).max);
    }

    function testConstructor() public {
        Swapper s = new Swapper(address(0xBEEF), "SubDAO 1");
        assertEq(address(s.roles()),  address(0xBEEF));
        assertEq(s.ilk(), "SubDAO 1");
        assertEq(s.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(swapper), "Swapper");
    }

    function testModifiers() public {
        bytes4[] memory authedMethods = new bytes4[](1);
        authedMethods[0] = swapper.swap.selector;

        vm.startPrank(address(0xBEEF));
        checkModifier(address(swapper), "Swapper/not-authorized", authedMethods);
        vm.stopPrank();
    }

    function testFile() public {
        checkFileAddress(address(swapper), "Swapper", ["buffer"]);
        checkFileUintForGemPair(address(swapper), "Swapper", ["cap", "hop"]);
    }

    function testRoles() public {
        vm.expectRevert("Swapper/not-authorized");
        vm.prank(address(0xBEEF)); swapper.file("buffer", address(0));
        roles.setRoleAction(ilk, uint8(0xF1), address(swapper), bytes4(keccak256("file(bytes32,address)")), true);
        roles.setUserRole(ilk, address(0xBEEF), uint8(0xF1), true);
        vm.prank(address(0xBEEF)); swapper.file("buffer", address(0));
    }

    function testSwap() public {
        bytes memory path = abi.encodePacked(USDC, uint24(100), DAI);
        uint256 prevDst = GemLike(DAI).balanceOf(address(buffer));
        vm.prank(FACILITATOR); uint256 out = swapper.swap(USDC, DAI, 10_000 * 10**6, 9900 * WAD, address(uniV3Callee), path);
        assertGe(GemLike(DAI).balanceOf(address(buffer)), prevDst + 9900 * WAD);

        path = abi.encodePacked(DAI, uint24(100), USDC);
        prevDst = GemLike(USDC).balanceOf(address(buffer));
        vm.prank(FACILITATOR); out = swapper.swap(DAI, USDC, 10_000 * WAD, 9900 * 10**6, address(uniV3Callee), path);
        assertGe(GemLike(USDC).balanceOf(address(buffer)), prevDst + 9900 * 10**6);
    }
}
