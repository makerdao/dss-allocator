// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Swapper.sol";

contract BufferMock {
    address immutable dai;
    constructor(address _dai) {
        dai = _dai;
    }
    function take(address to, uint256 wad) external {
        GemLike(dai).transfer(to, wad);
    }
    function wipe(uint256 wad) external {
    }
}

contract PipMock {
    function read() external pure returns (bytes32) {
        return bytes32(uint256(1 ether));
    }
}

contract BoxMock {
    uint256 nextWithdrawId;
    struct Withdrawal {
        address token;
        address operator;
        uint256 amount;
    }
    mapping(uint256 => Withdrawal) withdrawals;
    function initiateWithdraw(address token, address operator, uint256 amount) external returns (uint256) {
        withdrawals[nextWithdrawId].token = token;
        withdrawals[nextWithdrawId].operator = operator;
        withdrawals[nextWithdrawId].amount = amount;
        return nextWithdrawId++;
    }
    function completeWithdraw(uint256 withdrawId) external {
        GemLike(withdrawals[withdrawId].token).approve(withdrawals[withdrawId].operator, withdrawals[withdrawId].amount);
        delete withdrawals[withdrawId];
    }

    function deposit(address gem, uint256 wad) external {}
}

contract SwapperTest is Test {
    Swapper public swapper;
    BoxMock public box;

    address constant DAI                = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC               = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNIV3_ROUTER       = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address constant KEEPER = address(0xb0b);

    function setUp() public {
        swapper = new Swapper(DAI, USDC, UNIV3_ROUTER);
        box = new BoxMock();
        address pip = address(new PipMock());
        address buffer = address(new BufferMock(DAI));
        deal(DAI, buffer, 1_000_000_000 ether, true);
        swapper.file("box", address(box), 1);
        swapper.file("buffer", buffer);
        swapper.file("pip", pip);
        swapper.file("fee", 100);
        swapper.file("fee", 100);
        swapper.file("maxIn",  10_000 ether);
        swapper.file("maxOut", 10_000 ether);
        swapper.file("want", 99 ether / 100);
        swapper.kiss(KEEPER);
    }

    function testSwapper() public {

        vm.startPrank(KEEPER); 
        
        uint256 gemOut = swapper.swapIn(10_000 ether);
        console2.log("gemOut:", gemOut * 10**12);
        Swapper.Load[] memory cargo = new Swapper.Load[](1);
        cargo[0].box = address(box);
        cargo[0].wad = gemOut;
        swapper.push(cargo);
        uint256 withdrawId = box.initiateWithdraw(USDC, address(swapper), gemOut);
        box.completeWithdraw(withdrawId);
        swapper.pull(cargo);
        uint256 daiOut = swapper.swapOut(gemOut);
        console2.log("daiOut:", daiOut);

        vm.stopPrank();
    }

}
