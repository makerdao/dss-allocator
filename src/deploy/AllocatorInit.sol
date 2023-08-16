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
import { AllocatorSharedInstance, AllocatorCoreInstance, AllocatorFunnelsInstance } from "./AllocatorInstances.sol";

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

struct AllocatorConfig {
    uint256 debtCeiling;
    address allocatorProxy;
}

struct CoreConfig {
    uint8 operatorRole;
    address facilitator;
    address nst;
}

struct FunnelsConfig {
    uint8 operatorRole;
    address facilitator;
    address keeper;
}

library AllocatorInit {
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    uint256 constant RAD = 10 ** 45;

    // TODO: sanity checks
    // TODO: add contracts to changelog
    // TODO: add to ilk registry?

    // Should be called from Pause Proxy
    function initAllocator(
        DssInstance memory dss,
        AllocatorSharedInstance memory sharedInstance,
        AllocatorCoreInstance memory coreInstance,
        AllocatorConfig memory config
    ) internal {

        bytes32 ilk = VaultLike(coreInstance.vault).ilk();
        dss.vat.init(ilk);
        dss.vat.slip(ilk, coreInstance.vault, int256(1_000_000 * WAD));
        dss.jug.init(ilk);

        require(config.debtCeiling < WAD, "AllocatorInit/incorrect-ilk-line-precision");
        dss.vat.file(ilk, "line", config.debtCeiling * RAD);
        dss.vat.file("Line", dss.vat.Line() + config.debtCeiling * RAD);

        dss.spotter.file(ilk, "pip", sharedInstance.oracle);
        dss.spotter.file(ilk, "mat", RAY); // TODO: do we need this?
        dss.spotter.poke(ilk);

        RolesLike(sharedInstance.roles).setIlkAdmin(ilk, config.allocatorProxy);
        RegistryLike(sharedInstance.registry).file(ilk, "buffer", coreInstance.buffer);
    }

    // TODO: sanity checks
    // TODO: make sure it is agreed that only core contracts (vault + buffer) are added to changelog

    // // Should be called from Allocator Proxy
    function initCore(
        DssInstance memory dss,
        AllocatorSharedInstance memory sharedInstance,
        AllocatorCoreInstance memory coreInstance,
        CoreConfig memory config
    ) internal {
        VaultLike(coreInstance.vault).init();
        VaultLike(coreInstance.vault).file("jug", address(dss.jug));
        BufferLike(coreInstance.buffer).approve(config.nst, coreInstance.vault, type(uint256).max);

        bytes32 ilk = VaultLike(coreInstance.vault).ilk();
        RolesLike(sharedInstance.roles).setUserRole(ilk, config.facilitator, config.operatorRole, true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, config.operatorRole, coreInstance.vault, VaultLike.draw.selector, true);
        RolesLike(sharedInstance.roles).setRoleAction(ilk, config.operatorRole, coreInstance.vault, VaultLike.wipe.selector, true);
    }

    // TODO: sanity checks
    // TODO: not that we do not approve NST from the buffer, as it could be any token that we want to swap

    // Should be called from Allocator Proxy
    function initFunnels(
        AllocatorSharedInstance memory sharedInstance,
        AllocatorCoreInstance memory coreInstance,
        AllocatorFunnelsInstance memory funnelsInstance,
        FunnelsConfig memory config
    ) internal {

        bytes32 ilk = VaultLike(coreInstance.vault).ilk();
        RolesLike(sharedInstance.roles).setRoleAction(ilk, config.operatorRole, funnelsInstance.swapper, SwapperLike.swap.selector, true);
        // TODO: same for the depositor

        // TODO: are we fine with the same role ("operatorRole") for different entities (facilitator, stableSwapper...) operating on different contracts (vault, swapper..)?
        RolesLike(sharedInstance.roles).setUserRole(ilk, funnelsInstance.stableSwapper, config.operatorRole, true);
        //RolesLike(sharedInstance.roles).setUserRole(ilk, funnelsInstance.stableDepositor, config.operatorRole, true);

        // TODO: rely facilitator on automation contracts
        // TODO: add keepers to automation contracts
    }
}
