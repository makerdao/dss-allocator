// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2023 Dai Foundation
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

import { DssTest } from "dss-test/DssTest.sol";

// TODO: merge into DssTest
contract TestUtils is DssTest {
    // TODO: this should replace checkModifier in DssTest
    function checkModifierForLargeArgs(address _base, string memory _revertMsg, bytes4[] memory _fsigs) internal {
        for (uint256 i = 0; i < _fsigs.length; i++) {
            bytes4 fsig = _fsigs[i];
            uint256[] memory p = new uint256[](20);
            // Pad the abi call with 0s to fill all the args (it's okay to supply more than the function requires)
            assertRevert(_base, abi.encodePacked(fsig, p), _revertMsg);
        }
    }
     function checkModifierForLargeArgs(address _base, string memory _revertMsg, bytes4[1] memory _fsigs) internal {
        bytes4[] memory fsigs = new bytes4[](1);
        fsigs[0] = _fsigs[0];
        checkModifier(_base, _revertMsg, fsigs);
    }
    function checkModifierForLargeArgs(address _base, string memory _revertMsg, bytes4[2] memory _fsigs) internal {
        bytes4[] memory fsigs = new bytes4[](2);
        fsigs[0] = _fsigs[0];
        fsigs[1] = _fsigs[1];
        checkModifier(_base, _revertMsg, fsigs);
    }
    function checkModifierForLargeArgs(address _base, string memory _revertMsg, bytes4[3] memory _fsigs) internal {
        bytes4[] memory fsigs = new bytes4[](3);
        fsigs[0] = _fsigs[0];
        fsigs[1] = _fsigs[1];
        fsigs[2] = _fsigs[2];
        checkModifier(_base, _revertMsg, fsigs);
    }
}

