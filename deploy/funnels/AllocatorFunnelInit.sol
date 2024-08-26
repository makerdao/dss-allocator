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

import { AllocatorSharedInstance, AllocatorIlkInstance } from "deploy/AllocatorInstances.sol";
import { AllocatorIlkFunnelInstance } from "./AllocatorFunnelInstance.sol";

interface WardsLike {
    function rely(address) external;
}

interface RolesLike {
    function setUserRole(bytes32, address, uint8, bool) external;
    function setRoleAction(bytes32, uint8, address, bytes4, bool) external;
}

interface VaultLike {
    function draw(uint256) external;
    function wipe(uint256) external;
}

interface BufferLike {
    function approve(address, address, uint256) external;
}

interface SwapperLike {
    function roles() external view returns (address);
    function ilk() external view returns (bytes32);
    function buffer() external view returns (address);
    function swap(address, address, uint256, uint256, address, bytes calldata) external returns (uint256);
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

    function roles() external view returns (address);
    function ilk() external view returns (bytes32);
    function uniV3Factory() external view returns (address);
    function buffer() external view returns (address);
    function deposit(LiquidityParams memory) external returns (uint128, uint256, uint256);
    function withdraw(LiquidityParams memory, bool) external returns (uint128, uint256, uint256, uint256, uint256);
    function collect(CollectParams memory) external returns (uint256, uint256);
}

interface VaultMinterLike {
    function vault() external view returns (address);
}

interface StableSwapperLike {
    function swapper() external view returns (address);
}

interface StableDepositorUniV3Like {
    function depositor() external view returns (address);
}

interface ConduitMoverLike {
    function ilk() external view returns (bytes32);
    function buffer() external view returns (address);
}

interface KissLike {
    function kiss(address) external;
}

struct AllocatorIlkFunnelConfig {
    bytes32 ilk;
    address allocatorProxy;
    uint8 facilitatorRole;
    uint8 automationRole;
    address[] facilitators;
    address[] vaultMinterKeepers;
    address[] stableSwapperKeepers;
    address[] stableDepositorUniV3Keepers;
    address[] conduitMoverKeepers;
    address[] swapTokens;
    address[] depositTokens;
    address uniV3Factory;
}

library AllocatorFunnelInit {

    // Please note this should be executed by the allocator proxy
    function initIlkFunnel(
        AllocatorSharedInstance memory sharedInstance,
        AllocatorIlkInstance memory ilkInstance,
        AllocatorIlkFunnelInstance memory ilkFunnelInstance,
        AllocatorIlkFunnelConfig memory cfg
    ) internal {
        bytes32 ilk = cfg.ilk;

        require(SwapperLike(ilkFunnelInstance.swapper).roles()  == sharedInstance.roles, "AllocatorInit/swapper-roles-mismatch");
        require(SwapperLike(ilkFunnelInstance.swapper).ilk()    == ilk,                  "AllocatorInit/swapper-ilk-mismatch");
        require(SwapperLike(ilkFunnelInstance.swapper).buffer() == ilkInstance.buffer,   "AllocatorInit/swapper-buffer-mismatch");

        require(DepositorUniV3Like(ilkFunnelInstance.depositorUniV3).roles()        == sharedInstance.roles, "AllocatorInit/depositorUniV3-roles-mismatch");
        require(DepositorUniV3Like(ilkFunnelInstance.depositorUniV3).ilk()          == ilk,                  "AllocatorInit/depositorUniV3-ilk-mismatch");
        require(DepositorUniV3Like(ilkFunnelInstance.depositorUniV3).uniV3Factory() == cfg.uniV3Factory,     "AllocatorInit/depositorUniV3-uniV3Factory-mismatch");
        require(DepositorUniV3Like(ilkFunnelInstance.depositorUniV3).buffer()       == ilkInstance.buffer,   "AllocatorInit/depositorUniV3-buffer-mismatch");

        require(VaultMinterLike(ilkFunnelInstance.vaultMinter).vault() == ilkInstance.vault, "AllocatorInit/vaultMinter-vault-mismatch");

        require(StableSwapperLike(ilkFunnelInstance.stableSwapper).swapper()                 == ilkFunnelInstance.swapper,        "AllocatorInit/stableSwapper-swapper-mismatch");
        require(StableDepositorUniV3Like(ilkFunnelInstance.stableDepositorUniV3).depositor() == ilkFunnelInstance.depositorUniV3, "AllocatorInit/stableDepositorUniV3-depositorUniV3-mismatch");

        require(ConduitMoverLike(ilkFunnelInstance.conduitMover).ilk()    == ilk,                "AllocatorInit/conduitMover-ilk-mismatch");
        require(ConduitMoverLike(ilkFunnelInstance.conduitMover).buffer() == ilkInstance.buffer, "AllocatorInit/conduitMover-buffer-mismatch");

        // Allow vault and funnels to pull funds from the buffer
        for(uint256 i = 0; i < cfg.swapTokens.length; i++) {
            BufferLike(ilkInstance.buffer).approve(cfg.swapTokens[i], ilkFunnelInstance.swapper, type(uint256).max);
        }
        for(uint256 i = 0; i < cfg.depositTokens.length; i++) {
            BufferLike(ilkInstance.buffer).approve(cfg.depositTokens[i], ilkFunnelInstance.depositorUniV3, type(uint256).max);
        }

        // Allow the facilitators to operate on the vault and funnels directly
        for(uint256 i = 0; i < cfg.facilitators.length; i++) {
            RolesLike(sharedInstance.roles).setUserRole(ilk, cfg.facilitators[i], cfg.facilitatorRole, true);
        }

        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, ilkInstance.vault,                VaultLike.draw.selector,              true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, ilkInstance.vault,                VaultLike.wipe.selector,              true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, ilkFunnelInstance.swapper,        SwapperLike.swap.selector,            true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, ilkFunnelInstance.depositorUniV3, DepositorUniV3Like.deposit.selector,  true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, ilkFunnelInstance.depositorUniV3, DepositorUniV3Like.withdraw.selector, true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.facilitatorRole, ilkFunnelInstance.depositorUniV3, DepositorUniV3Like.collect.selector,  true);

        // Allow the automation contracts to operate on the funnels
        RolesLike(sharedInstance.roles).setUserRole(ilk, ilkFunnelInstance.vaultMinter,          cfg.automationRole, true);
        RolesLike(sharedInstance.roles).setUserRole(ilk, ilkFunnelInstance.stableSwapper,        cfg.automationRole, true);
        RolesLike(sharedInstance.roles).setUserRole(ilk, ilkFunnelInstance.stableDepositorUniV3, cfg.automationRole, true);

        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.automationRole, ilkInstance.vault,                VaultLike.draw.selector,              true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.automationRole, ilkInstance.vault,                VaultLike.wipe.selector,              true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.automationRole, ilkFunnelInstance.swapper,        SwapperLike.swap.selector,            true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.automationRole, ilkFunnelInstance.depositorUniV3, DepositorUniV3Like.deposit.selector,  true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.automationRole, ilkFunnelInstance.depositorUniV3, DepositorUniV3Like.withdraw.selector, true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, cfg.automationRole, ilkFunnelInstance.depositorUniV3, DepositorUniV3Like.collect.selector,  true);

        // Allow facilitator to set configurations in the automation contracts
        for(uint256 i = 0; i < cfg.facilitators.length; i++) {
            WardsLike(ilkFunnelInstance.vaultMinter).rely(cfg.facilitators[i]);
            WardsLike(ilkFunnelInstance.stableSwapper).rely(cfg.facilitators[i]);
            WardsLike(ilkFunnelInstance.stableDepositorUniV3).rely(cfg.facilitators[i]);
            WardsLike(ilkFunnelInstance.conduitMover).rely(cfg.facilitators[i]);
        }

        // Add keepers to the automation contracts
        for(uint256 i = 0; i < cfg.vaultMinterKeepers.length; i++) {
            KissLike(ilkFunnelInstance.vaultMinter).kiss(cfg.vaultMinterKeepers[i]);
        }
        for(uint256 i = 0; i < cfg.stableSwapperKeepers.length; i++) {
            KissLike(ilkFunnelInstance.stableSwapper).kiss(cfg.stableSwapperKeepers[i]);
        }
        for(uint256 i = 0; i < cfg.stableDepositorUniV3Keepers.length; i++) {
            KissLike(ilkFunnelInstance.stableDepositorUniV3).kiss(cfg.stableDepositorUniV3Keepers[i]);
        }
        for(uint256 i = 0; i < cfg.conduitMoverKeepers.length; i++) {
            KissLike(ilkFunnelInstance.conduitMover).kiss(cfg.conduitMoverKeepers[i]);
        }
    }
}
