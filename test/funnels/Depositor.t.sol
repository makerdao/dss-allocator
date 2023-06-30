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

interface NftLike {
    function balanceOf(address) external view returns (uint256);
    function transferFrom(address, address, uint256) external;
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
    event Deposit(address indexed sender, address indexed gem0, address indexed gem1, uint128 liquidity, uint256 amt0, uint256 amt1);
    event Withdraw(address indexed sender, address indexed gem0, address indexed gem1, uint128 liquidity, uint256 amt0, uint256 amt1);
    event Collect(address indexed sender, address indexed gem0, address indexed gem1, uint256 amt0, uint256 amt1);


    AllocatorRoles public roles;
    AllocatorBuffer public buffer;
    Depositor public depositor;
    UniV3SwapperCallee public uniV3Callee;

    bytes32 constant ilk = "aaa";

    address constant DAI           = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC          = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNIV3_POS_MGR = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant UNIV3_ROUTER  = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address constant FACILITATOR    = address(0x1337);
    uint8   constant DEPOSITOR_ROLE = uint8(2);

    int24 constant REF_TICK = -276324; // tick corresponding to 1 DAI = 1 USDC calculated as ~= math.log(10**(-12))/math.log(1.0001)

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        buffer = new AllocatorBuffer(ilk);
        roles = new AllocatorRoles();
        depositor = new Depositor(address(roles), ilk, UNIV3_FACTORY, UNIV3_POS_MGR, address(buffer));

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
        Depositor d = new Depositor(address(0xBEEF), "SubDAO 1", address(0xAAA), address(0xBBB), address(0xCCC));
        assertEq(address(d.roles()),  address(0xBEEF));
        assertEq(d.ilk(), "SubDAO 1");
        assertEq(d.uniV3Factory(), address(0xAAA));
        assertEq(d.uniV3PositionManager(), address(0xBBB));
        assertEq(d.buffer(), address(0xCCC));
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

    function testDeposit() public {
        assertEq(NftLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 0);
        uint256 prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        uint256 prevDAI = GemLike(DAI).balanceOf(address(buffer));

        Depositor.DepositParams memory dp = Depositor.DepositParams({ 
            gem0: DAI,
            gem1: USDC,
            amt0: 500 * WAD, 
            amt1: 500 * 10**6, 
            minAmt0: 490 * WAD, 
            minAmt1: 490 * 10**6, 
            fee: uint24(100), 
            tickLower: REF_TICK-100, 
            tickUpper: REF_TICK+100
        });
        vm.expectEmit(true, true, true, false);
        emit Deposit(FACILITATOR, DAI, USDC, 0, 0, 0);
        vm.prank(FACILITATOR); depositor.deposit(dp);

        assertLt(GemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertLt(GemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(NftLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);
        prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        prevDAI = GemLike(DAI).balanceOf(address(buffer));

        vm.warp(block.timestamp + 3600);
        vm.expectEmit(true, true, true, false);
        emit Deposit(FACILITATOR, DAI, USDC, 0, 0, 0);
        vm.prank(FACILITATOR); depositor.deposit(dp);

        assertLt(GemLike(DAI).balanceOf(address(buffer)), prevDAI);
        assertLt(GemLike(USDC).balanceOf(address(buffer)), prevUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(NftLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);
    }

    function testCollect() public {
        Depositor.DepositParams memory dp = Depositor.DepositParams({ 
            gem0: DAI,
            gem1: USDC,
            amt0: 500 * WAD, 
            amt1: 500 * 10**6, 
            minAmt0: 490 * WAD, 
            minAmt1: 490 * 10**6, 
            fee: uint24(100), 
            tickLower: REF_TICK-100, 
            tickUpper: REF_TICK+100
        });
        vm.prank(FACILITATOR); depositor.deposit(dp);
        uint256 prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        uint256 prevDAI = GemLike(DAI).balanceOf(address(buffer));

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
            tickLower: REF_TICK-100, 
            tickUpper: REF_TICK+100
        });
        vm.expectEmit(true, true, true, false);
        emit Collect(FACILITATOR, DAI, USDC, 0, 0);
        vm.prank(FACILITATOR); (uint256 amt0, uint256 amt1) = depositor.collect(cp);

        assertTrue(
            (amt0 > 0 && GemLike(DAI ).balanceOf(address(buffer)) > prevDAI ) || 
            (amt1 > 0 && GemLike(USDC).balanceOf(address(buffer)) > prevUSDC)
        );
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
    }

    function testWithdrawWithNoFeeCollection() public {
        uint256 initialUSDC = GemLike(USDC).balanceOf(address(buffer));
        uint256 initialDAI = GemLike(DAI).balanceOf(address(buffer));
        Depositor.DepositParams memory dp = Depositor.DepositParams({ 
            gem0: DAI,
            gem1: USDC,
            amt0: 500 * WAD, 
            amt1: 500 * 10**6, 
            minAmt0: 490 * WAD, 
            minAmt1: 490 * 10**6, 
            fee: uint24(100), 
            tickLower: REF_TICK-100, 
            tickUpper: REF_TICK+100
        });
        vm.prank(FACILITATOR); (uint128 liq, uint256 deposited0, uint256 deposited1) = depositor.deposit(dp);

        Depositor.WithdrawParams memory wp = Depositor.WithdrawParams({ 
            gem0: DAI,
            gem1: USDC,
            liquidity: liq,
            minAmt0: 490 * WAD, 
            minAmt1: 490 * 10**6,
            fee: uint24(100), 
            tickLower: REF_TICK-100, 
            tickUpper: REF_TICK+100,
            collectFees: false
        });
        vm.warp(block.timestamp + 3600);
        vm.expectEmit(true, true, true, false);
        emit Withdraw(FACILITATOR, DAI, USDC, liq, 0, 0);
        vm.prank(FACILITATOR); (uint256 withdrawn0, uint256 withdrawn1) = depositor.withdraw(wp);
        
        assertTrue(withdrawn0 + 1 >= deposited0);
        assertTrue(withdrawn1 + 1 >= deposited1);
        assertTrue(GemLike(DAI).balanceOf(address(buffer)) + 1 >= initialDAI);
        assertTrue(GemLike(USDC).balanceOf(address(buffer)) + 1 >= initialUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(NftLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);
    }

    function testWithdrawWithFeeCollection() public {
        uint256 initialUSDC = GemLike(USDC).balanceOf(address(buffer));
        uint256 initialDAI = GemLike(DAI).balanceOf(address(buffer));
        Depositor.DepositParams memory dp = Depositor.DepositParams({ 
            gem0: DAI,
            gem1: USDC,
            amt0: 500 * WAD, 
            amt1: 500 * 10**6, 
            minAmt0: 490 * WAD, 
            minAmt1: 490 * 10**6, 
            fee: uint24(100), 
            tickLower: REF_TICK-100, 
            tickUpper: REF_TICK+100
        });
        vm.prank(FACILITATOR); (uint128 liq, uint256 deposited0, uint256 deposited1) = depositor.deposit(dp);
        uint256 prevUSDC = GemLike(USDC).balanceOf(address(buffer));
        uint256 prevDAI = GemLike(DAI).balanceOf(address(buffer));

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

        Depositor.WithdrawParams memory wp = Depositor.WithdrawParams({ 
            gem0: DAI,
            gem1: USDC,
            liquidity: liq,
            minAmt0: 490 * WAD, 
            minAmt1: 490 * 10**6,
            fee: uint24(100), 
            tickLower: REF_TICK-100, 
            tickUpper: REF_TICK+100,
            collectFees: true
        });
        vm.warp(block.timestamp + 3600);
        vm.expectEmit(true, true, true, false);
        emit Withdraw(FACILITATOR, DAI, USDC, liq, 0, 0);
        vm.prank(FACILITATOR); (uint256 withdrawn0, uint256 withdrawn1) = depositor.withdraw(wp);

        assertTrue(
            (withdrawn0 > deposited0 && GemLike(DAI ).balanceOf(address(buffer)) > initialDAI ) || 
            (withdrawn1 > deposited1 && GemLike(USDC).balanceOf(address(buffer)) > initialUSDC)
        );
        assertTrue(GemLike(DAI).balanceOf(address(buffer)) >= prevDAI);
        assertTrue(GemLike(USDC).balanceOf(address(buffer)) >= prevUSDC);
        assertEq(GemLike(DAI).balanceOf(address(depositor)), 0);
        assertEq(GemLike(USDC).balanceOf(address(depositor)), 0);
        assertEq(NftLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);        
    }

    function testMoveLiquidity() public {
        Depositor.DepositParams memory dp = Depositor.DepositParams({ 
            gem0: DAI,
            gem1: USDC,
            amt0: 500 * WAD, 
            amt1: 500 * 10**6, 
            minAmt0: 490 * WAD, 
            minAmt1: 490 * 10**6, 
            fee: uint24(100), 
            tickLower: REF_TICK-100, 
            tickUpper: REF_TICK+100
        });
        vm.prank(FACILITATOR); depositor.deposit(dp);
        bytes32 key = keccak256(abi.encode(dp.gem0, dp.gem1, dp.fee, dp.tickLower, dp.tickUpper));
        uint256 tokenId = depositor.tokenIds(key);
        address newBuffer = address(new AllocatorBuffer(ilk));
        buffer.setApprovalForAll(UNIV3_POS_MGR, address(this), true);
        assertEq(NftLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 1);
        assertEq(NftLike(UNIV3_POS_MGR).balanceOf(newBuffer), 0);

        NftLike(UNIV3_POS_MGR).transferFrom(address(buffer), newBuffer, tokenId);

        assertEq(NftLike(UNIV3_POS_MGR).balanceOf(address(buffer)), 0);
        assertEq(NftLike(UNIV3_POS_MGR).balanceOf(newBuffer), 1);
    }
}
