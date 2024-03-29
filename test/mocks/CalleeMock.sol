// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external;
}

contract CalleeMock {
    uint256 random;

    function swapCallback(address, address dst, uint256, uint256, address, bytes calldata) external {
        GemLike(dst).transfer(msg.sender, GemLike(dst).balanceOf(address(this)));
    }
}
