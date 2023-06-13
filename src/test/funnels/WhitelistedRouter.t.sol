// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "../../funnels/WhitelistedRouter.sol";
import "dss-test/DssTest.sol";

interface BalanceLike {
    function balanceOf(address) external view returns (uint256);
}

interface GemLikeLike {
    function approve(address, uint256) external;
    function transferFrom(address, address, uint256) external;
}

contract BufferMock {
    mapping(address => uint256) public wards;
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Approve(address indexed token, address indexed spender, uint256 value);
    event Deposit(address indexed gem, address indexed sender, uint256 amount);

    modifier auth() {
        require(wards[msg.sender] == 1, "AllocatorBuffer/not-authorized");
        _;
    }
    constructor() {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }
    function approve(
        address token,
        address spender,
        uint256 value
    ) external auth {
        GemLikeLike(token).approve(spender, value);
        emit Approve(token, spender, value);
    }
    function deposit(address gem, uint256 amount, address /* owner */) external {
        GemLikeLike(gem).transferFrom(msg.sender, address(this), amount);
        emit Deposit(gem, msg.sender, amount);
    }
}

contract WhitelistedRouterTest is DssTest {
    WhitelistedRouter public router;
    address public box1;
    address public box2;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant FACILITATOR = address(0xb0b);
    address constant SUBDAO_PROXY = address(0xDA0);

    function setUp() public {
        router = new WhitelistedRouter();
        box1 = address(new BufferMock());
        box2 = address(new BufferMock());
        BufferMock(box1).approve(USDC, address(router), type(uint256).max);
        BufferMock(box2).approve(USDC, address(router), type(uint256).max);
        BufferMock(box1).approve(USDT, address(router), type(uint256).max);
        BufferMock(box2).approve(USDT, address(router), type(uint256).max);
        router.file("box", box1, 1);
        router.file("box", box2, 1);
        router.file("owner", SUBDAO_PROXY);
        router.kiss(FACILITATOR);
    }

    function _checkMove(address gem, uint256 amt) internal {
        deal(gem, box1, amt, true);
        assertEq(BalanceLike(gem).balanceOf(box1), amt);
        assertEq(BalanceLike(gem).balanceOf(box2), 0);
        vm.startPrank(FACILITATOR); 
        
        router.move(gem, box1, box2, amt);

        assertEq(BalanceLike(gem).balanceOf(box1), 0);
        assertEq(BalanceLike(gem).balanceOf(box2), amt);

        router.move(gem, box2, box1, amt);

        assertEq(BalanceLike(gem).balanceOf(box1), amt);
        assertEq(BalanceLike(gem).balanceOf(box2), 0);
        vm.stopPrank();
    }

    function testMoveUSDC() public {
        _checkMove(USDC, 1000 ether);
    }
    function testMoveUSDT() public {
        _checkMove(USDT, 1000 ether);
    }
}
