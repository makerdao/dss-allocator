// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface BufferLike {
    function take(address to, uint256 wad) external;
    function wipe(uint256 wad) external;
}

interface BoxLike { // aka "Conduit"
    function deposit(address gem, uint256 wad) external;
}

interface GemLike {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

interface PipLike {
    function read() external view returns (bytes32);
}

interface VatLike {
    function live() external view returns (uint256);
}

// https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/SwapRlefter.sol
interface SwapRouterLike {
    function exactInput(ExactInputParams calldata params) external returns (uint256 amountOut);
    function factory() external returns (address factory);

    // https://github.com/Uniswap/v3-periphery/blob/b06959dd01f5999aa93e1dc530fe573c7bb295f6/contracts/interfaces/ISwapRouter.sol#L26
    // https://docs.uniswap.org/protocol/guides/swaps/multihop-swaps#input-parameters
    struct ExactInputParams {
        bytes   path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }
}

// Assume one Swapper per SubDAO
contract Swapper {
    mapping (address => uint256) public wards;
    mapping (address => uint256) public buds;     // whitelisted facilitators
    mapping (address => uint256) public keepers;  // whitelisted keepers
    mapping (address => uint256) public boxes;    // whitelisted conduits
    
    VatLike public vat;
    address public buffer;     // Allocation buffer for this Swapper
    PipLike public pip;        // Reference price oracle in DAI/USDC
    uint256 public hop;        // [seconds] swap cooldown
    uint256 public maxIn;      // [WAD] max amount swapped from dai to gem every hop
    uint256 public maxOut;     // [WAD] max amount swapped from gem to dai every hop
    uint256 public zzz;        // [Timestamp]   Last swap
    uint256 public fee;        // [BPS] UniV3 pool fee
    uint256 public want;       // [WAD]         Relative multiplier of the reference price to insist on in the swap.

    event Rely  (address indexed usr);
    event Deny  (address indexed usr);
    event Kissed(address indexed usr);
    event Dissed(address indexed usr);
    event Permit(address indexed usr);
    event Forbid(address indexed usr);
    event File  (bytes32 indexed what, uint256 data);
    event File  (bytes32 indexed what, address data);
    event File  (bytes32 indexed what, address data, uint256 val);
    event Swap  (address indexed keeper, address indexed from, address indexed to, uint256 wad, uint256 out);
    event Quit  (address indexed usr, uint256 wad);

    struct Load {
        address box;
        uint256 wad; // [WAD]
    }

    constructor(address _vat, address _dai, address _gem, address _uniV3Router) {
        vat = VatLike(_vat);
        dai = _dai;
        gem = _gem;
        uniV3Router = _uniV3Router;

        GemLike(dai).approve(uniV3Router, type(uint256).max);
        GemLike(gem).approve(uniV3Router, type(uint256).max);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "Swapper/not-authorized");
        _;
    }

    // permissionned to whitelisted facilitator
    modifier toll { 
        require(buds[msg.sender] == 1, "Swapper/non-facilitator"); 
        _;
    }

    // permissionned to whitelisted keepers
    modifier keeper { 
        require(keepers[msg.sender] == 1, "Swapper/non-keeper"); 
        _;
    }
    
    address public immutable uniV3Router;
    address public immutable dai;
    address public immutable gem;

    function rely(address usr)   external auth { wards[usr]   = 1; emit Rely(usr); }
    function deny(address usr)   external auth { wards[usr]   = 0; emit Deny(usr); }
    function kiss(address usr)   external auth { buds[usr]    = 1; emit Kissed(usr); }
    function diss(address usr)   external auth { buds[usr]    = 0; emit Dissed(usr); }
    function permit(address usr) external toll { keepers[usr] = 1; emit Permit(usr); }
    function forbid(address usr) external toll { keepers[usr] = 0; emit Forbid(usr); }

    function file(bytes32 what, uint256 data) external auth {
        if      (what == "maxIn")  maxIn  = data;
        else if (what == "maxOut") maxOut = data;
        else if (what == "hop")    hop    = data;
        else if (what == "want")   want   = data;
        else if (what == "fee")    fee    = data;
        else revert("Swapper/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, address data, uint256 val) external auth {
        if (what == "box") boxes[data] = val;
        else revert("Swapper/file-unrecognized-param");
        emit File(what, data, val);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "pip") pip = PipLike(data);
        else if (what == "buffer") buffer = data;
        else revert("Swapper/file-unrecognized-param");
        emit File(what, data);
    }

    function swapIn(uint256 wad) external keeper returns (uint256 out) {
        require(vat.live() == 1, "Swapper/vat-not-live");
        require(block.timestamp >= zzz + hop, "Swapper/too-soon");
        zzz = block.timestamp;

        require(wad <= maxIn, "Swapper/exceeds-max-in");

        BufferLike(buffer).take(address(this), wad);

        bytes memory path = abi.encodePacked(dai, uint24(fee), gem);
        SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
            path:             path,
            recipient:        address(this),
            deadline:         block.timestamp,
            amountIn:         wad,
            // Q: can we assume pip giving DAI price in USDC (or equivalently, USD with USDC = 1$) ?
            // Q: do we want to move the decimal conversion to the pip instead of here?
            amountOutMinimum: uint256(pip.read()) * wad * want / 10**48 // 10**48 = WAD * WAD * 10**12
        });
        out = SwapRouterLike(uniV3Router).exactInput(params);

        emit Swap(msg.sender, dai, gem, wad, out);
    }

    function push(Load[] calldata to) external toll {
        require(vat.live() == 1, "Swapper/vat-not-live");
        for(uint256 i; i < to.length;) {
            (address _to, uint256 _wad) = (to[i].box,  to[i].wad);
            require(boxes[_to] == 1, "Swapper/invalid-destination");
            require(GemLike(gem).transfer(_to, _wad));
            BoxLike(_to).deposit(gem, _wad);
            unchecked { ++i; }
        }
    }

    function pull(Load[] calldata from) external {
        // After ES, we want to allow permissionlessly bring all the gem back
        require(buds[msg.sender] == 1 || vat.live() == 0, "Swapper/non-keeper"); 

        for(uint256 i; i < from.length;) {
            (address _from, uint256 _wad) = (from[i].box,  from[i].wad);
            // require(boxes[_from] == 1, "Swapper/invalid-source");

            // We assume the swapper was set as operator when calling box.initiateWithdrawal() and has
            // subsequently been granted a gem allowance by the box in box.completeWithdrawal()
            require(GemLike(gem).transferFrom(_from, address(this), _wad));
            unchecked { ++i; }
        }
    }

    function swapOut(uint256 wad) external returns (uint256 out) {
        // After ES, we want to allow permissionlessly swap all the gem back to dai and send that dai back to the buffer
        if(vat.live() == 1) {
            require(keepers[msg.sender] == 1, "Swapper/non-keeper"); 
            require(block.timestamp >= zzz + hop, "Swapper/too-soon");
            zzz = block.timestamp;
        }

        require(wad <= maxOut, "Swapper/exceeds-max-out");
        
        bytes memory path = abi.encodePacked(gem, uint24(fee), dai);
        SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
            path:             path,
            recipient:        address(this),
            deadline:         block.timestamp,
            amountIn:         wad,
            // Q: can we assume pip giving DAI price in USDC (or equivalently, in USD with USDC = 1$) ?
            // Q: do we want to move the decimal conversion to the pip instead of here?
            amountOutMinimum: wad * want / uint256(pip.read()) * 10**12
        });
        out = SwapRouterLike(uniV3Router).exactInput(params);

        GemLike(dai).transfer(buffer, out);
        BufferLike(buffer).wipe(out);

        emit Swap(msg.sender, gem, dai, wad, out);
    }

    // After ES, we want to allow permissionlessly bring all the dai back to the buffer
    function quit() external {
        require(vat.live() == 0, "Swapper/vat-still-live");
        uint256 wad = GemLike(dai).balanceOf(address(this));
        GemLike(dai).transfer(buffer, wad);
        emit Quit(msg.sender, wad);
    } 
}
