    // SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Dai Foundation
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

import { AuthLike, DssTest, GodMode } from "dss-test/DssTest.sol";

interface FileLike is AuthLike {
    function file(bytes32, address, address, uint256) external;
    function file(bytes32, address, address, uint128, uint128) external;
}

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

    event File(bytes32 indexed what, address indexed gem0, address indexed gem1, uint256 data);
    event File(bytes32 indexed what, address indexed gem0, address indexed gem1, uint128 data0, uint128 data1);
    
    /// @dev This is forge-only due to event checking
    function checkFileUintForGemPair(address _base, string memory _contractName, string[] memory _values) internal {
        address gem0 = address(111);
        address gem1 = address(222);

        FileLike base = FileLike(_base);
        uint256 ward = base.wards(address(this));

        // Ensure we have admin access
        GodMode.setWard(_base, address(this), 1);

        // First check an invalid value
        vm.expectRevert(abi.encodePacked(_contractName, "/file-unrecognized-param"));
        base.file("an invalid value", gem0, gem1, 1);

        // Next check each value is valid and updates the target storage slot
        for (uint256 i = 0; i < _values.length; i++) {
            string memory value = _values[i];
            bytes32 valueB32;
            assembly {
                valueB32 := mload(add(value, 32))
            }

            // Read original value
            (bool success, bytes memory result) = _base.call(abi.encodeWithSignature(string(abi.encodePacked(value, "s(address,address)")), gem0, gem1));
            assertTrue(success);
            uint256 origData = abi.decode(result, (uint256));
            uint256 newData;
            unchecked {
                newData = origData + 1;   // Overflow is fine
            }

            // Update value
            vm.expectEmit(true, true, true, true);
            emit File(valueB32, gem0, gem1, newData);
            base.file(valueB32, gem0, gem1, newData);

            // Confirm it was updated successfully
            (success, result) = _base.call(abi.encodeWithSignature(string(abi.encodePacked(value, "s(address,address)")), gem0, gem1));
            assertTrue(success);
            uint256 data = abi.decode(result, (uint256));
            assertEq(data, newData);

            // Reset value to original
            vm.expectEmit(true, true, true, true);
            emit File(valueB32, gem0, gem1, origData);
            base.file(valueB32, gem0, gem1, origData);
        }

        // Finally check that file is authed
        base.deny(address(this));
        vm.expectRevert(abi.encodePacked(_contractName, "/not-authorized"));
        base.file("some value", gem0, gem1, 1);

        // Reset admin access to what it was
        GodMode.setWard(_base, address(this), ward);
    }

    function checkFileUintForGemPair(address _base, string memory _contractName, string[1] memory _values) internal {
        string[] memory values = new string[](1);
        values[0] = _values[0];
        checkFileUintForGemPair(_base, _contractName, values);
    }

    function checkFileUintForGemPair(address _base, string memory _contractName, string[2] memory _values) internal {
        string[] memory values = new string[](2);
        values[0] = _values[0];
        values[1] = _values[1];
        checkFileUintForGemPair(_base, _contractName, values);
    }

    struct Uint128Pair {
        uint128 data0;
        uint128 data1;
    }

     /// @dev This is forge-only due to event checking
    function checkFileUint128PairForGemPair(address _base, string memory _contractName, string[] memory _values) internal {
        address gem0 = address(111);
        address gem1 = address(222);

        FileLike base = FileLike(_base);
        uint256 ward = base.wards(address(this));

        // Ensure we have admin access
        GodMode.setWard(_base, address(this), 1);

        // First check an invalid value
        vm.expectRevert(abi.encodePacked(_contractName, "/file-unrecognized-param"));
        base.file("an invalid value", gem0, gem1, 111, 222);

        // Next check each value is valid and updates the target storage slot
        for (uint256 i = 0; i < _values.length; i++) {
            string memory value = _values[i];
            bytes32 valueB32;
            assembly {
                valueB32 := mload(add(value, 32))
            }

            // Read original value
            (bool success, bytes memory result) = _base.call(abi.encodeWithSignature(string(abi.encodePacked(value, "s(address,address)")), gem0, gem1));
            assertTrue(success);
            (Uint128Pair memory origData) = abi.decode(result, (Uint128Pair));
            Uint128Pair memory newData;
            unchecked {
                (newData.data0, newData.data1) = (origData.data0 + 1, origData.data1 + 1);   // Overflow is fine
            }

            // Update value
            vm.expectEmit(true, true, true, true);
            emit File(valueB32, gem0, gem1, newData.data0, newData.data1);
            base.file(valueB32, gem0, gem1, newData.data0, newData.data1);

            // Confirm it was updated successfully
            (success, result) = _base.call(abi.encodeWithSignature(string(abi.encodePacked(value, "s(address,address)")), gem0, gem1));
            assertTrue(success);
            (Uint128Pair memory data) = abi.decode(result, (Uint128Pair));
            assertEq(data.data0, newData.data0);
            assertEq(data.data1, newData.data1);

            // Reset value to original
            vm.expectEmit(true, true, true, true);
            emit File(valueB32, gem0, gem1, origData.data0, origData.data1);
            base.file(valueB32, gem0, gem1, origData.data0, origData.data1);
        }

        // Finally check that file is authed
        base.deny(address(this));
        vm.expectRevert(abi.encodePacked(_contractName, "/not-authorized"));
        base.file("some value", gem0, gem1, 111, 222);

        // Reset admin access to what it was
        GodMode.setWard(_base, address(this), ward);
    }

    function checkFileUint128PairForGemPair(address _base, string memory _contractName, string[1] memory _values) internal {
        string[] memory values = new string[](1);
        values[0] = _values[0];
        checkFileUint128PairForGemPair(_base, _contractName, values);
    }

    function checkFileUint128PairForGemPair(address _base, string memory _contractName, string[2] memory _values) internal {
        string[] memory values = new string[](2);
        values[0] = _values[0];
        values[1] = _values[1];
        checkFileUint128PairForGemPair(_base, _contractName, values);
    }
}
