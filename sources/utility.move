module wb::utility {
    use std::vector;
    use std::string::{String, utf8};
    use std::option::{Self, Option};

    // use sui::address;
    use sui::ed25519;
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::table_vec::{Self, TableVec};
    use sui::vec_map::{Self, VecMap};
    use sui::table;
    use sui::dynamic_object_field as ofield;

    friend wb::loyalty;

    // Track the current version of the module
    const VERSION: u64 = 2;

    /// Not the right admin for this `Config`.
    const ENotAdmin: u64 = 0;

    /// Migration is not an upgrade
    const ENotUpgrade: u64 = 1;

    /// Calling functions from the wrong package version
    const EWrongVersion: u64 = 2;

    /// The provided nonce is already used.
    const ENonceAlreadyUsed: u64 = 3;

    /// The provided signature is invalid.
    const EInvalidSignature: u64 = 4;

    // ======== Types =========

    /// An auth type for actions within nft-protocol
    struct Witness has drop {}

    /// Admin capability.
    struct AdminCap has key, store {
        id: UID,
    }

    /// The `Config` struct. It's used to store
    /// common configs for multiple modules in this package.
    struct Config has key, store {
        id: UID,
        version: u64,
        admin: ID,
        signer: vector<u8>,
        used_nonces: TableVec<u64>,

        // Hold the collection ids created in other modules.
        // Note that the collection id need to be added by admin
        // first before we can mint NFTs in those modules.
        //
        // Use `add_collection` function below to add collection.
        collections: VecMap<String, ID>,
    }

    // ======== Initialization ========

    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap { id: object::new(ctx) };

        // mainnet signer
        let signer_pubkey = x"b8e5842115f34580cf722e2ee0f54a29ce44a4c3d91de50d170af0d55f72d17f";
        let config = create_config(object::id(&admin_cap), signer_pubkey, ctx);
        transfer::public_share_object(config);

        transfer::public_transfer(admin_cap, tx_context::sender(ctx));
    }

    // ======== Functions =========

    fun create_config(admin: ID, signer_pubkey: vector<u8>, ctx: &mut TxContext): Config {
        Config {
            id: object::new(ctx),
            version: VERSION,
            admin,
            signer: signer_pubkey,
            used_nonces: table_vec::empty<u64>(ctx),
            collections: vec_map::empty(),
        }
    }

    /// Entry function. Change the signer pubkey.
    entry fun set_signer(_: &AdminCap, config: &mut Config, signer: vector<u8>, _: &mut TxContext) {
        config.signer = signer;
    }

    /// Entry function. Add collection id to the `Config` struct.
    entry fun add_collection(
        _: &AdminCap, config: &mut Config, name: String, value: ID
    ) {
        add_collection_internal(config, name, value)
    }

    entry fun migrate(a: &AdminCap, c: &mut Config) {
        assert!(c.admin == object::id(a), ENotAdmin);
        assert!(c.version < VERSION, ENotUpgrade);
        c.version = VERSION;
    }

    entry fun add_used_nonces_table_dof(_: &AdminCap, c: &mut Config, ctx: &mut TxContext) {
        let used_nonces = table::new<u64, bool>(ctx);
        ofield::add(&mut c.id, b"used_nonces", used_nonces);
    }

    public(friend) fun mark_nonce_used(config: &mut Config, nonce: u64) {
        // table_vec::push_back(&mut config.used_nonces, nonce);
        let used_nonces = ofield::borrow_mut(&mut config.id, b"used_nonces");
        table::add(used_nonces, nonce, true)
    }

    public fun assert_version(config: &Config) {
        assert!(config.version == VERSION, EWrongVersion)
    }

    public fun assert_nonce(config: &Config, nonce: &u64) {
        assert!(
            nonce_used(config, nonce) == false,
            ENonceAlreadyUsed,
        )
    }

    public fun assert_signature(config: &Config, signature: &vector<u8>, hashed_msg: &vector<u8>) {
        assert!(
            signature_valid(config, signature, hashed_msg) == true,
            EInvalidSignature,
        )
    }

    // ======== View Functions ========

    public fun nonce_used(config: &Config, nonce: &u64): bool {
        // option::is_some(&find_nonce_from_table_vec(&config.used_nonces, nonce))
        let used_nonces = ofield::borrow(&config.id, b"used_nonces");
        table::contains<u64, bool>(used_nonces, *nonce)
    }

    public fun signature_valid(config: &Config, signature: &vector<u8>, hashed_msg: &vector<u8>): bool {
        ed25519::ed25519_verify(signature, &config.signer, hashed_msg)
    }

    public fun collection_id_by_name(config: &Config, name: vector<u8>): ID {
        *vec_map::get(&config.collections, &utf8(name))
    }

    // ======== Helper Functions ========

    public fun itoa(value: u64): String {
        if (value == 0) {
            return utf8(b"0")
        };
        let buffer = vector::empty<u8>();
        while (value != 0) {
            vector::push_back(&mut buffer, ((48 + value % 10) as u8));
            value = value / 10;
        };
        vector::reverse(&mut buffer);
        utf8(buffer)
    }

    fun find_nonce_from_table_vec(used_nonces: &TableVec<u64>, nonce: &u64): Option<u64> {
        let length = table_vec::length(used_nonces);
        let i = 0;
        while (i < length) {
            if (table_vec::borrow(used_nonces, i) == nonce) {
                return option::some(i)
            };
            i = i + 1;
        };
        option::none()
    }

    fun add_collection_internal(config: &mut Config, name: String, value: ID) {
        vec_map::insert(&mut config.collections, name, value)
    }

    // ======== Tests Helpers ========

    #[test_only]
    public fun test_create_admin_cap(ctx: &mut TxContext): AdminCap {
        AdminCap {
            id: object::new(ctx)
        }
    }

    #[test_only]
    public fun test_create_config(admin: ID, signer_pubkey: vector<u8>, ctx: &mut TxContext): Config {
        create_config(admin, signer_pubkey, ctx)
    }

    #[test_only]
    public fun test_add_collection(config: &mut Config, name: String, value: ID) {
        add_collection_internal(config, name, value)
    }
}

#[test_only]
module wb::utility_test {
    use sui::test_scenario::{Self, Scenario};
    use sui::transfer;
    use sui::object;

    use wb::utility;

    const ADMIN: address = @0xAA;
    const OPERATOR: address = @0xBB;
    const USER: address = @0xCC;

    const SIGNER_PUBKEY: vector<u8> = x"93e92bc75a7b7f47698844f12d1a009b5ac97b3ba60158e2b385a987ce6c6aa5";

    public fun scenario_with_utility_initialized(): Scenario {
        let scenario_ = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_;

        test_scenario::next_tx(scenario, ADMIN);
        {
            let ctx = test_scenario::ctx(scenario);

            let admin_cap = utility::test_create_admin_cap(ctx);
            let admin_cap_id = object::id(&admin_cap);

            let config = utility::test_create_config(admin_cap_id, SIGNER_PUBKEY, ctx);
            transfer::public_share_object(config);

            transfer::public_transfer(
                admin_cap,
                ADMIN,
            );
        };

        return scenario_
    }
}
