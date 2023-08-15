// AllocatorRoles.spec

methods {
    function wards(address) external returns (uint256) envfree;
    function ilkAdmins(bytes32) external returns (address) envfree;
    function userRoles(bytes32, address) external returns (bytes32) envfree;
    function actionsRoles(bytes32, address, bytes4) external returns (bytes32) envfree;
    function hasUserRole(bytes32, address, uint8) external returns (bool) envfree;
    function hasActionRole(bytes32, address, bytes4, uint8) external returns (bool) envfree;
    function canCall(bytes32, address, address, bytes4) external returns (bool) envfree;
}

definition bitNot(uint256 input) returns uint256 = input xor max_uint256;

// Verify correct response from hasUserRole
rule hasUserRole(bytes32 ilk, address who, uint8 role) {
    bool ok = userRoles(ilk, who) & to_bytes32(assert_uint256(2^role)) != to_bytes32(0);

    bool ok2 = hasUserRole(ilk, who, role);

    assert ok2 == ok, "hasUserRole did not return the expected result";
}

// Verify correct response from hasActionRole
rule hasActionRole(bytes32 ilk, address target, bytes4 sign, uint8 role) {
    bool ok = actionsRoles(ilk, target, sign) & to_bytes32(assert_uint256(2^role)) != to_bytes32(0);

    bool ok2 = hasActionRole(ilk, target, sign, role);

    assert ok2 == ok, "hasActionRole did not return the expected result";
}

// Verify correct storage changes for non reverting rely
rule rely(address usr) {
    env e;

    address other;
    require other != usr;
    bytes32 anyBytes32;
    address anyAddr;
    bytes4  anyBytes4;

    mathint wardsOtherBefore = wards(other);
    address ilkAdminsBefore = ilkAdmins(anyBytes32);
    bytes32 userRolesBefore = userRoles(anyBytes32, anyAddr);
    bytes32 actionsRolesBefore = actionsRoles(anyBytes32, anyAddr, anyBytes4);

    rely(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    address ilkAdminsAfter = ilkAdmins(anyBytes32);
    bytes32 userRolesAfter = userRoles(anyBytes32, anyAddr);
    bytes32 actionsRolesAfter = actionsRoles(anyBytes32, anyAddr, anyBytes4);

    assert wardsUsrAfter == 1, "rely did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "rely did not keep unchanged the rest of wards[x]";
    assert ilkAdminsAfter == ilkAdminsBefore, "rely did not keep unchanged every ilkAdmins[x]";
    assert userRolesAfter == userRolesBefore, "rely did not keep unchanged every userRoles[x][y]";
    assert actionsRolesAfter == actionsRolesBefore, "rely did not keep unchanged every actionsRoles[x][y][z]";
}

// Verify revert rules on rely
rule rely_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    rely@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting deny
rule deny(address usr) {
    env e;

    address other;
    require other != usr;
    bytes32 anyBytes32;
    address anyAddr;
    bytes4  anyBytes4;

    mathint wardsOtherBefore = wards(other);
    address ilkAdminsBefore = ilkAdmins(anyBytes32);
    bytes32 userRolesBefore = userRoles(anyBytes32, anyAddr);
    bytes32 actionsRolesBefore = actionsRoles(anyBytes32, anyAddr, anyBytes4);

    deny(e, usr);

    mathint wardsUsrAfter = wards(usr);
    mathint wardsOtherAfter = wards(other);
    address ilkAdminsAfter = ilkAdmins(anyBytes32);
    bytes32 userRolesAfter = userRoles(anyBytes32, anyAddr);
    bytes32 actionsRolesAfter = actionsRoles(anyBytes32, anyAddr, anyBytes4);

    assert wardsUsrAfter == 0, "deny did not set the wards";
    assert wardsOtherAfter == wardsOtherBefore, "deny did not keep unchanged the rest of wards[x]";
    assert ilkAdminsAfter == ilkAdminsBefore, "deny did not keep unchanged every ilkAdmins[x]";
    assert userRolesAfter == userRolesBefore, "deny did not keep unchanged every userRoles[x][y]";
    assert actionsRolesAfter == actionsRolesBefore, "deny did not keep unchanged every actionsRoles[x][y][z]";
}

// Verify revert rules on deny
rule deny_revert(address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    deny@withrevert(e, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting setIlkAdmin
rule setIlkAdmin(bytes32 ilk, address usr) {
    env e;

    bytes32 otherBytes32;
    require otherBytes32 != ilk;
    bytes32 anyBytes32;
    address anyAddr;
    bytes4  anyBytes4;

    mathint wardsBefore = wards(anyAddr);
    address ilkAdminsOtherBefore = ilkAdmins(otherBytes32);
    bytes32 userRolesBefore = userRoles(anyBytes32, anyAddr);
    bytes32 actionsRolesBefore = actionsRoles(anyBytes32, anyAddr, anyBytes4);

    setIlkAdmin(e, ilk, usr);

    mathint wardsAfter = wards(anyAddr);
    address ilkAdminsIlkAfter = ilkAdmins(ilk);
    address ilkAdminsOtherAfter = ilkAdmins(otherBytes32);
    bytes32 userRolesAfter = userRoles(anyBytes32, anyAddr);
    bytes32 actionsRolesAfter = actionsRoles(anyBytes32, anyAddr, anyBytes4);

    assert wardsAfter == wardsBefore, "setIlkAdmin did not keep unchanged every wards[x]";
    assert ilkAdminsIlkAfter == usr, "setIlkAdmin did not set ilkAdmins[ilk] to usr";
    assert ilkAdminsOtherAfter == ilkAdminsOtherBefore, "setIlkAdmin did not keep unchanged the rest of ilkAdmins[x]";
    assert userRolesAfter == userRolesBefore, "setIlkAdmin did not keep unchanged every userRoles[x][y]";
    assert actionsRolesAfter == actionsRolesBefore, "setIlkAdmin did not keep unchanged every actionsRoles[x][y][z]";
}

// Verify revert rules on setIlkAdmin
rule setIlkAdmin_revert(bytes32 ilk, address usr) {
    env e;

    mathint wardsSender = wards(e.msg.sender);

    setIlkAdmin@withrevert(e, ilk, usr);

    bool revert1 = e.msg.value > 0;
    bool revert2 = wardsSender != 1;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting setUserRole
rule setUserRole(bytes32 ilk, address who, uint8 role, bool enabled) {
    env e;

    bytes32 otherBytes32;
    address otherAddr;
    require otherBytes32 != ilk || otherAddr != who;
    bytes32 anyBytes32;
    address anyAddr;
    bytes4  anyBytes4;

    mathint wardsBefore = wards(anyAddr);
    address ilkAdminsBefore = ilkAdmins(anyBytes32);
    bytes32 userRolesIlkWhoBefore = userRoles(ilk, who);
    bytes32 userRolesOtherBefore = userRoles(otherBytes32, otherAddr);
    bytes32 actionsRolesBefore = actionsRoles(anyBytes32, anyAddr, anyBytes4);
    uint256 mask = assert_uint256(2^role);
    bytes32 value = enabled ? userRolesIlkWhoBefore | to_bytes32(mask) : userRolesIlkWhoBefore & to_bytes32(bitNot(mask));

    setUserRole(e, ilk, who, role, enabled);

    mathint wardsAfter = wards(anyAddr);
    address ilkAdminsAfter = ilkAdmins(anyBytes32);
    bytes32 userRolesIlkWhoAfter = userRoles(ilk, who);
    bytes32 userRolesOtherAfter = userRoles(otherBytes32, otherAddr);
    bytes32 actionsRolesAfter = actionsRoles(anyBytes32, anyAddr, anyBytes4);

    assert wardsAfter == wardsBefore, "setUserRole did not keep unchanged every wards[x]";
    assert ilkAdminsAfter == ilkAdminsBefore, "setUserRole did not keep unchanged every ilkAdmins[x]";
    assert userRolesIlkWhoAfter == value, "setUserRole did not set userRoles[ilk][who] by the corresponding value";
    assert userRolesOtherAfter == userRolesOtherBefore, "setUserRole did not keep unchanged the rest of userRoles[x][y]";
    assert actionsRolesAfter == actionsRolesBefore, "setUserRole did not keep unchanged every actionsRoles[x][y][z]";
}

// Verify revert rules on setUserRole
rule setUserRole_revert(bytes32 ilk, address who, uint8 role, bool enabled) {
    env e;

    address ilkAuthIlk = ilkAdmins(ilk);

    setUserRole@withrevert(e, ilk, who, role, enabled);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ilkAuthIlk != e.msg.sender;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct storage changes for non reverting setRoleAction
rule setRoleAction(bytes32 ilk, uint8 role, address target, bytes4 sign, bool enabled) {
    env e;

    bytes32 otherBytes32;
    address otherAddr;
    bytes4  otherBytes4;
    require otherBytes32 != ilk || otherAddr != target || otherBytes4 != sign;
    bytes32 anyBytes32;
    address anyAddr;

    mathint wardsBefore = wards(anyAddr);
    address ilkAdminsBefore = ilkAdmins(anyBytes32);
    bytes32 userRolesBefore = userRoles(anyBytes32, anyAddr);
    bytes32 actionsRolesIlkTargetSigBefore = actionsRoles(ilk, target, sign);
    bytes32 actionsRolesOtherBefore = actionsRoles(otherBytes32, otherAddr, otherBytes4);
    uint256 mask = assert_uint256(2^role);
    bytes32 value = enabled ? actionsRolesIlkTargetSigBefore | to_bytes32(mask) : actionsRolesIlkTargetSigBefore & to_bytes32(bitNot(mask));

    setRoleAction(e, ilk, role, target, sign, enabled);

    mathint wardsAfter = wards(anyAddr);
    address ilkAdminsAfter = ilkAdmins(anyBytes32);
    bytes32 userRolesAfter = userRoles(anyBytes32, anyAddr);
    bytes32 actionsRolesIlkTargetSigAfter = actionsRoles(ilk, target, sign);
    bytes32 actionsRolesOtherAfter = actionsRoles(otherBytes32, otherAddr, otherBytes4);

    assert wardsAfter == wardsBefore, "setRoleAction did not keep unchanged every wards[x]";
    assert ilkAdminsAfter == ilkAdminsBefore, "setRoleAction did not keep unchanged every ilkAdmins[x]";
    assert userRolesAfter == userRolesBefore, "setRoleAction did not keep unchanged every userRoles[x][y]";
    assert actionsRolesIlkTargetSigAfter == value, "setRoleAction did not set actionsRoles[ilk][target][sig] by the corresponding value";
    assert actionsRolesOtherAfter == actionsRolesOtherBefore, "setRoleAction did not keep unchanged the rest of actionsRoles[x][y][z]";
}

// Verify revert rules on setRoleAction
rule setRoleAction_revert(bytes32 ilk, uint8 role, address target, bytes4 sign, bool enabled) {
    env e;

    address ilkAuthIlk = ilkAdmins(ilk);

    setRoleAction@withrevert(e, ilk, role, target, sign, enabled);

    bool revert1 = e.msg.value > 0;
    bool revert2 = ilkAuthIlk != e.msg.sender;

    assert revert1 => lastReverted, "revert1 failed";
    assert revert2 => lastReverted, "revert2 failed";
    assert lastReverted => revert1 || revert2, "Revert rules are not covering all the cases";
}

// Verify correct response from canCall
rule canCall(bytes32 ilk, address caller, address target, bytes4 sign) {
    bool ok = userRoles(ilk, caller) & actionsRoles(ilk, target, sign) != to_bytes32(0);

    bool ok2 = canCall(ilk, caller, target, sign);

    assert ok2 == ok, "canCall did not return the expected result";
}
