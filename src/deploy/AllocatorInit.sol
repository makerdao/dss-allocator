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

pragma solidity >=0.8.0;

import { DssInstance } from "dss-test/MCD.sol";
import { AllocatorSharedInstance, AllocatorNetworkInstance } from "./AllocatorInstances.sol";

interface WardsLike {
    function wards(address) external view returns (uint256);
    function rely(address) external;
    function deny(address) external;
}

interface RolesLike {
    function setIlkAdmin(bytes32, address) external;
    function setUserRole(bytes32, address, uint8, bool) external;
    function setRoleAction(bytes32, uint8, address, bytes4, bool) external;
}

interface RegistryLike {
    function file(bytes32, bytes32, address) external;
}

interface VaultLike {
    function ilk() external view returns (bytes32);
    function nst() external view returns (address);
    function file(bytes32, address) external;
    function init() external;
    function draw(uint256) external;
    function wipe(uint256) external;
}

interface BufferLike {
    function approve(address, address, uint256) external;
}

interface SwapperLike {
    function swap(address, address, uint256, uint256, address, bytes calldata) external;
}

interface DepositorUniV3Like {
    struct LiquidityParams {
        address gem0;
        address gem1;
        uint24  fee;
        int24   tickLower;
        int24   tickUpper;
        uint128 liquidity;
        uint256 amt0Desired;
        uint256 amt1Desired;
        uint256 amt0Min;
        uint256 amt1Min;
    }

    struct CollectParams {
        address gem0;
        address gem1;
        uint24  fee;
        int24   tickLower;
        int24   tickUpper;
    }

    function deposit(LiquidityParams memory) external returns (uint128, uint256, uint256);
    function withdraw(LiquidityParams memory, bool) external returns (uint256, uint256);
    function collect(CollectParams memory) external returns (uint256, uint256);
}

interface KissLike {
    function kiss(address) external;
}

struct AllocatorConfig {
    uint256 debtCeiling;
    address allocatorProxy;
    uint8 facilitatorRole;
    uint8 automationRole;
    address facilitator;
    address keeper;
    address[] swapGems;
    address[] depositGems;
    bytes32 vaultClKey;
    bytes32 bufferClKey;
}

library AllocatorInit {
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    function switchOwner(address base, address currentOwner, address newOwner) internal {
        if (currentOwner == newOwner) return;
        require(WardsLike(base).wards(currentOwner) == 1, "cAllocatorInit/current-owner-not-authed");
        WardsLike(base).rely(newOwner);
        WardsLike(base).deny(currentOwner);
    }

    // TODO: add to ilk registry?
    // TODO: sanity checks

    function initShared(
        DssInstance memory dss,
        AllocatorSharedInstance memory sharedInstance
    ) internal {
        dss.chainlog.setAddress("ALLOCATOR_ORACLE",   sharedInstance.oracle);
        dss.chainlog.setAddress("ALLOCATOR_ROLES",    sharedInstance.roles);
        dss.chainlog.setAddress("ALLOCATOR_REGISTRY", sharedInstance.registry);
    }

    function initAllocator(
        DssInstance memory dss,
        AllocatorSharedInstance memory sharedInstance,
        AllocatorNetworkInstance memory networkInstance,
        AllocatorConfig memory cfg
    ) internal {
        bytes32 ilk = VaultLike(networkInstance.vault).ilk();

        // Onboard the ilk
        dss.vat.init(ilk);
        dss.jug.init(ilk);

        require(cfg.debtCeiling < WAD, "AllocatorInit/incorrect-ilk-line-precision");
        dss.vat.file(ilk, "line", cfg.debtCeiling * RAD);
        dss.vat.file("Line", dss.vat.Line() + cfg.debtCeiling * RAD);

        dss.spotter.file(ilk, "pip", sharedInstance.oracle);
        dss.spotter.file(ilk, "mat", RAY);
        dss.spotter.poke(ilk);

        // Configure the Registry and Roles contracts
        RolesLike(sharedInstance.roles).setIlkAdmin(ilk, cfg.allocatorProxy);
        RegistryLike(sharedInstance.registry).file(ilk, "buffer", networkInstance.buffer);

        // Onboard the vault
        dss.vat.slip(ilk, networkInstance.vault, int256(1_000_000 * WAD));
        VaultLike(networkInstance.vault).init();
        VaultLike(networkInstance.vault).file("jug", address(dss.jug));

        // Allow vault and funnels to pull funds from the buffer
        BufferLike(networkInstance.buffer).approve(VaultLike(networkInstance.vault).nst(), networkInstance.vault, type(uint256).max);
        for(uint256 i = 0; i < cfg.swapGems.length; i++) {
            BufferLike(networkInstance.buffer).approve(cfg.swapGems[i], networkInstance.swapper, type(uint256).max);
        }
        for(uint256 i = 0; i < cfg.depositGems.length; i++) {
            BufferLike(networkInstance.buffer).approve(cfg.depositGems[i], networkInstance.depositorUniV3, type(uint256).max);
        }

        // Allow the facilitator to operate on the vault and funnels directly
        RolesLike(sharedInstance.roles).setUserRole(ilk, cfg.facilitator, cfg.facilitatorRole, true);

        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, networkInstance.vault,          VaultLike.draw.selector,      true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, networkInstance.vault,          VaultLike.wipe.selector,      true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, networkInstance.swapper,        SwapperLike.swap.selector,    true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, networkInstance.depositorUniV3, DepositorUniV3Like.deposit.selector, true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, networkInstance.depositorUniV3, DepositorUniV3Like.withdraw.selector,true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, networkInstance.depositorUniV3, DepositorUniV3Like.collect.selector, true);

        // Allow the automation contracts to operate on the funnels
        RolesLike(sharedInstance.roles).setUserRole(ilk, networkInstance.stableSwapper,        cfg.automationRole, true);
        RolesLike(sharedInstance.roles).setUserRole(ilk, networkInstance.stableDepositorUniV3, cfg.automationRole, true);

        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.automationRole, networkInstance.swapper,        SwapperLike.swap.selector,    true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.automationRole, networkInstance.depositorUniV3, DepositorUniV3Like.deposit.selector, true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.automationRole, networkInstance.depositorUniV3, DepositorUniV3Like.withdraw.selector,true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.automationRole, networkInstance.depositorUniV3, DepositorUniV3Like.collect.selector, true);

        // Allow facilitator to set configurations in the automation contracts
        WardsLike(networkInstance.stableSwapper).rely(cfg.facilitator);
        WardsLike(networkInstance.stableDepositorUniV3).rely(cfg.facilitator);
        WardsLike(networkInstance.conduitMover).rely(cfg.facilitator);

        // Add keepers to the automation contracts
        KissLike(networkInstance.stableSwapper).kiss(cfg.keeper);
        KissLike(networkInstance.stableDepositorUniV3).kiss(cfg.keeper);
        KissLike(networkInstance.conduitMover).kiss(cfg.keeper);

        // Move ownership of the network contracts to the allocator proxy
        switchOwner(networkInstance.vault,                networkInstance.owner, cfg.allocatorProxy);
        switchOwner(networkInstance.buffer,               networkInstance.owner, cfg.allocatorProxy);
        switchOwner(networkInstance.swapper,              networkInstance.owner, cfg.allocatorProxy);
        switchOwner(networkInstance.depositorUniV3,       networkInstance.owner, cfg.allocatorProxy);
        switchOwner(networkInstance.stableSwapper,        networkInstance.owner, cfg.allocatorProxy);
        switchOwner(networkInstance.stableDepositorUniV3, networkInstance.owner, cfg.allocatorProxy);
        switchOwner(networkInstance.conduitMover,         networkInstance.owner, cfg.allocatorProxy);

        // Add contracts to changelog
        dss.chainlog.setAddress(cfg.vaultClKey, networkInstance.vault);
        dss.chainlog.setAddress(cfg.bufferClKey, networkInstance.buffer);
    }
}
