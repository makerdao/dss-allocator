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
import { VaultMinter }          from "src/funnels/automation/VaultMinter.sol";
import { StableSwapper }        from "src/funnels/automation/StableSwapper.sol";
import { StableDepositorUniV3 } from "src/funnels/automation/StableDepositorUniV3.sol";
import { ConduitMover }         from "src/funnels/automation/ConduitMover.sol";

import { AllocatorSharedInstance, AllocatorIlkInstance, AllocatorIlkFunnelInstance } from "./AllocatorInstances.sol";


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

    // Note: owner is assumed to be the pause proxy, allocator proxy will receive ownerships on init
    function deployIlk(
        address deployer,
        address owner,
        address roles,
        bytes32 ilk,
        address nstJoin
    ) internal returns (AllocatorIlkInstance memory ilkInstance) {
        address _buffer = address(new AllocatorBuffer());
        ScriptTools.switchOwner(_buffer, deployer, owner);
        ilkInstance.buffer = _buffer;

        address _vault  = address(new AllocatorVault(roles, _buffer, ilk, nstJoin));
        ScriptTools.switchOwner(_vault, deployer, owner);
        ilkInstance.vault = _vault;

        ilkInstance.owner = owner;
    }

    // Note: owner is assumed to be the allocator proxy
    function deployIlkFunnel(
        address deployer,
        address owner,
        address roles,
        bytes32 ilk,
        address uniV3Factory,
        address vault,
        address buffer
    ) internal returns (AllocatorIlkFunnelInstance memory ilkFunnelInstance) {
        address _swapper = address(new Swapper(roles, ilk, buffer));
        ScriptTools.switchOwner(_swapper, deployer, owner);
        ilkFunnelInstance.swapper = _swapper;

        address _depositorUniV3 = address(new DepositorUniV3(roles, ilk, uniV3Factory, buffer));
        ScriptTools.switchOwner(_depositorUniV3, deployer, owner);
        ilkFunnelInstance.depositorUniV3 = _depositorUniV3;

        {
        address _vaultMinter = address(new VaultMinter(vault));
        ScriptTools.switchOwner(_vaultMinter, deployer, owner);
        ilkFunnelInstance.vaultMinter = _vaultMinter;
        }

        {
        address _stableSwapper = address(new StableSwapper(_swapper));
        ScriptTools.switchOwner(_stableSwapper, deployer, owner);
        ilkFunnelInstance.stableSwapper = _stableSwapper;
        }

        {
        address _stableDepositorUniV3 = address(new StableDepositorUniV3(_depositorUniV3));
        ScriptTools.switchOwner(_stableDepositorUniV3, deployer, owner);
        ilkFunnelInstance.stableDepositorUniV3 = _stableDepositorUniV3;
        }

        {
        address _conduitMover = address(new ConduitMover(ilk, buffer));
        ScriptTools.switchOwner(_conduitMover, deployer, owner);
        ilkFunnelInstance.conduitMover = _conduitMover;
        }

        ilkFunnelInstance.owner = owner;
    }
}
