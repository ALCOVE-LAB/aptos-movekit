module movekit::access_control_admin_registry {
    use std::signer;
    use std::event;
    use std::option::{Self, Option};

    friend movekit::access_control_core;

    struct AdminRegistry has key {
        current_admin: address,
        pending_admin: Option<address>
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
    public fun transfer_admin(admin: &signer, new_admin: address) acquires AdminRegistry {
        require_admin(admin);
        let admin_addr = signer::address_of(admin);
        assert!(new_admin != admin_addr, E_SELF_TRANSFER_NOT_ALLOWED);

        // Set pending admin in registry
        let registry = &mut AdminRegistry[@movekit];
        registry.pending_admin = option::some(new_admin);

        event::emit(
            AdminTransferProposed { current_admin: admin_addr, pending_admin: new_admin }
        );
    }

    /// New admin accepts the transfer
    public fun accept_pending_admin(new_admin: &signer) acquires AdminRegistry {
        let new_admin_addr = signer::address_of(new_admin);
        assert!(exists<AdminRegistry>(@movekit), E_NOT_INITIALIZED);
        let registry = &mut AdminRegistry[@movekit];

        // Check that there's a pending admin transfer
        assert!(option::is_some(&registry.pending_admin), E_NO_PENDING_ADMIN);

        // Verify that the caller is the intended new admin
        let pending_admin_addr = *option::borrow(&registry.pending_admin);
        assert!(pending_admin_addr == new_admin_addr, E_NOT_PENDING_ADMIN);

        // Update registry
        let old_admin = registry.current_admin;
        registry.current_admin = new_admin_addr;
        registry.pending_admin = option::none();

        // Emit completion event
        event::emit(
            AdminTransferCompleted { old_admin: old_admin, new_admin: new_admin_addr }
        );
    }

    /// Cancel pending admin transfer
    public fun cancel_admin_transfer(admin: &signer) acquires AdminRegistry {
        require_admin(admin);
        let registry = &mut AdminRegistry[@movekit];
        assert!(option::is_some(&registry.pending_admin), E_NO_PENDING_ADMIN);

        let canceled_pending = *option::borrow(&registry.pending_admin);
        registry.pending_admin = option::none();

        event::emit(
            AdminTransferCanceled {
                admin: signer::address_of(admin),
                canceled_pending: canceled_pending
            }
        );
    }

    #[view]
    /// Get pending admin address
    public fun get_pending_admin(): address acquires AdminRegistry {
        assert!(exists<AdminRegistry>(@movekit), E_NOT_INITIALIZED);
        let registry = &AdminRegistry[@movekit];
        assert!(option::is_some(&registry.pending_admin), E_NO_PENDING_ADMIN);
        *option::borrow(&registry.pending_admin)
    }

    #[view]
    /// Check if there's a pending admin transfer
    public fun has_pending_admin(): bool acquires AdminRegistry {
        if (!exists<AdminRegistry>(@movekit)) return false;
        let registry = &AdminRegistry[@movekit];
        option::is_some(&registry.pending_admin)
    }

    /// Allow friend modules to initialize admin registry (idempotent)
    friend fun init_admin_registry(admin: &signer) {
        if (!exists<AdminRegistry>(@movekit)) {
            let admin_addr = signer::address_of(admin);
            move_to(
                admin,
                AdminRegistry { current_admin: admin_addr, pending_admin: option::none() }
            );
        }
    }

    // -- Private Functions -- //

    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        // admin signer represents @movekit during deployment
        move_to(
            admin,
            AdminRegistry { current_admin: admin_addr, pending_admin: option::none() }
        );
    }

    #[test_only]
    public fun init_for_testing(admin: &signer) {
        init_module(admin);
    }
}
