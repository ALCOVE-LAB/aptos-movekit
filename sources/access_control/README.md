# Access Control Core

Role-based access control (RBAC) system for Aptos Move applications.

## Features
- Type-safe role management using phantom types
- Admin role transfer capabilities  
- Event emission for audit trails

## Usage
```move
use movekit::access_control_core;

struct Treasurer has copy, drop {}

public entry fun withdraw(account: &signer, amount: u64) {
    access_control_core::require_role<Treasurer>(account);
    // withdrawal logic
}