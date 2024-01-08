// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

contract RolesMock {
    bool ok;

    function setOk(bool ok_) external {
        ok = ok_;
    }

    function canCall(bytes32, address, address, bytes4) external view returns (bool) {
        return ok;
    }
}
