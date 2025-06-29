#[test_only]
module movekit::access_control_admin_registry_tests {
    use std::signer;
    use movekit::access_control_admin_registry;

    // Test constants matching the module
    const E_NOT_INITIALIZED: u64 = 0;
    const E_NOT_ADMIN: u64 = 1;
    const E_SELF_TRANSFER_NOT_ALLOWED: u64 = 2;
    const E_NO_PENDING_ADMIN: u64 = 3;
    const E_NOT_PENDING_ADMIN: u64 = 4;
    const E_ALREADY_INITIALIZED: u64 = 5;

    // ===========================================
    // INITIALIZATION TESTS
    // ===========================================

    #[test(deployer = @movekit)]
    fun test_init_module_success(deployer: &signer) {
        access_control_admin_registry::init_for_testing(deployer);

        let deployer_addr = signer::address_of(deployer);

        // Should set deployer as current admin
        assert!(access_control_admin_registry::get_current_admin() == deployer_addr);
        assert!(access_control_admin_registry::is_current_admin(deployer_addr));

        // No pending admin initially
        assert!(!access_control_admin_registry::has_pending_admin());
    }

    #[test(deployer = @movekit)]
    #[expected_failure]
    fun test_double_initialization_fails(deployer: &signer) {
        access_control_admin_registry::init_for_testing(deployer);
        // Second initialization should fail
        access_control_admin_registry::init_for_testing(deployer);
    }

    #[test]
    #[
        expected_failure(
            abort_code = E_NOT_INITIALIZED,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_get_current_admin_not_initialized() {
        // Should fail when not initialized
        access_control_admin_registry::get_current_admin();
    }

    #[test]
    #[
        expected_failure(
            abort_code = E_NOT_INITIALIZED,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_is_current_admin_not_initialized() {
        // Should fail when not initialized (now that is_current_admin calls get_current_admin)
        access_control_admin_registry::is_current_admin(@0x123);
    }

    // ===========================================
    // ADMIN CHECK TESTS
    // ===========================================

    #[test(deployer = @movekit)]
    fun test_require_admin_success(deployer: &signer) {
        access_control_admin_registry::init_for_testing(deployer);

        // Should not abort for actual admin
        access_control_admin_registry::require_admin(deployer);
    }

    #[test(deployer = @movekit)]
    #[
        expected_failure(
            abort_code = E_NOT_INITIALIZED,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_require_admin_not_initialized(deployer: &signer) {
        access_control_admin_registry::require_admin(deployer);
    }

    #[test(deployer = @movekit, non_admin = @0x123)]
    #[
        expected_failure(
            abort_code = E_NOT_ADMIN, location = movekit::access_control_admin_registry
        )
    ]
    fun test_require_admin_fails_for_non_admin(
        deployer: &signer, non_admin: &signer
    ) {
        access_control_admin_registry::init_for_testing(deployer);

        // Should fail for non-admin
        access_control_admin_registry::require_admin(non_admin);
    }

    #[test(deployer = @movekit)]
    fun test_is_current_admin_various_addresses(deployer: &signer) {
        access_control_admin_registry::init_for_testing(deployer);

        let deployer_addr = signer::address_of(deployer);

        assert!(access_control_admin_registry::is_current_admin(deployer_addr));
        assert!(!access_control_admin_registry::is_current_admin(@0x123));
        assert!(!access_control_admin_registry::is_current_admin(@0x456));
    }

    // ===========================================
    // TWO-STEP TRANSFER TESTS
    // ===========================================

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_transfer_admin_complete_flow(
        admin: &signer, new_admin: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);

        let admin_addr = signer::address_of(admin);
        let new_admin_addr = signer::address_of(new_admin);

        // Step 1: Propose transfer
        access_control_admin_registry::transfer_admin(admin, new_admin_addr);

        // Check pending state
        assert!(access_control_admin_registry::has_pending_admin());
        assert!(access_control_admin_registry::get_pending_admin() == new_admin_addr);

        // Admin should still be current
        assert!(access_control_admin_registry::get_current_admin() == admin_addr);
        assert!(access_control_admin_registry::is_current_admin(admin_addr));
        assert!(!access_control_admin_registry::is_current_admin(new_admin_addr));

        // Step 2: Accept transfer
        access_control_admin_registry::accept_pending_admin(new_admin);

        // Check transfer completed
        assert!(access_control_admin_registry::get_current_admin() == new_admin_addr);
        assert!(access_control_admin_registry::is_current_admin(new_admin_addr));
        assert!(!access_control_admin_registry::is_current_admin(admin_addr));

        // Check pending admin cleaned up
        assert!(!access_control_admin_registry::has_pending_admin());
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_transfer_admin_overwrite_proposal(
        admin: &signer, new_admin: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);

        let new_admin_addr = signer::address_of(new_admin);
        let another_addr = @0x456;

        // First proposal
        access_control_admin_registry::transfer_admin(admin, new_admin_addr);
        assert!(access_control_admin_registry::get_pending_admin() == new_admin_addr);

        // Second proposal overwrites first
        access_control_admin_registry::transfer_admin(admin, another_addr);
        assert!(access_control_admin_registry::get_pending_admin() == another_addr);

        // Old proposal is no longer valid
        assert!(access_control_admin_registry::get_pending_admin() != new_admin_addr);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_cancel_admin_transfer(admin: &signer, new_admin: &signer) {
        access_control_admin_registry::init_for_testing(admin);

        let admin_addr = signer::address_of(admin);
        let new_admin_addr = signer::address_of(new_admin);

        // Propose transfer
        access_control_admin_registry::transfer_admin(admin, new_admin_addr);
        assert!(access_control_admin_registry::has_pending_admin());

        // Cancel transfer
        access_control_admin_registry::cancel_admin_transfer(admin);

        // Check admin unchanged
        assert!(access_control_admin_registry::get_current_admin() == admin_addr);
        assert!(access_control_admin_registry::is_current_admin(admin_addr));

        // Check pending admin cleaned up
        assert!(!access_control_admin_registry::has_pending_admin());
    }

    // ===========================================
    // ERROR CONDITION TESTS
    // ===========================================

    #[test(admin = @movekit, non_admin = @0x123)]
    #[
        expected_failure(
            abort_code = E_NOT_ADMIN, location = movekit::access_control_admin_registry
        )
    ]
    fun test_transfer_admin_not_admin(
        admin: &signer, non_admin: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);
        access_control_admin_registry::transfer_admin(non_admin, @0x456);
    }

    #[test(admin = @movekit)]
    #[
        expected_failure(
            abort_code = E_SELF_TRANSFER_NOT_ALLOWED,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_transfer_admin_to_self(admin: &signer) {
        access_control_admin_registry::init_for_testing(admin);
        let admin_addr = signer::address_of(admin);

        // Should fail - cannot transfer to self
        access_control_admin_registry::transfer_admin(admin, admin_addr);
    }

    #[test(admin = @movekit, new_admin = @0x123, wrong_admin = @0x456)]
    #[
        expected_failure(
            abort_code = E_NOT_PENDING_ADMIN,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_accept_pending_admin_wrong_address(
        admin: &signer, new_admin: &signer, wrong_admin: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);
        let new_admin_addr = signer::address_of(new_admin);

        // Propose transfer to new_admin
        access_control_admin_registry::transfer_admin(admin, new_admin_addr);

        // Should fail - wrong_admin tries to accept
        access_control_admin_registry::accept_pending_admin(wrong_admin);
    }

    #[test(new_admin = @0x123)]
    #[
        expected_failure(
            abort_code = E_NOT_INITIALIZED,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_accept_pending_admin_not_initialized(new_admin: &signer) {
        // Should fail - admin registry not initialized
        access_control_admin_registry::accept_pending_admin(new_admin);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    #[
        expected_failure(
            abort_code = E_NO_PENDING_ADMIN,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_accept_pending_admin_no_pending(
        admin: &signer, new_admin: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);

        // Should fail - no pending admin transfer
        access_control_admin_registry::accept_pending_admin(new_admin);
    }

    #[test(admin = @movekit, non_admin = @0x123)]
    #[
        expected_failure(
            abort_code = E_NOT_ADMIN, location = movekit::access_control_admin_registry
        )
    ]
    fun test_cancel_admin_transfer_not_admin(
        admin: &signer, non_admin: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);
        // Should fail - not admin
        access_control_admin_registry::cancel_admin_transfer(non_admin);
    }

    #[test(admin = @movekit)]
    #[
        expected_failure(
            abort_code = E_NO_PENDING_ADMIN,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_cancel_admin_transfer_no_pending(admin: &signer) {
        access_control_admin_registry::init_for_testing(admin);

        // Should fail - no pending transfer to cancel
        access_control_admin_registry::cancel_admin_transfer(admin);
    }

    #[test(admin = @movekit)]
    #[
        expected_failure(
            abort_code = E_NO_PENDING_ADMIN,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_get_pending_admin_no_pending(admin: &signer) {
        access_control_admin_registry::init_for_testing(admin);
        // Should fail - no pending admin
        access_control_admin_registry::get_pending_admin();
    }

    // ===========================================
    // CORNER CASE TESTS
    // ===========================================

    #[test(admin = @movekit, new_admin = @0x123)]
    #[
        expected_failure(
            abort_code = E_NO_PENDING_ADMIN,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_double_accept_pending_admin_fails(
        admin: &signer, new_admin: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);
        let new_admin_addr = signer::address_of(new_admin);

        // Normal transfer
        access_control_admin_registry::transfer_admin(admin, new_admin_addr);

        // First accept succeeds
        access_control_admin_registry::accept_pending_admin(new_admin);

        // Second accept must fail
        access_control_admin_registry::accept_pending_admin(new_admin);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    #[
        expected_failure(
            abort_code = E_NOT_PENDING_ADMIN,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_accept_after_overwrite_fails(
        admin: &signer, new_admin: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);
        let new_admin_addr = signer::address_of(new_admin);

        // Original proposal
        access_control_admin_registry::transfer_admin(admin, new_admin_addr);

        // Admin overwrites with different address
        access_control_admin_registry::transfer_admin(admin, @0x456);

        // Original new_admin can no longer accept
        access_control_admin_registry::accept_pending_admin(new_admin);
    }

    #[test(admin = @movekit, new_admin1 = @0x123, new_admin2 = @0x456)]
    fun test_transfer_chain(
        admin: &signer, new_admin1: &signer, new_admin2: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);

        let admin_addr = signer::address_of(admin);
        let new_admin1_addr = signer::address_of(new_admin1);
        let new_admin2_addr = signer::address_of(new_admin2);

        // Transfer 1: admin -> new_admin1
        access_control_admin_registry::transfer_admin(admin, new_admin1_addr);
        access_control_admin_registry::accept_pending_admin(new_admin1);

        assert!(access_control_admin_registry::get_current_admin() == new_admin1_addr);
        assert!(!access_control_admin_registry::is_current_admin(admin_addr));

        // Transfer 2: new_admin1 -> new_admin2
        access_control_admin_registry::transfer_admin(new_admin1, new_admin2_addr);
        access_control_admin_registry::accept_pending_admin(new_admin2);

        assert!(access_control_admin_registry::get_current_admin() == new_admin2_addr);
        assert!(!access_control_admin_registry::is_current_admin(new_admin1_addr));
        assert!(!access_control_admin_registry::is_current_admin(admin_addr));
    }

    // ===========================================
    // SPECIAL ADDRESS TESTS
    // ===========================================

    #[test(admin = @movekit)]
    fun test_transfer_to_zero_address(admin: &signer) {
        access_control_admin_registry::init_for_testing(admin);

        // Should allow transfer to zero address (for renouncing)
        access_control_admin_registry::transfer_admin(admin, @0x0);

        assert!(access_control_admin_registry::has_pending_admin());
        assert!(access_control_admin_registry::get_pending_admin() == @0x0);
    }

    #[test(admin = @movekit)]
    #[
        expected_failure(
            abort_code = E_SELF_TRANSFER_NOT_ALLOWED,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_self_transfer_module_address(admin: &signer) {
        access_control_admin_registry::init_for_testing(admin);

        // Should fail - transferring to @movekit when admin is @movekit is self-transfer
        access_control_admin_registry::transfer_admin(admin, @movekit);
    }

    // ===========================================
    // VIEW FUNCTION TESTS
    // ===========================================

    #[test(admin = @movekit)]
    fun test_has_pending_admin_various_states(admin: &signer) {
        access_control_admin_registry::init_for_testing(admin);

        // Initially no pending admin
        assert!(!access_control_admin_registry::has_pending_admin());

        // After proposing transfer
        access_control_admin_registry::transfer_admin(admin, @0x123);
        assert!(access_control_admin_registry::has_pending_admin());

        // After canceling
        access_control_admin_registry::cancel_admin_transfer(admin);
        assert!(!access_control_admin_registry::has_pending_admin());
    }

    #[test]
    fun test_has_pending_admin_nonexistent_address() {
        // Should return false for uninitialized registry
        assert!(!access_control_admin_registry::has_pending_admin());
    }

    // ===========================================
    // SECURITY TESTS
    // ===========================================

    #[test(admin = @movekit, attacker = @0x999)]
    #[
        expected_failure(
            abort_code = E_NOT_ADMIN, location = movekit::access_control_admin_registry
        )
    ]
    fun test_privilege_escalation_prevention_transfer(
        admin: &signer, attacker: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);
        // Attacker tries to transfer admin to themselves without being admin
        access_control_admin_registry::transfer_admin(
            attacker, signer::address_of(attacker)
        );
    }

    #[test(admin = @movekit, attacker = @0x999)]
    #[
        expected_failure(
            abort_code = E_NOT_ADMIN, location = movekit::access_control_admin_registry
        )
    ]
    fun test_privilege_escalation_prevention_cancel(
        admin: &signer, attacker: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);
        // Attacker tries to cancel admin transfer without being admin
        access_control_admin_registry::cancel_admin_transfer(attacker);
    }

    #[test(admin = @movekit, attacker = @0x999)]
    #[
        expected_failure(
            abort_code = E_NOT_PENDING_ADMIN,
            location = movekit::access_control_admin_registry
        )
    ]
    fun test_unauthorized_accept_prevention(
        admin: &signer, attacker: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);

        // Admin proposes transfer to someone else
        access_control_admin_registry::transfer_admin(admin, @0x123);

        // Attacker tries to accept transfer meant for someone else
        access_control_admin_registry::accept_pending_admin(attacker);
    }

    // ===========================================
    // EDGE CASE TESTS
    // ===========================================

    #[test(admin = @movekit)]
    fun test_multiple_proposal_overwrites(admin: &signer) {
        access_control_admin_registry::init_for_testing(admin);

        // Multiple proposals should overwrite each other
        access_control_admin_registry::transfer_admin(admin, @0x111);
        assert!(access_control_admin_registry::get_pending_admin() == @0x111);

        access_control_admin_registry::transfer_admin(admin, @0x222);
        assert!(access_control_admin_registry::get_pending_admin() == @0x222);

        access_control_admin_registry::transfer_admin(admin, @0x333);
        assert!(access_control_admin_registry::get_pending_admin() == @0x333);

        // Only the last proposal is valid
        assert!(access_control_admin_registry::get_pending_admin() != @0x111);
        assert!(access_control_admin_registry::get_pending_admin() != @0x222);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_pending_admin_cleanup_after_accept(
        admin: &signer, new_admin: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);

        let new_admin_addr = signer::address_of(new_admin);

        // Propose and accept transfer
        access_control_admin_registry::transfer_admin(admin, new_admin_addr);
        access_control_admin_registry::accept_pending_admin(new_admin);

        // No longer has pending admin after transfer
        assert!(!access_control_admin_registry::has_pending_admin());
        assert!(!access_control_admin_registry::has_pending_admin());
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_pending_admin_cleanup_after_cancel(
        admin: &signer, new_admin: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);

        let new_admin_addr = signer::address_of(new_admin);

        // Propose and cancel transfer
        access_control_admin_registry::transfer_admin(admin, new_admin_addr);
        access_control_admin_registry::cancel_admin_transfer(admin);

        // No longer has pending admin after cancellation
        assert!(!access_control_admin_registry::has_pending_admin());
        assert!(!access_control_admin_registry::has_pending_admin());
    }

    // ===========================================
    // STORAGE LEAK CHECKS
    // ===========================================

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_no_pending_admin_leaks_after_accept(
        admin: &signer, new_admin: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);

        let new_admin_addr = signer::address_of(new_admin);

        // Setup transfer
        access_control_admin_registry::transfer_admin(admin, new_admin_addr);

        // Verify pending admin exists
        assert!(access_control_admin_registry::has_pending_admin());

        // Accept transfer
        access_control_admin_registry::accept_pending_admin(new_admin);

        // Verify NO pending admin state exists
        assert!(!access_control_admin_registry::has_pending_admin());
        assert!(!access_control_admin_registry::has_pending_admin());
    }

    #[test(admin = @movekit)]
    fun test_no_pending_admin_leaks_after_cancel(admin: &signer) {
        access_control_admin_registry::init_for_testing(admin);

        // Setup transfer
        access_control_admin_registry::transfer_admin(admin, @0x123);

        // Verify pending admin exists
        assert!(access_control_admin_registry::has_pending_admin());

        // Cancel transfer
        access_control_admin_registry::cancel_admin_transfer(admin);

        // Verify NO pending admin state exists
        assert!(!access_control_admin_registry::has_pending_admin());
    }

    #[test(admin = @movekit)]
    fun test_no_pending_admin_leaks_after_overwrite(admin: &signer) {
        access_control_admin_registry::init_for_testing(admin);

        // Multiple overwrites
        access_control_admin_registry::transfer_admin(admin, @0x111);
        access_control_admin_registry::transfer_admin(admin, @0x222);
        access_control_admin_registry::transfer_admin(admin, @0x333);

        // Should only have ONE pending admin (the latest)
        assert!(access_control_admin_registry::has_pending_admin());
        assert!(access_control_admin_registry::get_pending_admin() == @0x333);

        // Cancel and verify clean slate
        access_control_admin_registry::cancel_admin_transfer(admin);
        assert!(!access_control_admin_registry::has_pending_admin());
    }

    // ===========================================
    // CONCURRENT/RAPID SUCCESSION TESTS
    // ===========================================

    #[test(admin = @movekit)]
    fun test_rapid_proposal_overwrites(admin: &signer) {
        access_control_admin_registry::init_for_testing(admin);

        // Rapid succession proposals (testing internal state consistency)
        access_control_admin_registry::transfer_admin(admin, @0x111);
        assert!(access_control_admin_registry::get_pending_admin() == @0x111);

        access_control_admin_registry::transfer_admin(admin, @0x222);
        assert!(access_control_admin_registry::get_pending_admin() == @0x222);

        access_control_admin_registry::transfer_admin(admin, @0x333);
        assert!(access_control_admin_registry::get_pending_admin() == @0x333);

        // Verify only the last one is valid
        assert!(access_control_admin_registry::get_pending_admin() != @0x111);
        assert!(access_control_admin_registry::get_pending_admin() != @0x222);
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_propose_cancel_propose_sequence(
        admin: &signer, new_admin: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);

        let new_admin_addr = signer::address_of(new_admin);

        // Rapid sequence: propose -> cancel -> propose -> accept
        access_control_admin_registry::transfer_admin(admin, new_admin_addr);
        access_control_admin_registry::cancel_admin_transfer(admin);
        access_control_admin_registry::transfer_admin(admin, new_admin_addr);
        access_control_admin_registry::accept_pending_admin(new_admin);

        // Verify final state is correct
        assert!(access_control_admin_registry::get_current_admin() == new_admin_addr);
        assert!(!access_control_admin_registry::has_pending_admin());
    }

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_interleaved_operations(admin: &signer, new_admin: &signer) {
        access_control_admin_registry::init_for_testing(admin);

        let new_admin_addr = signer::address_of(new_admin);

        // Complex sequence testing state machine robustness
        access_control_admin_registry::transfer_admin(admin, @0x999); // Propose to someone else
        access_control_admin_registry::transfer_admin(admin, new_admin_addr); // Overwrite

        // Verify state is correct before accept
        assert!(access_control_admin_registry::get_pending_admin() == new_admin_addr);
        assert!(
            access_control_admin_registry::get_current_admin()
                == signer::address_of(admin)
        );

        // Accept should work
        access_control_admin_registry::accept_pending_admin(new_admin);

        // Verify final state
        assert!(access_control_admin_registry::get_current_admin() == new_admin_addr);
    }

    // ===========================================
    // EDGE CASE OPERATIONAL TESTS
    // ===========================================

    #[test(admin = @movekit)]
    fun test_view_functions_consistency_under_state_changes(
        admin: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);

        let admin_addr = signer::address_of(admin);

        // Initial state verification
        assert!(access_control_admin_registry::is_current_admin(admin_addr));
        assert!(access_control_admin_registry::get_current_admin() == admin_addr);
        assert!(!access_control_admin_registry::has_pending_admin());

        // After proposal
        access_control_admin_registry::transfer_admin(admin, @0x123);
        assert!(access_control_admin_registry::is_current_admin(admin_addr)); // Still current
        assert!(access_control_admin_registry::get_current_admin() == admin_addr); // Still current
        assert!(access_control_admin_registry::has_pending_admin()); // Now has pending

        // After cancel
        access_control_admin_registry::cancel_admin_transfer(admin);
        assert!(access_control_admin_registry::is_current_admin(admin_addr)); // Still current
        assert!(access_control_admin_registry::get_current_admin() == admin_addr); // Still current
        assert!(!access_control_admin_registry::has_pending_admin()); // No longer pending
    }

    #[test(admin = @movekit)]
    fun test_resource_existence_consistency(admin: &signer) {
        access_control_admin_registry::init_for_testing(admin);

        // AdminRegistry should always exist after initialization
        assert!(
            access_control_admin_registry::is_current_admin(signer::address_of(admin)),
            0
        );

        // These operations shouldn't affect AdminRegistry existence
        access_control_admin_registry::transfer_admin(admin, @0x123);
        assert!(
            access_control_admin_registry::is_current_admin(signer::address_of(admin)),
            1
        );

        access_control_admin_registry::cancel_admin_transfer(admin);
        assert!(
            access_control_admin_registry::is_current_admin(signer::address_of(admin)),
            2
        );

        // Pending admin state should be created and destroyed properly
        assert!(!access_control_admin_registry::has_pending_admin());

        access_control_admin_registry::transfer_admin(admin, @0x123);
        assert!(access_control_admin_registry::has_pending_admin());

        access_control_admin_registry::cancel_admin_transfer(admin);
        assert!(!access_control_admin_registry::has_pending_admin());
    }

    // ===========================================
    // SYSTEM INVARIANT TESTS
    // ===========================================

    #[test(admin = @movekit, new_admin = @0x123)]
    fun test_admin_uniqueness_invariant(
        admin: &signer, new_admin: &signer
    ) {
        access_control_admin_registry::init_for_testing(admin);

        let admin_addr = signer::address_of(admin);
        let new_admin_addr = signer::address_of(new_admin);

        // Throughout the entire transfer process, exactly one address should be admin

        // Initial: admin is admin, new_admin is not
        assert!(access_control_admin_registry::is_current_admin(admin_addr));
        assert!(!access_control_admin_registry::is_current_admin(new_admin_addr));

        // During proposal: admin still admin, new_admin still not
        access_control_admin_registry::transfer_admin(admin, new_admin_addr);
        assert!(access_control_admin_registry::is_current_admin(admin_addr));
        assert!(!access_control_admin_registry::is_current_admin(new_admin_addr));

        // After transfer: new_admin is admin, admin is not
        access_control_admin_registry::accept_pending_admin(new_admin);
        assert!(!access_control_admin_registry::is_current_admin(admin_addr));
        assert!(access_control_admin_registry::is_current_admin(new_admin_addr));

        // Verify no other addresses are admin
        assert!(!access_control_admin_registry::is_current_admin(@0x999));
        assert!(!access_control_admin_registry::is_current_admin(@movekit));
    }

    #[test(admin = @movekit)]
    fun test_state_machine_invariants(admin: &signer) {
        access_control_admin_registry::init_for_testing(admin);

        let admin_addr = signer::address_of(admin);

        // Invariant: AdminRegistry always exists after initialization
        assert!(access_control_admin_registry::get_current_admin() == admin_addr);

        // Invariant: Pending admin state exists iff there's an active proposal
        assert!(!access_control_admin_registry::has_pending_admin());

        access_control_admin_registry::transfer_admin(admin, @0x123);
        assert!(access_control_admin_registry::has_pending_admin());

        access_control_admin_registry::cancel_admin_transfer(admin);
        assert!(!access_control_admin_registry::has_pending_admin());

        // Invariant: get_current_admin() always returns a valid address
        let current = access_control_admin_registry::get_current_admin();
        assert!(current == admin_addr); // Should be a concrete address, not null
    }
}
