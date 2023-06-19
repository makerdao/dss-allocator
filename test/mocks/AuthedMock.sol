// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

contract AuthedMock {
    address public roles;
    bool public flag;

    bytes32 public immutable ilk;

    constructor(address roles_, bytes32 ilk_) {
        roles = roles_;
        ilk = ilk_;
    }

    modifier auth() {
        address roles_ = roles;
        bool access;
        if (roles_ != address(0)) {
            (bool ok, bytes memory ret) = roles_.call(
                                            abi.encodeWithSignature(
                                                "canCall(bytes32,address,address,bytes4)",
                                                ilk,
                                                msg.sender,
                                                address(this),
                                                msg.sig
                                            )
            );
            access = ok && ret.length == 32 && abi.decode(ret, (bool));
        }
        require(access, "AuthedMock/not-authorized");
        _;
    }

    function exec() public auth {
        flag = true;
    }
}
