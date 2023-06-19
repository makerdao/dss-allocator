// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

interface RolesLike {
    function canCall(bytes32, address, address, bytes4) external view returns (bool);
}

contract AuthedMock {
    bool public flag;

    RolesLike public immutable roles;
    bytes32 public immutable ilk;

    constructor(address roles_, bytes32 ilk_) {
        roles = RolesLike(roles_);
        ilk = ilk_;
    }

    modifier auth() {
        require(roles.canCall(ilk, msg.sender, address(this), msg.sig), "AuthedMock/not-authorized");
        _;
    }

    function exec() public auth {
        flag = true;
    }
}
