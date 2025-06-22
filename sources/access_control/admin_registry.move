module movekit::access_control_admin_registry {
    use std::signer;
    use std::event;

    friend movekit::access_control_core;

    struct AdminRegistry has key {
        current_admin: address
    }

    struct PendingAdmin has key, drop {
        pending_admin: address
    }

    // -- Constants -- //
    const E_NOT_INITIALIZED: u64 = 0;
    const E_NOT_ADMIN: u64 = 1;
    const E_SELF_TRANSFER_NOT_ALLOWED: u64 = 2;
    const E_NO_PENDING_ADMIN: u64 = 3;
    const E_NOT_PENDING_ADMIN: u64 = 4;
    const E_ALREADY_INITIALIZED: u64 = 5;

    // -- Events -- //
    #[event]
    struct AdminTransferProposed has copy, drop, store {
        current_admin: address,
        pending_admin: address
    }

    #[event]
    struct AdminTransferCompleted has copy, drop, store {
        old_admin: address,
        new_admin: address
    }

    #[event]
    struct AdminTransferCanceled has copy, drop, store {
        admin: address,
        canceled_pending: address
    }

    // -- Public Functions -- //

    #[view]
    public fun get_current_admin(): address acquires AdminRegistry {
        assert!(exists<AdminRegistry>(@movekit), E_NOT_INITIALIZED);
        (&AdminRegistry[@movekit]).current_admin
    }

    #[view]
    public fun is_current_admin(addr: address): bool acquires AdminRegistry {
        get_current_admin() == addr
    }

    public fun require_admin(admin: &signer) acquires AdminRegistry {
        assert!(exists<AdminRegistry>(@movekit), E_NOT_INITIALIZED);
        let registry = &AdminRegistry[@movekit];
        assert!(registry.current_admin == signer::address_of(admin), E_NOT_ADMIN);
    }

    /// Current admin proposes new admin
    public fun transfer_admin(admin: &signer, new_admin: address) acquires AdminRegistry, PendingAdmin {
        require_admin(admin);
        let admin_addr = signer::address_of(admin);
        assert!(new_admin != admin_addr, E_SELF_TRANSFER_NOT_ALLOWED);

        // Set or update pending admin
        if (exists<PendingAdmin>(admin_addr)) {
            let pending = &mut PendingAdmin[admin_addr];
            pending.pending_admin = new_admin;
        } else {
            move_to(admin, PendingAdmin { pending_admin: new_admin });
        };

        event::emit(
            AdminTransferProposed { current_admin: admin_addr, pending_admin: new_admin }
        );
    }

    /// New admin accepts the transfer
    public fun accept_pending_admin(new_admin: &signer) acquires AdminRegistry, PendingAdmin {
        let new_admin_addr = signer::address_of(new_admin);
        let current_admin_addr = get_current_admin();

        // Check that there's a pending admin transfer
        assert!(exists<PendingAdmin>(current_admin_addr), E_NO_PENDING_ADMIN);

        // Get the pending admin info
        let pending = &PendingAdmin[current_admin_addr];

        // Verify that the caller is the intended new admin
        assert!(pending.pending_admin == new_admin_addr, E_NOT_PENDING_ADMIN);

        // Update AdminRegistry to point to new admin
        let registry = &mut AdminRegistry[@movekit];
        let old_admin = registry.current_admin;
        registry.current_admin = new_admin_addr;

        // Clean up: Remove PendingAdmin resource from old admin's address
        let _removed_pending = move_from<PendingAdmin>(current_admin_addr);

        // Emit completion event
        event::emit(
            AdminTransferCompleted { old_admin: old_admin, new_admin: new_admin_addr }
        );
    }

    /// Cancel pending admin transfer
    public fun cancel_admin_transfer(admin: &signer) acquires AdminRegistry, PendingAdmin {
        let admin_addr = signer::address_of(admin);
        require_admin(admin);
        assert!(exists<PendingAdmin>(admin_addr), E_NO_PENDING_ADMIN);

        let pending = move_from<PendingAdmin>(admin_addr);

        event::emit(
            AdminTransferCanceled {
                admin: admin_addr,
                canceled_pending: pending.pending_admin
            }
        );
    }

    #[view]
    /// Get pending admin address
    public fun get_pending_admin(): address acquires AdminRegistry, PendingAdmin {
        let current_admin = get_current_admin();
        assert!(exists<PendingAdmin>(current_admin), E_NO_PENDING_ADMIN);
        (&PendingAdmin[current_admin]).pending_admin
    }

    #[view]
    /// Check if there's a pending admin transfer
    public fun has_pending_admin(admin: address): bool {
        exists<PendingAdmin>(admin)
    }

    /// Allow friend modules to initialize admin registry (idempotent)
    friend fun init_admin_registry(admin: &signer) {
        if (!exists<AdminRegistry>(@movekit)) {
            let admin_addr = signer::address_of(admin);
            move_to(admin, AdminRegistry { current_admin: admin_addr });
        }
    }

    // -- Private Functions -- //

    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        // admin signer represents @movekit during deployment
        move_to(admin, AdminRegistry { current_admin: admin_addr });
    }

    #[test_only]
    public fun init_for_testing(admin: &signer) {
        init_module(admin);
    }
}
