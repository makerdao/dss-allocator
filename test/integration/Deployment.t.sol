// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";

import { AllocatorSharedInstance, AllocatorIlkInstance } from "deploy/AllocatorInstances.sol";
import { AllocatorIlkFunnelInstance } from "deploy/funnels/AllocatorFunnelInstance.sol";
import { AllocatorDeploy } from "deploy/AllocatorDeploy.sol";
import { AllocatorFunnelDeploy } from "deploy/funnels/AllocatorFunnelDeploy.sol";
import { AllocatorInit, AllocatorIlkConfig } from "deploy/AllocatorInit.sol";
import { AllocatorFunnelInit, AllocatorIlkFunnelConfig } from "deploy/funnels/AllocatorFunnelInit.sol";

import { SwapperCalleeUniV3 } from "src/funnels/callees/SwapperCalleeUniV3.sol";

import { GemMock } from "test/mocks/GemMock.sol";
import { UsdsJoinMock } from "test/mocks/UsdsJoinMock.sol";
import { VatMock } from "test/mocks/VatMock.sol";
import { AllocatorConduitMock } from "test/mocks/AllocatorConduitMock.sol";

import { AllocatorRoles } from "src/AllocatorRoles.sol";
import { AllocatorRegistry } from "src/AllocatorRegistry.sol";
import { AllocatorVault } from "src/AllocatorVault.sol";
import { AllocatorBuffer } from "src/AllocatorBuffer.sol";
import { Swapper } from "src/funnels/Swapper.sol";
import { DepositorUniV3 } from "src/funnels/DepositorUniV3.sol";
import { VaultMinter } from "src/funnels/automation/VaultMinter.sol";
import { StableSwapper } from "src/funnels/automation/StableSwapper.sol";
import { StableDepositorUniV3 } from "src/funnels/automation/StableDepositorUniV3.sol";
import { ConduitMover } from "src/funnels/automation/ConduitMover.sol";

interface GemLike {
    function allowance(address, address) external view returns (uint256);
}

interface WardsLike {
    function wards(address) external view returns (uint256);
}

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface IlkRegistryLike {
    function count() external view returns (uint256);
    function pos(bytes32) external view returns (uint256);
    function class(bytes32) external view returns (uint256);
    function gem(bytes32) external view returns (address);
    function pip(bytes32) external view returns (address);
    function join(bytes32) external view returns (address);
    function xlip(bytes32) external view returns (address);
    function dec(bytes32) external view returns (uint256);
    function symbol(bytes32) external view returns (string memory);
    function name(bytes32) external view returns (string memory);
}

interface AutoLineLike {
    function ilks(bytes32) external view returns (uint256, uint256, uint48, uint48, uint48);
}

contract DeploymentTest is DssTest {

    using stdStorage for StdStorage;

    // existing contracts
    address constant LOG           = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    address constant UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant UNIV3_ROUTER  = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    // existing contracts to be fetched from chainlog
    DssInstance dss;
    address ILK_REGISTRY;
    address PAUSE_PROXY;
    address USDC;

    // actors
    address constant allocatorProxy              = address(0x1);
    address constant facilitator1                = address(0x2);
    address constant facilitator2                = address(0x3);
    address constant vaultMinterKeeper1          = address(0x4);
    address constant vaultMinterKeeper2          = address(0x5);
    address constant stableSwapperKeeper1        = address(0x6);
    address constant stableSwapperKeeper2        = address(0x7);
    address constant stableDepositorUniV3Keeper1 = address(0x8);
    address constant stableDepositorUniV3Keeper2 = address(0x9);
    address constant conduitMoverKeeper1         = address(0xA);
    address constant conduitMoverKeeper2         = address(0xB);

    // roles
    uint8 constant facilitatorRole = uint8(1);
    uint8 constant automationRole  = uint8(2);

    // contracts to be deployed
    address usds;
    address usdsJoin;
    address uniV3Callee;
    address conduit1;
    address conduit2;

    // storage to be initiated on setup
    AllocatorSharedInstance sharedInst;
    AllocatorIlkInstance ilkInst;
    AllocatorIlkFunnelInstance ilkFunnelInst;
    bytes usdcDaiPath;
    bytes daiUsdcPath;

    // constants
    int24 constant REF_TICK = -276324; // tick corresponding to 1 DAI = 1 USDC calculated as ~= math.log(10**(-12))/math.log(1.0001)
    bytes32 constant ILK = "ILK-A";

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        dss          = MCD.loadFromChainlog(LOG);
        PAUSE_PROXY  = ChainlogLike(LOG).getAddress("MCD_PAUSE_PROXY");
        ILK_REGISTRY = ChainlogLike(LOG).getAddress("ILK_REGISTRY");
        USDC         = ChainlogLike(LOG).getAddress("USDC");

        usds        = address(new GemMock(0));
        usdsJoin    = address(new UsdsJoinMock(VatMock(address(dss.vat)), GemMock(usds)));
        uniV3Callee = address(new SwapperCalleeUniV3(UNIV3_ROUTER));

        usdcDaiPath = abi.encodePacked(USDC, uint24(100), address(dss.dai));
        daiUsdcPath = abi.encodePacked(address(dss.dai),  uint24(100), USDC);

        sharedInst = AllocatorDeploy.deployShared(address(this), PAUSE_PROXY);
        ilkInst = AllocatorDeploy.deployIlk({
            deployer     : address(this),
            owner        : PAUSE_PROXY,
            roles        : sharedInst.roles,
            ilk          : ILK,
            usdsJoin     : usdsJoin
        });
        ilkFunnelInst = AllocatorFunnelDeploy.deployIlkFunnel({
            deployer     : address(this),
            owner        : allocatorProxy,
            roles        : sharedInst.roles,
            ilk          : ILK,
            uniV3Factory : UNIV3_FACTORY,
            vault        : ilkInst.vault,
            buffer       : ilkInst.buffer
        });

        // Deploy conduits (assumed to be done separately than the current allocator ilkInst deploy)
        conduit1 = address(new AllocatorConduitMock(sharedInst.roles, sharedInst.registry));
        conduit2 = address(new AllocatorConduitMock(sharedInst.roles, sharedInst.registry));
    }

    function emulateSpell() internal {
        vm.startPrank(PAUSE_PROXY);
        AllocatorInit.initShared(dss, sharedInst);

        address[] memory swapTokens = new address[](1);
        swapTokens[0] = address(dss.dai);

        address[] memory depositTokens = new address[](2);
        depositTokens[0] = address(dss.dai);
        depositTokens[1] = USDC;

        address[] memory facilitators = new address[](2);
        facilitators[0] = facilitator1;
        facilitators[1] = facilitator2;

        address[] memory vaultMinterKeepers = new address[](2);
        vaultMinterKeepers[0] = vaultMinterKeeper1;
        vaultMinterKeepers[1] = vaultMinterKeeper2;

        address[] memory stableSwapperKeepers = new address[](2);
        stableSwapperKeepers[0] = stableSwapperKeeper1;
        stableSwapperKeepers[1] = stableSwapperKeeper2;

        address[] memory stableDepositorUniV3Keepers = new address[](2);
        stableDepositorUniV3Keepers[0] = stableDepositorUniV3Keeper1;
        stableDepositorUniV3Keepers[1] = stableDepositorUniV3Keeper2;

        address[] memory conduitMoverKeepers = new address[](2);
        conduitMoverKeepers[0] = conduitMoverKeeper1;
        conduitMoverKeepers[1] = conduitMoverKeeper2;

        AllocatorIlkConfig memory cfg = AllocatorIlkConfig({
            ilk                         : ILK,
            duty                        : 1000000001243680656318820312,
            maxLine                     : 100_000_000 * RAD,
            gap                         : 10_000_000 * RAD,
            ttl                         : 1 days,
            allocatorProxy              : allocatorProxy,
            ilkRegistry                 : ILK_REGISTRY
        });

        AllocatorInit.initIlk(dss, sharedInst, ilkInst, cfg);
        vm.stopPrank();

        // Init conduits (assumed to be done separately than the current allocator ilkInst init)
        vm.startPrank(allocatorProxy);
        AllocatorIlkFunnelConfig memory funnelCfg = AllocatorIlkFunnelConfig({
            ilk                         : ILK,
            allocatorProxy              : allocatorProxy,
            facilitatorRole             : facilitatorRole,
            automationRole              : automationRole,
            facilitators                : facilitators,
            vaultMinterKeepers          : vaultMinterKeepers,
            stableSwapperKeepers        : stableSwapperKeepers,
            stableDepositorUniV3Keepers : stableDepositorUniV3Keepers,
            conduitMoverKeepers         : conduitMoverKeepers,
            swapTokens                  : swapTokens,
            depositTokens               : depositTokens,
            uniV3Factory                : UNIV3_FACTORY
        });
        AllocatorFunnelInit.initIlkFunnel(sharedInst, ilkInst, ilkFunnelInst, funnelCfg);

        AllocatorRoles(sharedInst.roles).setUserRole(ILK, address(ilkFunnelInst.conduitMover), automationRole, true);

        AllocatorRoles(sharedInst.roles).setRoleAction(ILK, automationRole, conduit1, AllocatorConduitMock.deposit.selector,  true);
        AllocatorRoles(sharedInst.roles).setRoleAction(ILK, automationRole, conduit1, AllocatorConduitMock.withdraw.selector, true);
        AllocatorRoles(sharedInst.roles).setRoleAction(ILK, automationRole, conduit2, AllocatorConduitMock.deposit.selector,  true);
        AllocatorRoles(sharedInst.roles).setRoleAction(ILK, automationRole, conduit2, AllocatorConduitMock.withdraw.selector, true);

        AllocatorBuffer(ilkInst.buffer).approve(USDC, conduit1, type(uint256).max);
        AllocatorBuffer(ilkInst.buffer).approve(USDC, conduit2, type(uint256).max);
        vm.stopPrank();
    }

    function testInitSharedValues() public {
        emulateSpell();

        assertEq(ChainlogLike(LOG).getAddress("ALLOCATOR_ROLES"),    sharedInst.roles);
        assertEq(ChainlogLike(LOG).getAddress("ALLOCATOR_REGISTRY"), sharedInst.registry);
    }

    function testInitIlkValues() public {
        uint256 previousLine = dss.vat.Line();
        uint256 previousIlkRegistryCount = IlkRegistryLike(ILK_REGISTRY).count();

        emulateSpell();

        (, uint256 rate, uint256 spot, uint256 line,) = dss.vat.ilks(ILK);
        assertEq(rate, RAY);
        assertEq(spot, 10**18 * RAY * 10**9 / dss.spotter.par());
        assertEq(line, 10_000_000 * RAD);
        assertEq(dss.vat.Line(), previousLine + 10_000_000 * RAD);

        {
            AutoLineLike autoLine = AutoLineLike(ChainlogLike(LOG).getAddress("MCD_IAM_AUTO_LINE"));
            (uint256 maxline, uint256 gap, uint48 ttl, uint48 last, uint48 lastInc) = autoLine.ilks(ILK);
            assertEq(maxline, 100_000_000 * RAD);
            assertEq(gap, 10_000_000 * RAD);
            assertEq(ttl, 1 days);
            assertEq(last, 0);
            assertEq(lastInc, 0);
        }

        (uint256 duty, uint256 rho) = dss.jug.ilks(ILK);
        assertEq(duty, 1000000001243680656318820312);
        assertEq(rho, block.timestamp);

        (address pip, uint256 mat) = dss.spotter.ilks(ILK);
        assertEq(pip, sharedInst.oracle);
        assertEq(mat, RAY);

        assertEq(dss.vat.gem(ILK, ilkInst.vault), 0);
        (uint256 ink, uint256 art) = dss.vat.urns(ILK, ilkInst.vault);
        assertEq(ink, 1_000_000_000_000 * WAD);
        assertEq(art, 0);

        assertEq(AllocatorRegistry(sharedInst.registry).buffers(ILK), ilkInst.buffer);
        assertEq(address(AllocatorVault(ilkInst.vault).jug()), address(dss.jug));

        assertEq(GemLike(usds).allowance(ilkInst.buffer, ilkInst.vault),                            type(uint256).max);
        assertEq(GemLike(address(dss.dai)).allowance(ilkInst.buffer, ilkFunnelInst.swapper),        type(uint256).max);
        assertEq(GemLike(address(dss.dai)).allowance(ilkInst.buffer, ilkFunnelInst.depositorUniV3), type(uint256).max);
        assertEq(GemLike(USDC).allowance(ilkInst.buffer, ilkFunnelInst.depositorUniV3),             type(uint256).max);

        assertEq(AllocatorRoles(sharedInst.roles).ilkAdmins(ILK), allocatorProxy);

        assertEq(AllocatorRoles(sharedInst.roles).hasUserRole(ILK, facilitator1, facilitatorRole), true);
        assertEq(AllocatorRoles(sharedInst.roles).hasUserRole(ILK, facilitator2, facilitatorRole), true);

        assertEq(AllocatorRoles(sharedInst.roles).hasActionRole(ILK, ilkInst.vault,                AllocatorVault.draw.selector,     facilitatorRole), true);
        assertEq(AllocatorRoles(sharedInst.roles).hasActionRole(ILK, ilkInst.vault,                AllocatorVault.wipe.selector,     facilitatorRole), true);
        assertEq(AllocatorRoles(sharedInst.roles).hasActionRole(ILK, ilkFunnelInst.swapper,        Swapper.swap.selector,            facilitatorRole), true);
        assertEq(AllocatorRoles(sharedInst.roles).hasActionRole(ILK, ilkFunnelInst.depositorUniV3, DepositorUniV3.deposit.selector,  facilitatorRole), true);
        assertEq(AllocatorRoles(sharedInst.roles).hasActionRole(ILK, ilkFunnelInst.depositorUniV3, DepositorUniV3.withdraw.selector, facilitatorRole), true);
        assertEq(AllocatorRoles(sharedInst.roles).hasActionRole(ILK, ilkFunnelInst.depositorUniV3, DepositorUniV3.collect.selector,  facilitatorRole), true);

        assertEq(AllocatorRoles(sharedInst.roles).hasUserRole(ILK, ilkFunnelInst.stableSwapper,        automationRole), true);
        assertEq(AllocatorRoles(sharedInst.roles).hasUserRole(ILK, ilkFunnelInst.stableDepositorUniV3, automationRole), true);

        assertEq(AllocatorRoles(sharedInst.roles).hasActionRole(ILK, ilkFunnelInst.swapper,        Swapper.swap.selector,            automationRole), true);
        assertEq(AllocatorRoles(sharedInst.roles).hasActionRole(ILK, ilkFunnelInst.depositorUniV3, DepositorUniV3.deposit.selector,  automationRole), true);
        assertEq(AllocatorRoles(sharedInst.roles).hasActionRole(ILK, ilkFunnelInst.depositorUniV3, DepositorUniV3.withdraw.selector, automationRole), true);
        assertEq(AllocatorRoles(sharedInst.roles).hasActionRole(ILK, ilkFunnelInst.depositorUniV3, DepositorUniV3.collect.selector,  automationRole), true);

        assertEq(WardsLike(ilkFunnelInst.vaultMinter).wards(facilitator1), 1);
        assertEq(WardsLike(ilkFunnelInst.vaultMinter).wards(facilitator2), 1);
        assertEq(WardsLike(ilkFunnelInst.stableSwapper).wards(facilitator1), 1);
        assertEq(WardsLike(ilkFunnelInst.stableSwapper).wards(facilitator2), 1);
        assertEq(WardsLike(ilkFunnelInst.stableDepositorUniV3).wards(facilitator1), 1);
        assertEq(WardsLike(ilkFunnelInst.stableDepositorUniV3).wards(facilitator2), 1);
        assertEq(WardsLike(ilkFunnelInst.conduitMover).wards(facilitator1), 1);
        assertEq(WardsLike(ilkFunnelInst.conduitMover).wards(facilitator2), 1);

        assertEq(VaultMinter(ilkFunnelInst.vaultMinter).buds(vaultMinterKeeper1), 1);
        assertEq(VaultMinter(ilkFunnelInst.vaultMinter).buds(vaultMinterKeeper2), 1);
        assertEq(StableSwapper(ilkFunnelInst.stableSwapper).buds(stableSwapperKeeper1), 1);
        assertEq(StableSwapper(ilkFunnelInst.stableSwapper).buds(stableSwapperKeeper2), 1);
        assertEq(StableDepositorUniV3(ilkFunnelInst.stableDepositorUniV3).buds(stableDepositorUniV3Keeper1), 1);
        assertEq(StableDepositorUniV3(ilkFunnelInst.stableDepositorUniV3).buds(stableDepositorUniV3Keeper2), 1);
        assertEq(ConduitMover(ilkFunnelInst.conduitMover).buds(conduitMoverKeeper1), 1);
        assertEq(ConduitMover(ilkFunnelInst.conduitMover).buds(conduitMoverKeeper2), 1);

        assertEq(WardsLike(ilkInst.vault).wards(PAUSE_PROXY), 0);
        assertEq(WardsLike(ilkInst.vault).wards(allocatorProxy), 1);

        assertEq(WardsLike(ilkInst.buffer).wards(PAUSE_PROXY), 0);
        assertEq(WardsLike(ilkInst.buffer).wards(allocatorProxy), 1);

        assertEq(WardsLike(ilkFunnelInst.swapper).wards(PAUSE_PROXY), 0);
        assertEq(WardsLike(ilkFunnelInst.swapper).wards(allocatorProxy), 1);

        assertEq(WardsLike(ilkFunnelInst.depositorUniV3).wards(PAUSE_PROXY), 0);
        assertEq(WardsLike(ilkFunnelInst.depositorUniV3).wards(allocatorProxy), 1);

        assertEq(WardsLike(ilkFunnelInst.vaultMinter).wards(PAUSE_PROXY), 0);
        assertEq(WardsLike(ilkFunnelInst.vaultMinter).wards(allocatorProxy), 1);

        assertEq(WardsLike(ilkFunnelInst.stableSwapper).wards(PAUSE_PROXY), 0);
        assertEq(WardsLike(ilkFunnelInst.stableSwapper).wards(allocatorProxy), 1);

        assertEq(WardsLike(ilkFunnelInst.stableDepositorUniV3).wards(PAUSE_PROXY), 0);
        assertEq(WardsLike(ilkFunnelInst.stableDepositorUniV3).wards(allocatorProxy), 1);

        assertEq(WardsLike(ilkFunnelInst.conduitMover).wards(PAUSE_PROXY), 0);
        assertEq(WardsLike(ilkFunnelInst.conduitMover).wards(allocatorProxy), 1);

        assertEq(ChainlogLike(LOG).getAddress("ILK_A_VAULT"),  ilkInst.vault);
        assertEq(ChainlogLike(LOG).getAddress("ILK_A_BUFFER"), ilkInst.buffer);
        assertEq(ChainlogLike(LOG).getAddress("PIP_ILK_A"), sharedInst.oracle);

        assertEq(IlkRegistryLike(ILK_REGISTRY).count(),     previousIlkRegistryCount + 1);
        assertEq(IlkRegistryLike(ILK_REGISTRY).pos(ILK),    previousIlkRegistryCount);
        assertEq(IlkRegistryLike(ILK_REGISTRY).join(ILK),   address(0));
        assertEq(IlkRegistryLike(ILK_REGISTRY).gem(ILK),    address(0));
        assertEq(IlkRegistryLike(ILK_REGISTRY).dec(ILK),    0);
        assertEq(IlkRegistryLike(ILK_REGISTRY).class(ILK),  5);
        assertEq(IlkRegistryLike(ILK_REGISTRY).pip(ILK),    sharedInst.oracle);
        assertEq(IlkRegistryLike(ILK_REGISTRY).xlip(ILK),   address(0));
        assertEq(IlkRegistryLike(ILK_REGISTRY).name(ILK),   string("ILK-A"));
        assertEq(IlkRegistryLike(ILK_REGISTRY).symbol(ILK), string("ILK-A"));
    }

    function testVaultDrawWipeFromFacilitator() public {
        emulateSpell();

        vm.prank(facilitator1); AllocatorVault(ilkInst.vault).draw(1_000 * WAD);
        vm.prank(facilitator1); AllocatorVault(ilkInst.vault).wipe(1_000 * WAD);
    }

    function testVaultDrawWipeFromFromKeeper() public {
        emulateSpell();

        vm.prank(facilitator1); VaultMinter(ilkFunnelInst.vaultMinter).setConfig(1, 1 hours, uint96(1_000 * WAD));
        vm.prank(vaultMinterKeeper1); VaultMinter(ilkFunnelInst.vaultMinter).draw();

        vm.prank(facilitator1); VaultMinter(ilkFunnelInst.vaultMinter).setConfig(-1, 1 hours, uint96(1_000 * WAD));
        vm.prank(vaultMinterKeeper1); VaultMinter(ilkFunnelInst.vaultMinter).wipe();
    }

    function testSwapFromFacilitator() public {
        emulateSpell();

        deal(address(dss.dai), ilkInst.buffer, 1_000 * WAD);

        vm.prank(allocatorProxy); Swapper(ilkFunnelInst.swapper).setLimits(address(dss.dai), USDC, uint96(1_000 * WAD), 1 hours);
        vm.prank(facilitator1); Swapper(ilkFunnelInst.swapper).swap(address(dss.dai), USDC, 1_000 * WAD, 990 * 10**6 , uniV3Callee, daiUsdcPath);
    }

    function testSwapFromKeeper() public {
        emulateSpell();

        deal(address(dss.dai), ilkInst.buffer, 1_000 * WAD);

        vm.prank(allocatorProxy); Swapper(ilkFunnelInst.swapper).setLimits(address(dss.dai), USDC, uint96(1_000 * WAD), 1 hours);
        vm.prank(facilitator1); StableSwapper(ilkFunnelInst.stableSwapper).setConfig(address(dss.dai), USDC, 1, 1 hours, uint96(1_000 * WAD), uint96(990 * 10**6));
        vm.prank(stableSwapperKeeper1); StableSwapper(ilkFunnelInst.stableSwapper).swap(address(dss.dai), USDC, 990 * 10**6, uniV3Callee, daiUsdcPath);
    }

    function testDepositWithdrawCollectFromFacilitator() public {
        emulateSpell();

        deal(address(dss.dai), ilkInst.buffer, 1_000 * WAD);
        deal(USDC, ilkInst.buffer, 1_000 * 10**6);

        vm.prank(allocatorProxy); DepositorUniV3(ilkFunnelInst.depositorUniV3).setLimits(address(dss.dai), USDC, uint24(100), uint96(2_000 * WAD), uint96(2_000 * 10**6), 1 hours);
        DepositorUniV3.LiquidityParams memory dp = DepositorUniV3.LiquidityParams({
            gem0       : address(dss.dai),
            gem1       : USDC,
            fee        : uint24(100),
            tickLower  : REF_TICK - 100,
            tickUpper  : REF_TICK + 100,
            liquidity  : 0,
            amt0Desired: 1_000 * WAD,
            amt1Desired: 1_000 * 10**6,
            amt0Min    : 900 * WAD,
            amt1Min    : 900 * 10**6
        });

        vm.prank(facilitator1); DepositorUniV3(ilkFunnelInst.depositorUniV3).deposit(dp);
        vm.prank(facilitator1); DepositorUniV3(ilkFunnelInst.depositorUniV3).withdraw(dp, false);

        DepositorUniV3.CollectParams memory cp = DepositorUniV3.CollectParams({
            gem0     : address(dss.dai),
            gem1     : USDC,
            fee      : uint24(100),
            tickLower: REF_TICK - 100,
            tickUpper: REF_TICK + 100
        });

        vm.expectRevert(bytes("NP")); // we make sure it reverts since no fees to collect and not because the call is unauthorized
        vm.prank(facilitator1); DepositorUniV3(ilkFunnelInst.depositorUniV3).collect(cp);
    }

    function testDepositWithdrawCollectFromKeeper() public {
        emulateSpell();

        deal(address(dss.dai), ilkInst.buffer, 1_000 * WAD);
        deal(USDC, ilkInst.buffer, 1_000 * 10**6);

        vm.prank(allocatorProxy); DepositorUniV3(ilkFunnelInst.depositorUniV3).setLimits(address(dss.dai), USDC, uint24(100), uint96(2_000 * WAD), uint96(2_000 * 10**6), 1 hours);

        vm.prank(facilitator1); StableDepositorUniV3(ilkFunnelInst.stableDepositorUniV3).setConfig(address(dss.dai), USDC, uint24(100), REF_TICK - 100, REF_TICK + 100, 1, 1 hours, uint96(1_000 * WAD), uint96(1000 * 10**6), 0, 0);
        vm.prank(stableDepositorUniV3Keeper1); StableDepositorUniV3(ilkFunnelInst.stableDepositorUniV3).deposit(address(dss.dai), USDC, uint24(100), REF_TICK - 100, REF_TICK + 100, 0, 0);

        vm.prank(facilitator1); StableDepositorUniV3(ilkFunnelInst.stableDepositorUniV3).setConfig(address(dss.dai), USDC, uint24(100), REF_TICK - 100, REF_TICK + 100, -1, 1 hours, uint96(1_000 * WAD), uint96(1000 * 10**6), 0, 0);
        vm.prank(stableDepositorUniV3Keeper1); StableDepositorUniV3(ilkFunnelInst.stableDepositorUniV3).withdraw(address(dss.dai), USDC, uint24(100), REF_TICK - 100, REF_TICK + 100, 0, 0);

        vm.expectRevert(bytes("NP")); // Reverts since no fees to collect and not because the call is unauthorized
        vm.prank(stableDepositorUniV3Keeper1); StableDepositorUniV3(ilkFunnelInst.stableDepositorUniV3).collect(address(dss.dai), USDC, uint24(100), REF_TICK - 100, REF_TICK + 100);
    }

    function testMoveFromKeeper() public {
        emulateSpell();

        // Note that although the Conduits setup and init were not done by the tested contracts, we are testing the
        // ConduitMover deployment, the facilitators ward on it and the keeper addition to it.

        // Give conduit1 some funds
        deal(USDC, ilkInst.buffer, 3_000 * 10**6, true);
        vm.prank(ilkFunnelInst.conduitMover); AllocatorConduitMock(conduit1).deposit(ILK, USDC, 3_000 * 10**6);

        vm.prank(facilitator1); ConduitMover(ilkFunnelInst.conduitMover).setConfig(conduit1, conduit2, USDC, 1, 1 hours, 3_000 * 10**6);
        vm.prank(conduitMoverKeeper1); ConduitMover(ilkFunnelInst.conduitMover).move(conduit1, conduit2, USDC);
    }

    function testEndCage() public {
        // This test doesn't mean ES is supported, just aims to check that in case of planned governance shutdown is needed, the End could handle well a huge number of ink
        emulateSpell();

        vm.prank(facilitator1); AllocatorVault(ilkInst.vault).draw(1_000_000 * WAD);

        uint256 ink; uint256 art;
        (ink, art) = dss.vat.urns(ILK, address(ilkInst.vault));
        assertEq(ink, 1_000_000_000_000 * WAD);
        assertEq(art, 1_000_000 * WAD);
        assertEq(dss.vat.gem(ILK, address(dss.end)), 0);

        vm.prank(PAUSE_PROXY); dss.end.cage();
        dss.end.cage(ILK);
        assertEq(dss.end.tag(ILK), RAY);
        dss.end.skim(ILK, address(ilkInst.vault));

        (ink, art) = dss.vat.urns(ILK, address(ilkInst.vault));
        assertEq(ink, (1_000_000_000_000 - 1_000_000) * WAD);
        assertEq(art, 0);
        assertEq(dss.vat.gem(ILK, address(dss.end)), 1_000_000 * WAD);

        stdstore.target(address(dss.vat)).sig("dai(address)").with_key(address(dss.vow)).depth(0).checked_write(uint256(0));
        vm.warp(block.timestamp + dss.end.wait());
        dss.end.thaw();

        dss.end.flow(ILK);
        assertEq(dss.end.fix(ILK), 1_000_000 * RAD / (dss.vat.debt() / RAY));
    }
}
