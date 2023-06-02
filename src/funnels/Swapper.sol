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
    
    address public buffer;     // Allocation buffer for this Swapper
    uint256 public hop;        // [seconds] swap cooldown
    uint256 public maxIn;      // [WAD]       Max amount swapped from nst to gem every hop
    uint256 public maxOut;     // [WAD]       Max amount swapped from gem to nst every hop
    uint256 public wantIn;     // [WAD]       Relative multiplier of the reference price (equal to 1 gem/nst) to insist on in the swap from nst to gem.
    uint256 public wantOut;    // [WAD]       Relative multiplier of the reference price (equal to 1 nst/gem) to insist on in the swap from gem to nst.
    uint256 public zzz;        // [Timestamp] Last swap
    uint256 public fee;        // [BPS]       UniV3 pool fee

    uint256[] internal weights;   // Bit vector tightly packing (address(box), uint96(percentage)) tuple entries such that the sum of all percentages = 1 WAD (100%)

    event Rely  (address indexed usr);
    event Deny  (address indexed usr);
    event Kissed(address indexed usr);
    event Dissed(address indexed usr);
    event Permit(address indexed usr);
    event Forbid(address indexed usr);
    event File  (bytes32 indexed what, uint256 data);
    event File  (bytes32 indexed what, address data);
    event File  (bytes32 indexed what, address data, uint256 val);
    event Swap  (address indexed kpr, address indexed from, address indexed to, uint256 wad, uint256 out);
    event Quit  (address indexed usr, uint256 wad);

    struct Weight {
        address box;
        uint96 wad; // percentage in WAD such that 1 WAD = 100%
    }

    constructor(address _nst, address _gem, address _uniV3Router) {
        nst = _nst;
        gem = _gem;
        uniV3Router = _uniV3Router;

        GemLike(nst).approve(uniV3Router, type(uint256).max);
        GemLike(gem).approve(uniV3Router, type(uint256).max);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth {
        require(wards[msg.sender] == 1, "Swapper/not-authorized");
        _;
    }

    // permissionned to whitelisted facilitators
    modifier toll { 
        require(buds[msg.sender] == 1, "Swapper/non-facilitator"); 
        _;
    }

    // permissionned to whitelisted keepers
    modifier keeper { 
        require(keepers[msg.sender] == 1, "Swapper/non-keeper"); 
        _;
    }

    uint256 internal constant WAD = 10 ** 18;

    address public immutable uniV3Router;
    address public immutable nst;
    address public immutable gem;

    function rely(address usr)   external auth { wards[usr]   = 1; emit Rely(usr); }
    function deny(address usr)   external auth { wards[usr]   = 0; emit Deny(usr); }
    function kiss(address usr)   external auth { buds[usr]    = 1; emit Kissed(usr); }
    function diss(address usr)   external auth { buds[usr]    = 0; emit Dissed(usr); }
    function permit(address usr) external toll { keepers[usr] = 1; emit Permit(usr); }
    function forbid(address usr) external toll { keepers[usr] = 0; emit Forbid(usr); }

    function file(bytes32 what, uint256 data) external auth {
        if      (what == "maxIn")   maxIn  = data;
        else if (what == "maxOut")  maxOut = data;
        else if (what == "wantIn")  wantIn = data;
        else if (what == "wantOut") wantOut = data;
        else if (what == "hop")     hop    = data;
        else if (what == "fee")     fee    = data;
        else revert("Swapper/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "buffer") buffer = data;
        else revert("Swapper/file-unrecognized-param");
        emit File(what, data);
    }

    function file(bytes32 what, address data, uint256 val) external auth {
        if (what == "box") boxes[data] = val;
        else revert("Swapper/file-unrecognized-param");
        emit File(what, data, val);
    }

    function setWeights(Weight[] memory newWeights) external toll {
        uint256 cumPct;
        uint256[] memory arr = new uint256[](newWeights.length);
        for(uint256 i; i < newWeights.length;) {
            (address _box, uint256 _pct) = (newWeights[i].box, uint256(newWeights[i].wad));
            require(boxes[_box] == 1, "Swapper/invalid-box");
            require(_pct <= WAD, "Swapper/not-wad-percentage");
            arr[i] = (uint256(uint160(_box)) << 96) | _pct;
            cumPct += _pct;
            unchecked { ++i; }
        }
        require(cumPct == WAD, "Swapper/total-weight-not-wad");
        weights = arr;
    }

    function getWeightAt(uint256 i) public view returns (address box, uint256 percent) {
        uint256 weight = weights[i];
        (box, percent) = (address(uint160(weight >> 96)), weight & (2**96 - 1)); // TODO: check that this tuple assignment results in only one SLOAD
        require(boxes[box] == 1, "Swapper/invalid-box"); // sanity check that any deauthorised box has also been removed from the weights vector
    }

    function getWeightsLength() external view returns (uint256 len) {
        len = weights.length;
    }

    function swapIn(uint256 wad, uint256 min) external keeper returns (uint256 out) {
        require(block.timestamp >= zzz + hop, "Swapper/too-soon");
        zzz = block.timestamp;

        require(wad <= maxIn, "Swapper/wad-too-large");
        require(min >= wad * wantIn / 10**30 , "Swapper/min-too-small"); // 1/10**30 = 1/WAD * 1/10**12

        BufferLike(buffer).take(address(this), wad);

        bytes memory path = abi.encodePacked(nst, uint24(fee), gem);
        SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
            path:             path,
            recipient:        address(this),
            deadline:         block.timestamp,
            amountIn:         wad,
            amountOutMinimum: min
        });
        out = SwapRouterLike(uniV3Router).exactInput(params);

        uint256 pending = out;
        uint256 len = weights.length;
        for(uint256 i; i < len;) {
            (address _to, uint256 _percent) = getWeightAt(i);
            uint256 _amt = (i == len - 1) ? pending : out * _percent / WAD;

            require(GemLike(gem).transfer(_to, _amt));
            BoxLike(_to).deposit(gem, _amt);

            pending -= _amt;
            unchecked { ++i; }
        }

        emit Swap(msg.sender, nst, gem, wad, out);
    }

    function swapOut(uint256 wad, uint256 min) external keeper returns (uint256 out) {

        require(block.timestamp >= zzz + hop, "Swapper/too-soon");
        zzz = block.timestamp;

        require(wad <= maxOut, "Swapper/wad-too-large");
        require(min >= wad * wantOut / 10**6, "Swapper/min-too-small"); // 1/10**6 = 10**12 / WAD
        
        uint256 pending = wad;
        uint256 len = weights.length;
        for(uint256 i; i < len;) {
            (address _from, uint256 _percent) = getWeightAt(i);
            uint256 _amt = (i == len - 1) ? pending : wad * _percent / WAD;

            // We assume the swapper was set as operator when calling box.initiateWithdrawal() and has
            // subsequently been granted a gem allowance by the box in box.completeWithdrawal()
            require(GemLike(gem).transferFrom(_from, address(this), _amt));

            pending -= _amt;
            unchecked { ++i; }
        }

        bytes memory path = abi.encodePacked(gem, uint24(fee), nst);
        SwapRouterLike.ExactInputParams memory params = SwapRouterLike.ExactInputParams({
            path:             path,
            recipient:        address(this),
            deadline:         block.timestamp,
            amountIn:         wad,
            // Q: can we assume pip giving NST price in USDC (or equivalently, in USD with USDC = 1$) ?
            // Q: do we want to move the decimal conversion to the pip instead of here?
            amountOutMinimum: min
        });
        out = SwapRouterLike(uniV3Router).exactInput(params);

        GemLike(nst).transfer(buffer, out);
        BufferLike(buffer).wipe(out);

        emit Swap(msg.sender, gem, nst, wad, out);
    }
}
