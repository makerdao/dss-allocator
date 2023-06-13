// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

contract AuthedMock {
    address public roles;
    bool public flag1;
    bool public flag2;

    constructor(address roles_) {
        roles = roles_;
    }

    modifier auth() {
        address roles_ = roles;
        bool access;
        if (roles_ != address(0)) {
            (bool ok, bytes memory ret) = roles_.call(
                                            abi.encodeWithSignature(
                                                "canCall(address,address,bytes4)",
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

    function cap1() public auth {
		flag1 = true;
	}

	function cap2() public auth {
		flag2 = true;
	}
}
