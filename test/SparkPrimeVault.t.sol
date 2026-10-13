// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IAccessControl } from "../lib/oz/contracts/access/IAccessControl.sol";

import { TestBase, SparkPrimeVault, ISparkVaultLike } from "./TestBase.t.sol";

contract SparkPrimeVaultTests is TestBase {

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(admin);
        spPRIME.grantRole(GUARDIAN_ROLE,   guardian);
        spPRIME.grantRole(REBALANCER_ROLE, rebalancer);
        spPRIME.grantRole(SETTER_ROLE,     setter);

        spPRIME.setCapacity(VAULT_CAPACITY);
        spPRIME.setMinimums(MINIMUM_DEPOSIT, MINIMUM_WITHDRAW);
        vm.stopPrank();

        // Deal USDC to user
        deal(address(usdc), user, 1_000_000e6);
    }

}

contract RequestDepositTests is SparkPrimeVaultTests {

    // Failure tests

    function test_requestDeposit_invalidRecipient() external {
        vm.expectRevert("SparkPrimeVault/invalid-recipient");
        spPRIME.requestDeposit(100e6, address(0));
    }

    function test_requestDeposit_belowMinimumBoundary() external {
        vm.prank(user);
        usdc.approve(address(spPRIME), MINIMUM_DEPOSIT);

        vm.expectRevert("SparkPrimeVault/below-minimum");
        vm.prank(user);
        spPRIME.requestDeposit(MINIMUM_DEPOSIT - 1, user);

        vm.prank(user);
        spPRIME.requestDeposit(MINIMUM_DEPOSIT, user);
    }

    function test_requestDeposit_notEnoughAllowanceBoundary() external {
        vm.prank(user);
        usdc.approve(address(spPRIME), 1_000_000e6);

        vm.prank(user);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        spPRIME.requestDeposit(1_000_000e6 + 1, user);

        vm.prank(user);
        spPRIME.requestDeposit(1_000_000e6, user);
    }

    // Success tests

    function test_requestDeposit_instantFill() external {
        vm.prank(user);
        usdc.approve(address(spPRIME), 1_000_000e6);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : VAULT_CAPACITY,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : 0,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 1_000_000e6,
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : 0
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);

        assertEq(usdc.allowance(user, address(spPRIME)), 1_000_000e6);

        uint256 expectedSavingsShares = spUSDC.convertToShares(1_000_000e6);

        vm.expectEmit(address(spUSDC));
        emit ISparkVaultLike.Deposit(address(spPRIME), address(spPRIME), 1_000_000e6, expectedSavingsShares);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.DepositRequest(user, user, 0, 1_000_000e6);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 1_000_000e6 - 1, 1_000_000e6 - 1); // Rounding

        vm.prank(user);
        uint256 requestId = spPRIME.requestDeposit(1_000_000e6, user);

        assertEq(requestId, 0);

        assertEq(usdc.allowance(user, address(spPRIME)), 0);

        vaultState.totalSupply                  = 1_000_000e6 - 1; // Rounding
        vaultState.totalAssets                  = 1_000_000e6 - 1; // Rounding
        vaultState.availableCapacity            = VAULT_CAPACITY - 1_000_000e6 + 1; // Rounding
        vaultState.availableLiquidAssets        = 1_000_000e6 - 1; // Rounding
        vaultState.unencumberedSparkVaultShares = expectedSavingsShares;

        depositQueueState.head = 1;

        userBalances.asset  = 0;
        userBalances.shares = 1_000_000e6 - 1; // Rounding

        vaultBalances.savingsShares = expectedSavingsShares;

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, 0);
    }

    function test_requestDeposit_instantFillMultipleRequests() external {
        vm.prank(user);
        usdc.approve(address(spPRIME), 1_000_000e6);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : VAULT_CAPACITY,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : 0,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 1_000_000e6,
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : 0
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);

        // Request 1 with 500k USDC

        assertEq(usdc.allowance(user, address(spPRIME)), 1_000_000e6);

        uint256 expectedSavingsShares = spUSDC.convertToShares(500_000e6);

        vm.expectEmit(address(spUSDC));
        emit ISparkVaultLike.Deposit(address(spPRIME), address(spPRIME), 500_000e6, expectedSavingsShares);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.DepositRequest(user, user, 0, 500_000e6);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 500_000e6 - 1, 500_000e6 - 1); // Rounding

        vm.prank(user);
        uint256 requestId = spPRIME.requestDeposit(500_000e6, user);

        assertEq(requestId, 0);

        assertEq(usdc.allowance(user, address(spPRIME)), 500_000e6);

        vaultState.totalSupply                  = 500_000e6 - 1; // Rounding
        vaultState.totalAssets                  = 500_000e6 - 1; // Rounding
        vaultState.availableCapacity            = VAULT_CAPACITY - 500_000e6 + 1; // Rounding
        vaultState.availableLiquidAssets        = 500_000e6 - 1; // Rounding
        vaultState.unencumberedSparkVaultShares = expectedSavingsShares;

        depositQueueState.head = 1;

        userBalances.asset  = 500_000e6;
        userBalances.shares = 500_000e6 - 1; // Rounding

        vaultBalances.savingsShares = expectedSavingsShares;

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, 0);

        // Request 2 with 500k USDC

        expectedSavingsShares = spUSDC.convertToShares(500_000e6);

        vm.expectEmit(address(spUSDC));
        emit ISparkVaultLike.Deposit(address(spPRIME), address(spPRIME), 500_000e6, expectedSavingsShares);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.DepositRequest(user, user, 1, 500_000e6);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 500_000e6 - 1, 500_000e6 - 1); // Rounding

        vm.prank(user);
        requestId = spPRIME.requestDeposit(500_000e6, user);

        assertEq(requestId, 1);

        vaultState.totalSupply                  = 1_000_000e6 - 2; // Rounding
        vaultState.totalAssets                  = 1_000_000e6 - 2; // Rounding
        vaultState.availableCapacity            = VAULT_CAPACITY - 1_000_000e6 + 2; // Rounding
        vaultState.availableLiquidAssets        = 1_000_000e6 - 1; // Rounding
        vaultState.unencumberedSparkVaultShares += expectedSavingsShares;

        depositQueueState.head = 2;

        userBalances.asset  = 0;
        userBalances.shares = 1_000_000e6 - 2; // Rounding

        vaultBalances.savingsShares += expectedSavingsShares;

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, 0);
    }

    function test_requestDeposit_instantFill_exactCapacity() external {
        vm.prank(admin);
        spPRIME.setCapacity(1_000_000e6);

        vm.prank(user);
        usdc.approve(address(spPRIME), 1_000_000e6);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : 1_000_000e6,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : 0,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 1_000_000e6,
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : 0
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);

        assertEq(usdc.allowance(user, address(spPRIME)), 1_000_000e6);

        uint256 expectedSavingsShares = spUSDC.convertToShares(1_000_000e6);

        vm.expectEmit(address(spUSDC));
        emit ISparkVaultLike.Deposit(address(spPRIME), address(spPRIME), 1_000_000e6, expectedSavingsShares);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.DepositRequest(user, user, 0, 1_000_000e6);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 1_000_000e6 - 1, 1_000_000e6 - 1); // Rounding

        vm.prank(user);
        uint256 requestId = spPRIME.requestDeposit(1_000_000e6, user);

        assertEq(requestId, 0);

        assertEq(usdc.allowance(user, address(spPRIME)), 0);

        // spUSDC rounding credits 1 wei less than deposited, so 1 share of capacity is left over
        vaultState.totalSupply                  = 1_000_000e6 - 1; // Rounding
        vaultState.totalAssets                  = 1_000_000e6 - 1; // Rounding
        vaultState.availableCapacity            = 1;               // Rounding
        vaultState.availableLiquidAssets        = 1_000_000e6 - 1; // Rounding
        vaultState.unencumberedSparkVaultShares = expectedSavingsShares;

        depositQueueState.head = 1;

        userBalances.asset  = 0;
        userBalances.shares = 1_000_000e6 - 1; // Rounding

        vaultBalances.savingsShares = expectedSavingsShares;

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, 0);
    }

    function test_requestDeposit_instantFill_afterInterestAccrual() external {
        uint256 deployTimestamp = block.timestamp;

        vm.prank(admin);
        spPRIME.setVSRBounds(RAY, MAX_VSR);

        vm.prank(setter);
        spPRIME.setVSR(FIVE_PCT_VSR);

        skip(365 days);

        vm.prank(user);
        usdc.approve(address(spPRIME), 1_000_000e6);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : VAULT_CAPACITY,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : deployTimestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : 0,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 1_000_000e6,
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : 0
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);

        uint256 expectedChi = spPRIME.nowChi();

        // 5% APY over one year
        assertApproxEqRel(expectedChi, 1.05e27, 0.0001e18);

        uint256 expectedSavingsShares = spUSDC.convertToShares(1_000_000e6);
        uint256 expectedAssets        = spUSDC.convertToAssets(expectedSavingsShares);
        uint256 expectedShares        = expectedAssets * RAY / expectedChi;

        // Shares are minted at the accrued chi, so fewer shares than assets
        assertLt(expectedShares, expectedAssets);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Drip(uint192(expectedChi), 0);  // No supply yet, so no diff

        vm.expectEmit(address(spUSDC));
        emit ISparkVaultLike.Deposit(address(spPRIME), address(spPRIME), 1_000_000e6, expectedSavingsShares);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.DepositRequest(user, user, 0, 1_000_000e6);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, expectedAssets, expectedShares);

        vm.prank(user);
        uint256 requestId = spPRIME.requestDeposit(1_000_000e6, user);

        assertEq(requestId, 0);

        assertEq(usdc.allowance(user, address(spPRIME)), 0);

        vaultState.totalSupply                  = expectedShares;
        vaultState.totalAssets                  = expectedShares * expectedChi / RAY;
        vaultState.availableCapacity            = VAULT_CAPACITY - expectedShares;
        vaultState.availableLiquidAssets        = expectedAssets;
        vaultState.unencumberedSparkVaultShares = expectedSavingsShares;
        vaultState.chi                          = expectedChi;
        vaultState.rho                          = block.timestamp;

        depositQueueState.head = 1;

        userBalances.asset  = 0;
        userBalances.shares = expectedShares;

        vaultBalances.savingsShares = expectedSavingsShares;

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, 0);
    }

    function test_requestDeposit_instantAfterQueueFullyCancelled() external {
        vm.prank(user);
        usdc.approve(address(spPRIME), 1_000_000e6);

        // No capacity, so request 0 is queued in full
        vm.prank(admin);
        spPRIME.setCapacity(0);

        uint256 queuedSavingsShares = spUSDC.convertToShares(500_000e6);

        vm.prank(user);
        assertEq(spPRIME.requestDeposit(500_000e6, user), 0);

        _assertDepositRequest(0, user, user, queuedSavingsShares);

        // Cancel request 0, which leaves no shares encumbered by deposits
        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.CancelDepositRequest(0, 500_000e6 - 1); // Rounding

        vm.prank(user);
        spPRIME.cancelDepositRequest(0, user);

        vm.prank(admin);
        spPRIME.setCapacity(VAULT_CAPACITY);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : VAULT_CAPACITY,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : 0,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 1_000_000e6 - 1, // Rounding
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : 0
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(0, address(0), address(0), 0);

        assertEq(usdc.allowance(user, address(spPRIME)), 500_000e6);

        uint256 expectedSavingsShares = spUSDC.convertToShares(500_000e6);

        vm.expectEmit(address(spUSDC));
        emit ISparkVaultLike.Deposit(address(spPRIME), address(spPRIME), 500_000e6, expectedSavingsShares);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.DepositRequest(user, user, 1, 500_000e6);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 500_000e6 - 1, 500_000e6 - 1); // Rounding

        vm.prank(user);
        uint256 requestId = spPRIME.requestDeposit(500_000e6, user);

        // The cancelled entry is skipped and this request fills instantly
        assertEq(requestId, 1);

        assertEq(usdc.allowance(user, address(spPRIME)), 0);

        vaultState.totalSupply                  = 500_000e6 - 1; // Rounding
        vaultState.totalAssets                  = 500_000e6 - 1; // Rounding
        vaultState.availableCapacity            = VAULT_CAPACITY - 500_000e6 + 1; // Rounding
        vaultState.availableLiquidAssets        = 500_000e6 - 1; // Rounding
        vaultState.unencumberedSparkVaultShares = expectedSavingsShares;

        depositQueueState.head = 2;

        userBalances.asset  = 500_000e6 - 1; // Rounding
        userBalances.shares = 500_000e6 - 1; // Rounding

        vaultBalances.savingsShares = expectedSavingsShares;

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(0,         address(0), address(0), 0);
        _assertDepositRequest(requestId, user,       user,       0);
    }

    function test_requestDeposit_partialInstantFill() external {
        vm.prank(admin);
        spPRIME.setCapacity(500_000e6);

        vm.prank(user);
        usdc.approve(address(spPRIME), 1_000_000e6);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : 500_000e6,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : 0,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 1_000_000e6,
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : 0
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);

        uint256 expectedSavingsShares = spUSDC.convertToShares(1_000_000e6);

        // The 500k of capacity converts to spUSDC shares (rounded down), which is what gets filled
        uint256 filledSavingsShares = spUSDC.convertToShares(500_000e6);
        uint256 queuedSavingsShares = expectedSavingsShares - filledSavingsShares;

        vm.expectEmit(address(spUSDC));
        emit ISparkVaultLike.Deposit(address(spPRIME), address(spPRIME), 1_000_000e6, expectedSavingsShares);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.DepositRequest(user, user, 0, 1_000_000e6);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 500_000e6 - 1, 500_000e6 - 1);  // Rounding

        vm.prank(user);
        uint256 requestId = spPRIME.requestDeposit(1_000_000e6, user);

        assertEq(requestId, 0);

        vaultState.totalSupply                  = 500_000e6 - 1;  // Rounding
        vaultState.totalAssets                  = 500_000e6 - 1;  // Rounding
        vaultState.availableCapacity            = 1;              // Rounding
        vaultState.availableLiquidAssets        = spUSDC.convertToAssets(filledSavingsShares);
        vaultState.unencumberedSparkVaultShares = filledSavingsShares;

        // Partial fill, the request stays at the head with the rest of its spUSDC
        depositQueueState.encumberedShares = queuedSavingsShares;

        userBalances.asset  = 0;
        userBalances.shares = 500_000e6 - 1;  // Rounding

        vaultBalances.savingsShares = expectedSavingsShares;

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, queuedSavingsShares);
    }

    function test_requestDeposit_queued_oneShareCapacityLeft() external {
        vm.prank(admin);
        spPRIME.setCapacity(500_000e6);

        vm.prank(user);
        usdc.approve(address(spPRIME), 1_000_000e6);

        // Request 0 fills 500k - 1 (rounding), leaving 1 share of capacity
        vm.prank(user);
        spPRIME.requestDeposit(500_000e6, user);

        uint256 expectedSavingsShares = spUSDC.convertToShares(500_000e6);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 500_000e6 - 1,  // Rounding
            totalAssets                  : 500_000e6 - 1,  // Rounding
            availableCapacity            : 1,              // Rounding
            availableLiquidAssets        : 500_000e6 - 1,  // Rounding
            unencumberedSparkVaultShares : expectedSavingsShares,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : 0,
            head             : 1
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 500_000e6,
            shares        : 500_000e6 - 1, // Rounding
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : expectedSavingsShares
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);

        assertEq(spUSDC.convertToShares(1), 0);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.DepositRequest(user, user, 1, 500_000e6);

        vm.prank(user);
        uint256 requestId = spPRIME.requestDeposit(500_000e6, user);

        assertEq(requestId, 1);

        // Nothing is minted, the whole request waits in the queue and the 1 share of capacity stays
        depositQueueState.encumberedShares = expectedSavingsShares;

        userBalances.asset = 0;

        vaultBalances.savingsShares = 2 * expectedSavingsShares;

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, expectedSavingsShares);
    }

    function test_requestDeposit_queued_noCapacity() external {
        vm.prank(admin);
        spPRIME.setCapacity(0);

        vm.prank(user);
        usdc.approve(address(spPRIME), 1_000_000e6);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : 0,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : 0,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 1_000_000e6,
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : 0
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);

        uint256 expectedSavingsShares = spUSDC.convertToShares(1_000_000e6);

        vm.expectEmit(address(spUSDC));
        emit ISparkVaultLike.Deposit(address(spPRIME), address(spPRIME), 1_000_000e6, expectedSavingsShares);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.DepositRequest(user, user, 0, 1_000_000e6);

        vm.prank(user);
        uint256 requestId = spPRIME.requestDeposit(1_000_000e6, user);

        assertEq(requestId, 0);

        // Nothing is minted, the whole request waits in the queue as spUSDC
        depositQueueState.encumberedShares = expectedSavingsShares;

        userBalances.asset = 0;

        vaultBalances.savingsShares = expectedSavingsShares;

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, expectedSavingsShares);
    }

    function test_requestDeposit_queued_queueNotEmpty() external {
        vm.prank(admin);
        spPRIME.setCapacity(250_000e6);

        vm.prank(user);
        usdc.approve(address(spPRIME), 1_000_000e6);

        // Request 0 is partially filled and stays at the head
        vm.prank(user);
        spPRIME.requestDeposit(500_000e6, user);

        // Capacity is free again, but request 0 is still queued ahead
        vm.prank(admin);
        spPRIME.setCapacity(VAULT_CAPACITY);

        uint256 expectedSavingsShares = spUSDC.convertToShares(500_000e6);

        ( , , uint256 queuedSavingsShares ) = spPRIME.depositQueue(0);

        assertGt(queuedSavingsShares, 0);

        uint256 filledSavingsShares = expectedSavingsShares - queuedSavingsShares;

        // The 250k of capacity converts to spUSDC shares (rounded down), which is what got filled
        assertEq(filledSavingsShares, spUSDC.convertToShares(250_000e6));

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 250_000e6 - 1,  // Rounding
            totalAssets                  : 250_000e6 - 1,  // Rounding
            availableCapacity            : VAULT_CAPACITY - 250_000e6 + 1,  // Rounding
            availableLiquidAssets        : spUSDC.convertToAssets(filledSavingsShares),
            unencumberedSparkVaultShares : filledSavingsShares,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : queuedSavingsShares,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 500_000e6,
            shares        : 250_000e6 - 1, // Rounding
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : expectedSavingsShares
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);

        vm.expectEmit(address(spUSDC));
        emit ISparkVaultLike.Deposit(address(spPRIME), address(spPRIME), 500_000e6, expectedSavingsShares);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.DepositRequest(user, user, 1, 500_000e6);

        vm.prank(user);
        uint256 requestId = spPRIME.requestDeposit(500_000e6, user);

        assertEq(requestId, 1);

        // Queued behind request 0 (FIFO), nothing is filled
        depositQueueState.encumberedShares = queuedSavingsShares + expectedSavingsShares;

        userBalances.asset = 0;

        vaultBalances.savingsShares = 2 * expectedSavingsShares;

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(0,         user, user, queuedSavingsShares);
        _assertDepositRequest(requestId, user, user, expectedSavingsShares);
    }

    function test_requestDeposit_queued_subShareCapacityLeft() external {
        uint256 deployTimestamp = block.timestamp;

        vm.startPrank(admin);
        spPRIME.setVSRBounds(RAY, MAX_VSR);
        spPRIME.setCapacity(1);
        vm.stopPrank();

        vm.prank(setter);
        spPRIME.setVSR(FIVE_PCT_VSR);

        skip(365 days);

        vm.prank(user);
        usdc.approve(address(spPRIME), 1_000_000e6);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : 1,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : deployTimestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : 0,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 1_000_000e6,
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : 0
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);

        uint256 expectedChi           = spPRIME.nowChi();
        uint256 expectedSavingsShares = spUSDC.convertToShares(500_000e6);

        // 1 share of capacity is worth 1 wei at chi 1.05, which buys 0 spUSDC shares
        assertEq(spUSDC.convertToShares(1 * expectedChi / RAY), 0);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Drip(uint192(expectedChi), 0);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.DepositRequest(user, user, 0, 500_000e6);

        vm.prank(user);
        uint256 requestId = spPRIME.requestDeposit(500_000e6, user);

        assertEq(requestId, 0);

        // Nothing is minted, the whole request waits in the queue
        vaultState.chi = expectedChi;
        vaultState.rho = block.timestamp;

        depositQueueState.encumberedShares = expectedSavingsShares;

        userBalances.asset = 500_000e6;

        vaultBalances.savingsShares = expectedSavingsShares;

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, expectedSavingsShares);
    }

    function test_requestDeposit_queued_moreThan500CancelledAhead() external {
        vm.prank(admin);
        spPRIME.setCapacity(0);

        vm.startPrank(user);
        usdc.approve(address(spPRIME), 1_000_000e6);

        // Queue 500 requests, then cancel all of them
        for (uint256 i; i < 500; ++i) {
            spPRIME.requestDeposit(MINIMUM_DEPOSIT, user);
        }

        for (uint256 i; i < 500; ++i) {
            spPRIME.cancelDepositRequest(i, user);
        }
        vm.stopPrank();

        vm.prank(admin);
        spPRIME.setCapacity(VAULT_CAPACITY);

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : 0,
            head             : 0
        });

        _assertDepositQueueState(depositQueueState);

        uint256 expectedSavingsShares = spUSDC.convertToShares(500_000e6);

        vm.prank(user);
        uint256 requestId = spPRIME.requestDeposit(500_000e6, user);

        assertEq(requestId, 500);

        // The walk stops at the 500th cancelled entry, before it reaches request 500
        depositQueueState.encumberedShares = expectedSavingsShares;
        depositQueueState.head             = 499;

        _assertDepositQueueState(depositQueueState);
        _assertDepositRequest(requestId, user, user, expectedSavingsShares);

        assertEq(spPRIME.totalSupply(),   0);
        assertEq(spPRIME.balanceOf(user), 0);
    }

    function test_requestDeposit_instantFill_withReferral() external {
        vm.prank(user);
        usdc.approve(address(spPRIME), 1_000_000e6);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : VAULT_CAPACITY,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : 0,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 1_000_000e6,
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : 0
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);

        uint256 expectedSavingsShares = spUSDC.convertToShares(1_000_000e6);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Referral(1, user, 1_000_000e6);

        vm.expectEmit(address(spUSDC));
        emit ISparkVaultLike.Deposit(address(spPRIME), address(spPRIME), 1_000_000e6, expectedSavingsShares);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.DepositRequest(user, user, 0, 1_000_000e6);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 1_000_000e6 - 1, 1_000_000e6 - 1); // Rounding

        vm.prank(user);
        uint256 requestId = spPRIME.requestDeposit(1_000_000e6, user, 1);

        assertEq(requestId, 0);

        vaultState.totalSupply                  = 1_000_000e6 - 1; // Rounding
        vaultState.totalAssets                  = 1_000_000e6 - 1; // Rounding
        vaultState.availableCapacity            = VAULT_CAPACITY - 1_000_000e6 + 1; // Rounding
        vaultState.availableLiquidAssets        = 1_000_000e6 - 1; // Rounding
        vaultState.unencumberedSparkVaultShares = expectedSavingsShares;

        depositQueueState.head = 1;

        userBalances.asset  = 0;
        userBalances.shares = 1_000_000e6 - 1; // Rounding

        vaultBalances.savingsShares = expectedSavingsShares;

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, 0);
    }

}

contract ProcessDepositQueueTests is SparkPrimeVaultTests {

    function setUp() public override {
        super.setUp();

        vm.prank(user);
        usdc.approve(address(spPRIME), 1_000_000e6);
    }

    function _queueDeposit(uint256 assets, address recipient)
        internal
        returns (uint256 requestId, uint256 savingsShares)
    {
        savingsShares = spUSDC.convertToShares(assets);

        vm.prank(admin);
        spPRIME.setCapacity(0);

        vm.prank(user);
        requestId = spPRIME.requestDeposit(assets, recipient);

        vm.prank(admin);
        spPRIME.setCapacity(VAULT_CAPACITY);
    }

    function _queueDeposit(uint256 assets)
        internal
        returns (uint256 requestId, uint256 savingsShares)
    {
        return _queueDeposit(assets, user);
    }

    // Failure tests

    function test_processDepositQueue_notRebalancer() external {
        vm.expectRevert(abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            address(this),
            REBALANCER_ROLE
        ));
        spPRIME.processDepositQueue(type(uint256).max);
    }

    function test_processDepositQueue_paused() external {
        vm.prank(guardian);
        spPRIME.pause();

        vm.expectRevert("SparkPrimeVault/paused");
        vm.prank(rebalancer);
        spPRIME.processDepositQueue(type(uint256).max);
    }

    // Success tests

    function test_processDepositQueue_emptyQueue() external {
        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : VAULT_CAPACITY,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : 0,
            head             : 0
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);

        vm.prank(rebalancer);
        spPRIME.processDepositQueue(type(uint256).max);

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
    }

    function test_processDepositQueue_singleRequest() external {
        ( uint256 requestId, uint256 savingsShares ) = _queueDeposit(1_000_000e6);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : VAULT_CAPACITY,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : savingsShares,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 0,
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : savingsShares
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, savingsShares);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 1_000_000e6 - 1, 1_000_000e6 - 1);  // Rounding

        vm.prank(rebalancer);
        spPRIME.processDepositQueue(type(uint256).max);

        vaultState.totalSupply                  = 1_000_000e6 - 1;  // Rounding
        vaultState.totalAssets                  = 1_000_000e6 - 1;  // Rounding
        vaultState.availableCapacity            = VAULT_CAPACITY - 1_000_000e6 + 1;  // Rounding
        vaultState.availableLiquidAssets        = 1_000_000e6 - 1;  // Rounding
        vaultState.unencumberedSparkVaultShares = savingsShares;

        depositQueueState.encumberedShares = 0;
        depositQueueState.head             = 1;

        userBalances.shares = 1_000_000e6 - 1;  // Rounding

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, 0);
    }

    function test_processDepositQueue_multipleRequests() external {
        ( , uint256 savingsShares0 ) = _queueDeposit(500_000e6);
        ( , uint256 savingsShares1 ) = _queueDeposit(500_000e6);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : VAULT_CAPACITY,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : savingsShares0 + savingsShares1,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 0,
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : savingsShares0 + savingsShares1
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(0, user, user, savingsShares0);
        _assertDepositRequest(1, user, user, savingsShares1);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 500_000e6 - 1, 500_000e6 - 1);  // Rounding

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 500_000e6 - 1, 500_000e6 - 1);  // Rounding

        vm.prank(rebalancer);
        spPRIME.processDepositQueue(type(uint256).max);

        vaultState.totalSupply                  = 1_000_000e6 - 2;  // Rounding
        vaultState.totalAssets                  = 1_000_000e6 - 2;  // Rounding
        vaultState.availableCapacity            = VAULT_CAPACITY - 1_000_000e6 + 2;  // Rounding
        vaultState.availableLiquidAssets        = 1_000_000e6 - 1;  // Rounding
        vaultState.unencumberedSparkVaultShares = savingsShares0 + savingsShares1;

        depositQueueState.encumberedShares = 0;
        depositQueueState.head             = 2;

        userBalances.shares = 1_000_000e6 - 2;  // Rounding

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(0, user, user, 0);
        _assertDepositRequest(1, user, user, 0);
    }

    function test_processDepositQueue_singleRequestPartialFill() external {
        ( uint256 requestId, uint256 savingsShares ) = _queueDeposit(1_000_000e6);

        // Exactly half of the spUSDC shares are taken, worth 500k - 1 (rounding)
        uint256 filledSavingsShares = savingsShares / 2;
        uint256 queuedSavingsShares = savingsShares - filledSavingsShares;

        assertEq(spUSDC.convertToAssets(filledSavingsShares), 500_000e6 - 1);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : VAULT_CAPACITY,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : savingsShares,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 0,
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : savingsShares
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, savingsShares);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 500_000e6 - 1, 500_000e6 - 1);  // Rounding

        vm.prank(rebalancer);
        spPRIME.processDepositQueue(filledSavingsShares);

        vaultState.totalSupply                  = 500_000e6 - 1;  // Rounding
        vaultState.totalAssets                  = 500_000e6 - 1;  // Rounding
        vaultState.availableCapacity            = VAULT_CAPACITY - 500_000e6 + 1;  // Rounding
        vaultState.availableLiquidAssets        = 500_000e6 - 1;  // Rounding
        vaultState.unencumberedSparkVaultShares = filledSavingsShares;

        // Partial fill, the request stays at the head with the rest of its spUSDC
        depositQueueState.encumberedShares = queuedSavingsShares;

        userBalances.shares = 500_000e6 - 1; // Rounding

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, queuedSavingsShares);
    }

    function test_processDepositQueue_maxSparkVaultSharesSpansMultipleRequests() external {
        ( , uint256 savingsShares0 ) = _queueDeposit(500_000e6);
        ( , uint256 savingsShares1 ) = _queueDeposit(500_000e6);

        // Request 0 in full plus half of request 1, worth 250k - 1 (rounding)
        uint256 filledSavingsShares1 = savingsShares1 / 2;
        uint256 queuedSavingsShares1 = savingsShares1 - filledSavingsShares1;

        assertEq(spUSDC.convertToAssets(filledSavingsShares1), 250_000e6 - 1);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : VAULT_CAPACITY,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : savingsShares0 + savingsShares1,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 0,
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : savingsShares0 + savingsShares1
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(0, user, user, savingsShares0);
        _assertDepositRequest(1, user, user, savingsShares1);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 500_000e6 - 1, 500_000e6 - 1); // Rounding

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 250_000e6 - 1, 250_000e6 - 1); // Rounding

        vm.prank(rebalancer);
        spPRIME.processDepositQueue(savingsShares0 + filledSavingsShares1);

        vaultState.totalSupply                  = 750_000e6 - 2;  // Rounding
        vaultState.totalAssets                  = 750_000e6 - 2;  // Rounding
        vaultState.availableCapacity            = VAULT_CAPACITY - 750_000e6 + 2;  // Rounding
        vaultState.availableLiquidAssets        =
            spUSDC.convertToAssets(savingsShares0 + filledSavingsShares1);
        vaultState.unencumberedSparkVaultShares = savingsShares0 + filledSavingsShares1;

        // Request 1 is partially filled and stays at the head
        depositQueueState.encumberedShares = queuedSavingsShares1;
        depositQueueState.head             = 1;

        userBalances.shares = 750_000e6 - 2;  // Rounding

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(0, user, user, 0);
        _assertDepositRequest(1, user, user, queuedSavingsShares1);
    }

    function test_processDepositQueue_zeroMaxSparkVaultShares() external {
        ( uint256 requestId, uint256 savingsShares ) = _queueDeposit(1_000_000e6);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : VAULT_CAPACITY,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : savingsShares,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 0,
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : savingsShares
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, savingsShares);

        vm.prank(rebalancer);
        spPRIME.processDepositQueue(0);

        // Nothing is filled, the request stays at the head
        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, savingsShares);
    }

    function test_processDepositQueue_capacityLimited() external {
        ( uint256 requestId, uint256 savingsShares ) = _queueDeposit(1_000_000e6);

        vm.prank(admin);
        spPRIME.setCapacity(500_000e6);

        // The 500k of capacity converts to spUSDC shares (rounded down), which is what gets filled
        uint256 filledSavingsShares = spUSDC.convertToShares(500_000e6);
        uint256 queuedSavingsShares = savingsShares - filledSavingsShares;

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : 500_000e6,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : savingsShares,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 0,
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : savingsShares
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, savingsShares);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 500_000e6 - 1, 500_000e6 - 1); // Rounding

        vm.prank(rebalancer);
        spPRIME.processDepositQueue(type(uint256).max);

        // spUSDC rounding credits 1 wei less than the capacity, so 1 share of capacity is left over
        vaultState.totalSupply                  = 500_000e6 - 1;  // Rounding
        vaultState.totalAssets                  = 500_000e6 - 1;  // Rounding
        vaultState.availableCapacity            = 1;              // Rounding
        vaultState.availableLiquidAssets        = 500_000e6 - 1;  // Rounding
        vaultState.unencumberedSparkVaultShares = filledSavingsShares;

        depositQueueState.encumberedShares = queuedSavingsShares;

        userBalances.shares = 500_000e6 - 1;  // Rounding

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, queuedSavingsShares);
    }

    function test_processDepositQueue_capacityDustLeftover() external {
        ( uint256 requestId, uint256 savingsShares ) = _queueDeposit(1_000_000e6);

        vm.prank(admin);
        spPRIME.setCapacity(500_000e6);

        uint256 filledSavingsShares = spUSDC.convertToShares(500_000e6);
        uint256 queuedSavingsShares = savingsShares - filledSavingsShares;

        vm.prank(rebalancer);
        spPRIME.processDepositQueue(type(uint256).max);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 500_000e6 - 1,  // Rounding
            totalAssets                  : 500_000e6 - 1,  // Rounding
            availableCapacity            : 1,              // Rounding
            availableLiquidAssets        : 500_000e6 - 1,  // Rounding
            unencumberedSparkVaultShares : filledSavingsShares,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : queuedSavingsShares,
            head             : 0
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertDepositRequest(requestId, user, user, queuedSavingsShares);

        // The 1 share of leftover capacity buys 0 spUSDC shares, so another call is a no-op
        assertEq(spUSDC.convertToShares(1), 0);

        vm.prank(rebalancer);
        spPRIME.processDepositQueue(type(uint256).max);

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertDepositRequest(requestId, user, user, queuedSavingsShares);

        // Raising the capacity lets the rest of the request through
        vm.prank(admin);
        spPRIME.setCapacity(VAULT_CAPACITY);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 500_000e6 - 1, 500_000e6 - 1); // Rounding

        vm.prank(rebalancer);
        spPRIME.processDepositQueue(type(uint256).max);

        vaultState.totalSupply                  = 1_000_000e6 - 2;  // Rounding
        vaultState.totalAssets                  = 1_000_000e6 - 2;  // Rounding
        vaultState.availableCapacity            = VAULT_CAPACITY - 1_000_000e6 + 2;  // Rounding
        vaultState.availableLiquidAssets        = 1_000_000e6 - 1;  // Rounding
        vaultState.unencumberedSparkVaultShares = savingsShares;

        depositQueueState.encumberedShares = 0;
        depositQueueState.head             = 1;

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertDepositRequest(requestId, user, user, 0);
    }

    function test_processDepositQueue_noCapacity() external {
        ( uint256 requestId, uint256 savingsShares ) = _queueDeposit(1_000_000e6);

        vm.prank(admin);
        spPRIME.setCapacity(0);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : 0,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : savingsShares,
            head             : 0
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertDepositRequest(requestId, user, user, savingsShares);

        assertEq(spPRIME.balanceOf(user), 0);

        vm.prank(rebalancer);
        spPRIME.processDepositQueue(type(uint256).max);

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertDepositRequest(requestId, user, user, savingsShares);

        assertEq(spPRIME.balanceOf(user), 0);
    }

    function test_processDepositQueue_subShareCapacity() external {
        ( uint256 requestId, uint256 savingsShares ) = _queueDeposit(1_000_000e6);

        vm.prank(admin);
        spPRIME.setCapacity(1);

        // 1 share of capacity is worth 1 wei, which buys 0 spUSDC shares
        assertEq(spUSDC.convertToShares(1), 0);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : 1,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : savingsShares,
            head             : 0
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertDepositRequest(requestId, user, user, savingsShares);

        vm.prank(rebalancer);
        spPRIME.processDepositQueue(type(uint256).max);

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertDepositRequest(requestId, user, user, savingsShares);

        assertEq(spPRIME.balanceOf(user), 0);
    }

    function test_processDepositQueue_afterInterestAccrual() external {
        uint256 deployTimestamp = block.timestamp;

        ( uint256 requestId, uint256 savingsShares ) = _queueDeposit(1_000_000e6);

        vm.prank(admin);
        spPRIME.setVSRBounds(RAY, MAX_VSR);

        vm.prank(setter);
        spPRIME.setVSR(FIVE_PCT_VSR);

        skip(365 days);

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : VAULT_CAPACITY,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : deployTimestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : savingsShares,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 0,
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : savingsShares
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, savingsShares);

        uint256 expectedChi = spPRIME.nowChi();

        // 5% APY over one year
        assertEq(expectedChi, 1.049999999999999999961070145e27);

        uint256 expectedAssets = spUSDC.convertToAssets(savingsShares);
        uint256 expectedShares = expectedAssets * RAY / expectedChi;

        // The queued spUSDC earned yield while waiting, and shares are minted at the accrued chi
        assertEq(expectedAssets, 1_037_999.999999e6);
        assertEq(expectedShares, 988_571.428570e6);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Drip(uint192(expectedChi), 0);  // No supply yet, so no diff

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, expectedAssets, expectedShares);

        vm.prank(rebalancer);
        spPRIME.processDepositQueue(type(uint256).max);

        vaultState.totalSupply                  = expectedShares;
        vaultState.totalAssets                  = expectedShares * expectedChi / RAY;
        vaultState.availableCapacity            = VAULT_CAPACITY - expectedShares;
        vaultState.availableLiquidAssets        = expectedAssets;
        vaultState.unencumberedSparkVaultShares = savingsShares;
        vaultState.chi                          = expectedChi;
        vaultState.rho                          = block.timestamp;

        depositQueueState.encumberedShares = 0;
        depositQueueState.head             = 1;

        userBalances.shares = expectedShares;

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, 0);
    }

    function test_processDepositQueue_skipsCancelled() external {
        _queueDeposit(300_000e6);
        _queueDeposit(300_000e6);
        ( uint256 requestId, uint256 savingsShares ) = _queueDeposit(300_000e6);

        vm.startPrank(user);
        spPRIME.cancelDepositRequest(0, user);
        spPRIME.cancelDepositRequest(1, user);
        vm.stopPrank();

        AssertVaultStateParams memory vaultState = AssertVaultStateParams({
            totalSupply                  : 0,
            totalAssets                  : 0,
            availableCapacity            : VAULT_CAPACITY,
            availableLiquidAssets        : 0,
            unencumberedSparkVaultShares : 0,
            chi                          : RAY,
            rho                          : block.timestamp
        });

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : savingsShares,
            head             : 0
        });

        AssertBalancesParams memory userBalances = AssertBalancesParams({
            account       : user,
            asset         : 100_000e6 + 2 * (300_000e6 - 1), // Rounding on the refunds
            shares        : 0,
            savingsShares : 0
        });

        AssertBalancesParams memory vaultBalances = AssertBalancesParams({
            account       : address(spPRIME),
            asset         : 0,
            shares        : 0,
            savingsShares : savingsShares
        });

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(0,         address(0), address(0), 0);
        _assertDepositRequest(1,         address(0), address(0), 0);
        _assertDepositRequest(requestId, user,       user,       savingsShares);

        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 300_000e6 - 1, 300_000e6 - 1); // Rounding

        vm.prank(rebalancer);
        spPRIME.processDepositQueue(type(uint256).max);

        vaultState.totalSupply                  = 300_000e6 - 1; // Rounding
        vaultState.totalAssets                  = 300_000e6 - 1; // Rounding
        vaultState.availableCapacity            = VAULT_CAPACITY - 300_000e6 + 1; // Rounding
        vaultState.availableLiquidAssets        = 300_000e6 - 1; // Rounding
        vaultState.unencumberedSparkVaultShares = savingsShares;

        // The cancelled entries are walked over and request 2 is filled
        depositQueueState.encumberedShares = 0;
        depositQueueState.head             = 3;

        userBalances.shares = 300_000e6 - 1; // Rounding

        _assertVaultState(vaultState);
        _assertDepositQueueState(depositQueueState);
        _assertBalances(userBalances);
        _assertBalances(vaultBalances);
        _assertDepositRequest(requestId, user, user, 0);
    }

    function test_processDepositQueue_moreThan500Cancelled() external {
        vm.prank(admin);
        spPRIME.setCapacity(0);

        // Request 0 is live, then 500 requests are queued behind it and cancelled, then request
        // 501 is queued behind those.
        uint256 savingsShares0 = spUSDC.convertToShares(MINIMUM_DEPOSIT);

        vm.startPrank(user);
        spPRIME.requestDeposit(MINIMUM_DEPOSIT, user);

        for (uint256 i; i < 500; ++i) {
            spPRIME.requestDeposit(MINIMUM_DEPOSIT, user);
        }

        for (uint256 i = 1; i <= 500; ++i) {
            spPRIME.cancelDepositRequest(i, user);
        }

        uint256 savingsShares501 = spUSDC.convertToShares(500_000e6);

        assertEq(spPRIME.requestDeposit(500_000e6, user), 501);
        vm.stopPrank();

        vm.prank(admin);
        spPRIME.setCapacity(VAULT_CAPACITY);

        AssertQueueStateParams memory depositQueueState = AssertQueueStateParams({
            encumberedShares : savingsShares0 + savingsShares501,
            head             : 0
        });

        _assertDepositQueueState(depositQueueState);
        _assertDepositRequest(0,   user, user, savingsShares0);
        _assertDepositRequest(501, user, user, savingsShares501);

        // Request 0 is filled (1 wei less, rounding), then the walk stops at the 500th cancelled
        // entry
        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, MINIMUM_DEPOSIT - 1, MINIMUM_DEPOSIT - 1);

        vm.prank(rebalancer);
        spPRIME.processDepositQueue(type(uint256).max);

        depositQueueState.encumberedShares = savingsShares501;
        depositQueueState.head             = 500;

        _assertDepositQueueState(depositQueueState);
        _assertDepositRequest(0,   user, user, 0);
        _assertDepositRequest(501, user, user, savingsShares501);

        assertEq(spPRIME.totalSupply(),   MINIMUM_DEPOSIT - 1); // Rounding
        assertEq(spPRIME.balanceOf(user), MINIMUM_DEPOSIT - 1); // Rounding

        // The next call picks up where the walk stopped and fills request 501
        vm.expectEmit(address(spPRIME));
        emit SparkPrimeVault.Deposit(user, user, 500_000e6 - 1, 500_000e6 - 1); // Rounding

        vm.prank(rebalancer);
        spPRIME.processDepositQueue(type(uint256).max);

        depositQueueState.encumberedShares = 0;
        depositQueueState.head             = 502;

        _assertDepositQueueState(depositQueueState);
        _assertDepositRequest(0,   user, user, 0);
        _assertDepositRequest(501, user, user, 0);

        assertEq(spPRIME.totalSupply(),   MINIMUM_DEPOSIT + 500_000e6 - 2); // Rounding
        assertEq(spPRIME.balanceOf(user), MINIMUM_DEPOSIT + 500_000e6 - 2); // Rounding
    }

}
