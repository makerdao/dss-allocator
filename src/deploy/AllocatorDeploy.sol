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

import { ScriptTools } from "dss-test/ScriptTools.sol";

import { AllocatorOracle }      from "src/AllocatorOracle.sol";
import { AllocatorRoles }       from "src/AllocatorRoles.sol";
import { AllocatorRegistry }    from "src/AllocatorRegistry.sol";
import { AllocatorBuffer }      from "src/AllocatorBuffer.sol";
import { AllocatorVault }       from "src/AllocatorVault.sol";
import { Swapper }              from "src/funnels/Swapper.sol";
import { DepositorUniV3 }       from "src/funnels/DepositorUniV3.sol";
import { StableSwapper }        from "src/funnels/automation/StableSwapper.sol";
import { StableDepositorUniV3 } from "src/funnels/automation/StableDepositorUniV3.sol";

import { AllocatorSharedInstance, AllocatorNetworkInstance } from "./AllocatorInstances.sol";

library AllocatorDeploy {

    // Note: owner is assumed to be the pause proxy
    function deployShared(
        address deployer,
        address owner
    ) internal returns (AllocatorSharedInstance memory sharedInstance) {
        address _oracle = address(new AllocatorOracle());

        address _roles  = address(new AllocatorRoles());
        ScriptTools.switchOwner(_roles, deployer, owner);

        address _registry = address(new AllocatorRegistry());
        ScriptTools.switchOwner(_registry, deployer, owner);

        sharedInstance.oracle   = _oracle;
        sharedInstance.roles    = _roles;
        sharedInstance.registry = _registry;
    }

    // Note: owner is assumed to be the pause proxy, allocatorProxy will receive ownerships on init
    function deployNetwork(
        address deployer,
        address owner,
        address roles,
        address vat,
        bytes32 ilk,
        address nstJoin,
        address buffer,
        address uniV3Factory
    ) internal returns (AllocatorNetworkInstance memory networkInstance) {
        address _buffer = address(new AllocatorBuffer());
        ScriptTools.switchOwner(_buffer, deployer, owner);

        address _vault  = address(new AllocatorVault(roles, _buffer, vat, ilk, nstJoin));
        ScriptTools.switchOwner(_vault, deployer, owner);

        address _swapper = address(new Swapper(roles, ilk, buffer));
        ScriptTools.switchOwner(_swapper, deployer, owner);

        address _depositorUniV3 = address(new DepositorUniV3(roles, ilk, uniV3Factory, buffer));
        ScriptTools.switchOwner(_depositorUniV3, deployer, owner);

        address _stableSwapper = address(new StableSwapper(_swapper));
        ScriptTools.switchOwner(_stableSwapper, deployer, owner);

        address _stableDepositorUniV3 = address(new StableDepositorUniV3(_depositorUniV3));
        ScriptTools.switchOwner(_stableDepositorUniV3, deployer, owner);

        networkInstance.owner                = owner;
        networkInstance.vault                = _vault;
        networkInstance.buffer               = _buffer;
        networkInstance.swapper              = _swapper;
        networkInstance.depositorUniV3       = _depositorUniV3;
        networkInstance.stableSwapper        = _stableSwapper;
        networkInstance.stableDepositorUniV3 = _stableDepositorUniV3;
    }
}
