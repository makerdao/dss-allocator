// AllocatorOracle.spec

methods {
    function peek() external returns (bytes32, bool) envfree;
    function read() external returns (bytes32) envfree;
}

// Verify correct response from peek
rule peek() {
    bytes32 val;
    bool ok;
    val, ok = peek();

    assert val == to_bytes32(10^6 * 10^18), "peek did not return the expected val result";
    assert ok, "peek did not return the expected ok result";
}

// Verify correct response from read
rule read() {
    bytes32 val = read();

    assert val == to_bytes32(10^6 * 10^18), "read did not return the expected result";
}
