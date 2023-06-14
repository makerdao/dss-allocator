// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.16;

contract AllocatorConduitExample {
    // --- storage variables ---

    mapping(address => uint256) public wards;
    mapping(bytes32 => address) public roles;
    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;
    uint256 public totalWithdrawalRequests;

    // --- structs ---

    enum StatusEnum { Inactive, Active, Completed }
    struct WithdrawalRequest {
        bytes32 domain;
        uint256 amount;
        StatusEnum status;
    }

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event SetRoles(bytes32 indexed domain, address roles_);
    event InitiateRequestFunds(address indexed sender, bytes32 domain, uint256 amount, StatusEnum status);
    event CancelRequestFunds(address indexed sender, bytes32 indexed domain, uint256 withdrawalId);
    event Withdraw(address indexed sender, bytes32 indexed domain, uint256 withdrawalId);

    // --- modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "AllocatorBuffer/not-authorized");
        _;
    }

    modifier domainAuth(bytes32 domain) {
        address roles_ = roles[domain];
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
        require(access, "AllocatorConduitExample/not-authorized");
        _;
    }

    // --- getters ---

    function isCancelable(uint256 withdrawalId) external view returns (bool ok) {
        WithdrawalRequest storage request = withdrawalRequests[withdrawalId];
        ok = request.status == StatusEnum.Active;
    }

    function withdrawStatus(uint256 withdrawalId) external view returns (bytes32 domain, uint256 amount, StatusEnum status) {
        WithdrawalRequest storage request = withdrawalRequests[withdrawalId];
        (domain, amount, status) = (request.domain, request.amount, request.status);
    }

    function activeWithdraws(bytes32 domain) external view returns (uint256[] memory withdrawIds, uint256 totalAmount) {
        withdrawIds = new uint256[](totalWithdrawalRequests);
        uint256 count;

        for (uint256 i = 1; i <= totalWithdrawalRequests; i++) {
            if (withdrawalRequests[i].domain == domain && withdrawalRequests[i].status == StatusEnum.Active) {
                withdrawIds[count++] = i;
            }
        }

        for (uint256 i = 0; i < count; i++) {
            totalAmount += withdrawalRequests[withdrawIds[i]].amount;
        }
    }

    function totalActiveWithdraws() external view returns (uint256 count) {
        for (uint256 i = 1; i <= totalWithdrawalRequests; i++) {
            if (withdrawalRequests[i].status == StatusEnum.Active) {
                count++;
            }
        }
    }

    // --- admininstration ---

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function setRoles(bytes32 domain, address roles_) external auth {
        roles[domain] = roles_;
        emit SetRoles(domain, roles_);
    }

    // --- functions ---

    function deposit(bytes32 domain, uint256 amount) external domainAuth(domain) {
        // Implement the logic to deposit funds into the FundManager
    }

    function initiateRequestFunds(bytes32 domain, uint256 amount) external domainAuth(domain) returns (uint256 withdrawalId) {
        require(amount > 0, "AllocatorConduitExample/amount-not-greater-0");

        withdrawalId = ++totalWithdrawalRequests;
        withdrawalRequests[withdrawalId] = WithdrawalRequest(domain, amount, StatusEnum.Active);

        emit InitiateRequestFunds(msg.sender, domain, amount, StatusEnum.Active);
    }

    function cancelRequestFunds(bytes32 domain, uint256 withdrawalId) external domainAuth(domain) {
        WithdrawalRequest storage request = withdrawalRequests[withdrawalId];
        require(request.domain == domain, "AllocatorConduitExample/domain-not-match");
        require(request.status == StatusEnum.Active, "AllocatorConduitExample/request-not-active");

        request.status = StatusEnum.Inactive;
        emit CancelRequestFunds(msg.sender, domain, withdrawalId);
    }

    function withdraw(bytes32 domain, uint256 withdrawalId) external domainAuth(domain) {
        WithdrawalRequest storage request = withdrawalRequests[withdrawalId];
        require(request.domain == domain, "AllocatorConduitExample/domain-not-match");
        require(request.status == StatusEnum.Active, "AllocatorConduitExample/request-not-active");

        // Implement the logic to withdraw funds from the FundManager

        request.status = StatusEnum.Completed;

        emit Withdraw(msg.sender, domain, withdrawalId);
    }
}
