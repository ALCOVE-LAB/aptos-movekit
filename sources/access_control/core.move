module movekit::access_control_core {

    // -- Std & Framework Helpers -- //

    use std::signer;
    use std::event;

    // -- Types Section -- //

    /// Marker resource: "address *A* holds role *T*"
    struct Role<phantom T> has key, drop {}

    /// Built-in admin tag.  Other modules may define their own empty structs.
    struct Admin has copy, drop {}

    // -- Constants Section -- //

    /// Error codes
    const E_NOT_ADMIN: u64 = 0;
    const E_ALREADY_HAS_ROLE: u64 = 1;
    const E_NO_SUCH_ROLE: u64 = 2;

    // -- Events Section -- //

    #[event]
    struct RoleGrantedEvent<phantom T> has copy, drop, store {
        admin: address,
        target: address
    }

    #[event]
    struct RoleRevokedEvent<phantom T> has copy, drop, store {
        admin: address,
        target: address
    }

    #[event]
    struct RoleTransferredEvent<phantom T> has copy, drop, store {
        admin: address,
        from: address,
        to: address
    }

    // -- External Functions Section -- //

    /// Transfers the Admin role from one address to another
    public fun transfer_admin(admin: &signer, new_admin: &signer) acquires Role {
        assert!(
            has_role<Admin>(signer::address_of(admin)),
            E_NOT_ADMIN
        );

        assert!(
            !exists<Role<Admin>>(signer::address_of(new_admin)),
            E_ALREADY_HAS_ROLE
        );

        move_from<Role<Admin>>(signer::address_of(admin));
        move_to<Role<Admin>>(new_admin, Role<Admin> {});

        event::emit(
            RoleTransferredEvent<Admin> {
                admin: signer::address_of(admin),
                from: signer::address_of(admin),
                to: signer::address_of(new_admin)
            }
        );
    }

    /// Grants a role to an address
    public fun grant_role<T>(admin: &signer, target: &signer) {
        grant_role_internal<T>(admin, target);
    }

    /// Revokes a role from an address
    public fun revoke_role<T>(admin: &signer, target: address) acquires Role {
        revoke_role_internal<T>(admin, target);
    }

    /// Transfers a role from one address to another
    public fun transfer_role<T>(
        admin: &signer, from: &signer, to: &signer
    ) acquires Role {
        assert!(
            has_role<Admin>(signer::address_of(admin)),
            E_NOT_ADMIN
        );

        assert!(
            exists<Role<T>>(signer::address_of(from)),
            E_NO_SUCH_ROLE
        );

        assert!(
            !exists<Role<T>>(signer::address_of(to)),
            E_ALREADY_HAS_ROLE
        );

        move_from<Role<T>>(signer::address_of(from));
        move_to<Role<T>>(to, Role<T> {});

        event::emit(
            RoleTransferredEvent<T> {
                admin: signer::address_of(admin),
                from: signer::address_of(from),
                to: signer::address_of(to)
            }
        );
    }

    // View helper to check whether an address currently holds role T
    #[view]
    public fun has_role<T>(addr: address): bool {
        exists<Role<T>>(addr)
    }

    // -- Internal Functions Section -- //

    /// Bootstrap: give the deployer the Admin role and publish event handles
    fun init_module(admin: &signer) {
        // Grant Admin to caller
        assert!(
            !exists<Role<Admin>>(signer::address_of(admin)),
            E_ALREADY_HAS_ROLE
        );
        move_to<Role<Admin>>(admin, Role<Admin> {});

        event::emit(
            RoleGrantedEvent<Admin> {
                admin: signer::address_of(admin),
                target: signer::address_of(admin)
            }
        );
    }

    // Public init function for testing only
    #[test_only]
    public fun init_for_testing(admin: &signer) {
        init_module(admin);
    }

    /// Grants a role to an address
    fun grant_role_internal<T>(admin: &signer, target: &signer) {
        assert!(
            has_role<Admin>(signer::address_of(admin)),
            E_NOT_ADMIN
        );

        assert!(
            !exists<Role<T>>(signer::address_of(target)),
            E_ALREADY_HAS_ROLE
        );
        move_to<Role<T>>(target, Role<T> {});

        event::emit(
            RoleGrantedEvent<T> {
                admin: signer::address_of(admin),
                target: signer::address_of(target)
            }
        );
    }

    /// Revokes a role from an address
    fun revoke_role_internal<T>(admin: &signer, target: address) acquires Role {
        assert!(
            has_role<Admin>(signer::address_of(admin)),
            E_NOT_ADMIN
        );

        assert!(exists<Role<T>>(target), E_NO_SUCH_ROLE);
        move_from<Role<T>>(target);

        event::emit(
            RoleRevokedEvent<T> { admin: signer::address_of(admin), target: target }
        );
    }
}
