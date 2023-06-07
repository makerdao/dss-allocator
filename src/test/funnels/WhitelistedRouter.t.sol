// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "../../funnels/WhitelistedRouter.sol";
import "../../funnels/Escrow.sol";
import "dss-test/DssTest.sol";

interface TokenLike {
    function balanceOf(address) external view returns (uint256);
}

contract ConduitMock {
    mapping(address => uint256) public wards;
    mapping(uint256 => Withdrawal) withdrawals;
    mapping(address => uint256) deposits;
    uint256 nextWithdrawId;
    struct Withdrawal {
        address owner;
        uint256 amount;
    }
    address immutable gem;
    modifier auth() { require(wards[msg.sender] == 1, "ConduitMock/not-authorized"); _; }
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    constructor(address _gem) {
        gem = _gem;
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }
    function isCancelable(uint256 withdrawalId) external view returns (bool) { return withdrawals[withdrawalId].owner != address(0); }
    function initiateWithdraw(address owner, uint256 amount) external auth returns (uint256) {
        deposits[owner] -= amount;
        withdrawals[nextWithdrawId].owner = owner;
        withdrawals[nextWithdrawId].amount = amount;
        return nextWithdrawId++;
    }
    function cancelWithdraw(uint256 withdrawalId) external auth {
        (address owner, uint256 amount) = (withdrawals[withdrawalId].owner, withdrawals[withdrawalId].amount);
        require(owner != address(0));
        delete withdrawals[withdrawalId];
        deposits[owner] += amount;
    }
    function withdraw(uint256 withdrawId) external auth returns (uint256) {
        ApproveLike(gem).approve(msg.sender, withdrawals[withdrawId].amount);
        delete withdrawals[withdrawId];
        return 0;
    }
    function moved(address owner, uint256 amount) external auth {
        deposits[owner] += amount;
    }
}

contract WhitelistedRouterTest is DssTest {
    WhitelistedRouter public router;
    address public escrow;
    address public conduit;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant FACILITATOR = address(0xb0b);

    function setUp() public {
        router = new WhitelistedRouter(USDC);
        escrow = address(new Escrow());
        Escrow(escrow).approve(USDC, address(router), type(uint256).max);
        conduit = address(new ConduitMock(USDC));
        ConduitMock(conduit).rely(address(router));

        router.file("box", escrow, 1);
        router.file("box", conduit, 1);
        router.file("owner", address(this));
        router.kiss(FACILITATOR);
    }

    function testTransferFrom() public {
        uint256 amt = 1000 ether;
        deal(USDC, escrow, amt, true);
        assertEq(TokenLike(USDC).balanceOf(escrow), amt);
        assertEq(TokenLike(USDC).balanceOf(conduit), 0);
        vm.startPrank(FACILITATOR); 
        
        bool ack = router.transferFrom(escrow, conduit, amt);

        assertEq(ack, true);
        assertEq(TokenLike(USDC).balanceOf(escrow), 0);
        assertEq(TokenLike(USDC).balanceOf(conduit), amt);

        uint256 id = router.initiateWithdraw(conduit, amt);
        router.cancelWithdraw(conduit, id);
        uint256 newId = router.initiateWithdraw(conduit, amt);
        router.withdraw(conduit, newId);

        ack = router.transferFrom(conduit, escrow, amt);

        assertEq(ack, false);
        assertEq(TokenLike(USDC).balanceOf(escrow), amt);
        assertEq(TokenLike(USDC).balanceOf(conduit), 0);
    }

}
