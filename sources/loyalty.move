module wb::loyalty {
    use std::ascii;
    use std::option;
    use std::vector as vec;
    use std::string::{String, utf8};

    use sui::hash;
    use sui::bcs;
    use sui::address;
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::event::emit;
    use sui::transfer;
    use sui::package::{Self, Publisher};
    use sui::display::{Self, Display};

    use nft_protocol::collection::{Self, Collection};
    use nft_protocol::display_info;
    use nft_protocol::attributes::{Self, Attributes};
    use nft_protocol::mint_event;
    use nft_protocol::royalty;
    use nft_protocol::royalty_strategy_bps;
    use ob_permissions::witness::{Self, Witness as DelegatedWitness};
    use ob_request::transfer_request;

    use wb::utility::{Self, AdminCap, Config};

    /// Mismatch `Ticket`'s type with `Box`'s type
    /// while applying that ticket to a box.
    const ETicketTypeMisMatch: u64 = 0;

    // ======== Types =========

    /// An auth type for actions within nft-protocol
    struct Witness has drop {}

    /// OTW for constructing the Publisher
    struct LOYALTY has drop {}

    /// A Box is used to store loyalty points of user.
    struct Box has key {
        id: UID,
        type: u64,
        name: String,
        infinity_credits: u64,
        attributes: Attributes,
    }

    /// A Ticket is issued by the users, when they're willing
    /// to sell their loyalty points on marketplace.
    struct Ticket has key, store {
        id: UID,
        type: u64,
        name: String,
        infinity_credits: u64,
        attributes: Attributes,
    }

    // ========= Events =========

    /// Event when new `Box` is created.
    struct BoxCreated has copy, drop {
        id: ID,
        nonce: u64,
        type: u64,
        name: String,
        infinity_credits: u64,
        recipient: address,
    }

    /// Event when loyalty points in `Box` is synced.
    struct BoxLoyaltyPointsSynced has copy, drop {
        id: ID,
        nonce: u64,
        infinity_credits: u64,
        by: address,
    }

    /// Event when loyalty points in `Box` is updated.
    struct BoxLoyaltyPointsUpdated has copy, drop {
        id: ID,
        infinity_credits: u64,
        by: address,
    }

    /// Event when new `Ticket` is created.
    struct TicketCreated has copy, drop {
        id: ID,
        box_id: ID,
        nonce: u64,
        type: u64,
        name: String,
        infinity_credits: u64,
        recipient: address,
    }

    /// Event when a `Ticket` is applied.
    struct TicketApplied has copy, drop {
        box_id: ID,
        ticket_id: ID,
        nonce: u64,
        applied_infinity_credits: u64,
        by: address,
    }

    // ======== Functions =========

    fun init(otw: LOYALTY, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);

        let (ticket_col, ticket_mint_cap) = collection::create_with_mint_cap<LOYALTY, Ticket>(
             &otw, option::none(), ctx
        );

        // init Publisher
        let publisher = package::claim(otw, ctx);

        // init box Display
        let box_display = create_box_display(&publisher, ctx);
        transfer::public_transfer(box_display, sender);

        // init ticket Display
        let ticket_display = create_ticket_display(&publisher, ctx);
        transfer::public_transfer(ticket_display, sender);

        // init DelegatedWitness for ticket collection
        let dwt = witness::from_witness<Ticket, Witness>(Witness {});

        // add display_info domain to ticket collection
        collection::add_domain(
            dwt,
            &mut ticket_col,
            display_info::new(
                utf8(b"Worlds Beyond Infinity Tickets Collection"),
                utf8(b"Worlds Beyond Infinity Tickets"),
            )
        );

        // add royalty domain to ticket collection
        royalty_strategy_bps::create_domain_and_add_strategy(
            dwt, &mut ticket_col, royalty::from_address(sender, ctx), 500, ctx,
        );

        let (ticket_transfer_policy, ticket_transfer_cap) = transfer_request::init_policy<Ticket>(&publisher, ctx);

        royalty_strategy_bps::enforce(&mut ticket_transfer_policy, &ticket_transfer_cap);

        transfer::public_share_object(ticket_transfer_policy);
        transfer::public_transfer(ticket_transfer_cap, sender);

        transfer::public_transfer(ticket_mint_cap, sender);
        transfer::public_share_object(ticket_col);

        transfer::public_transfer(publisher, sender);
    }

    fun create_box_display(publisher: &Publisher, ctx: &mut TxContext): Display<Box> {
        let keys = vector[
            utf8(b"name"),
            utf8(b"infinity_credits"),
            utf8(b"link"),
            utf8(b"image_url"),
            utf8(b"description"),
            utf8(b"project_url"),
            utf8(b"creator"),
        ];

        let values = vector[
            utf8(b"{name}"),
            utf8(b"{infinity_credits}"),
            utf8(b"https://worldsbeyondnft.com/loyalty-boxes/{id}"),
            utf8(b"https://cdn.worldsbeyondnft.com/nft/loyalty-boxes/{type}.jpg"),
            utf8(b"The Infinity Passport is a loyalty program that rewards players for playing games in our ecosystem. Players earn Infinity Credits on their Infinity Passports for playing Worlds Beyond games, winning competitions, completing challenges and more. These Infinity Credits can be redeemed for a variety of rewards, including WBITS mining keys, in-game items, exclusive content, and real-world prizes. Be sure to follow news in our Discord and Twitter for the most updated information."),
            utf8(b"https://worldsbeyondnft.com"),
            utf8(b"Worlds Beyond Creator")
        ];

        // Get a new `Display` object for the `Box` type.
        let display = display::new_with_fields<Box>(
            publisher, keys, values, ctx
        );

        // Commit first version of `Display` to apply changes.
        display::update_version(&mut display);

        display
    }

    fun create_ticket_display(publisher: &Publisher, ctx: &mut TxContext): Display<Ticket> {
        let keys = vector[
            utf8(b"name"),
            utf8(b"infinity_credits"),
            utf8(b"link"),
            utf8(b"image_url"),
            utf8(b"description"),
            utf8(b"project_url"),
            utf8(b"creator"),
        ];

        let values = vector[
            utf8(b"{name}"),
            utf8(b"{infinity_credits}"),
            utf8(b"https://worldsbeyondnft.com/loyalty-tickets/{id}"),
            utf8(b"https://cdn.worldsbeyondnft.com/nft/loyalty-tickets/{type}.jpg"),
            utf8(b"Infinity Tickets are tradeable tickets that contain tradeable balances of Infinity Credits. Once purchased, a user must apply an Infinity Ticket before Infinity Credits can be applied to the user's account. Players earn Infinity Credits on their Infinity Passports for playing Worlds Beyond games, winning competitions, completing challenges and more. These Infinity Credits can be redeemed for a variety of rewards, including WBITS mining keys, in-game items, exclusive content, and real-world prizes. Be sure to follow news in our Discord and Twitter for the most updated information."),
            utf8(b"https://worldsbeyondnft.com"),
            utf8(b"Worlds Beyond Creator")
        ];

        // Get a new `Display` object for the `Ticket` type.
        let display = display::new_with_fields<Ticket>(
            publisher, keys, values, ctx
        );

        // Commit first version of `Display` to apply changes.
        display::update_version(&mut display);

        display
    }

    /// Entry function. Mint a loyalty `Box` providing a `MintCap`
    /// and transfer it to recipient.
    entry fun mint_box_for(
        _: &AdminCap,
        type: u64,
        name: vector<u8>,
        infinity_credits: u64,
        attribute_keys: vector<ascii::String>,
        attribute_values: vector<ascii::String>,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        let box = Box {
            id: object::new(ctx),
            type,
            name: utf8(name),
            infinity_credits,
            attributes: attributes::from_vec(attribute_keys, attribute_values),
        };

        transfer::transfer(box, recipient)
    }

    entry fun change_ticket_collection_name(_: &AdminCap, collection: &mut Collection<Ticket>, new_name: vector<u8>) {
        let collection_uid = collection::borrow_uid_mut(ticket_col_wit(), collection);
        display_info::change_name<Witness, Ticket>(collection_uid, utf8(new_name))
    }

    entry fun change_ticket_collection_desc(_: &AdminCap, collection: &mut Collection<Ticket>, new_desc: vector<u8>) {
        let collection_uid = collection::borrow_uid_mut(ticket_col_wit(), collection);
        display_info::change_description<Witness, Ticket>(collection_uid, utf8(new_desc))
    }

    /// Entry function. Claim a loyalty `Box`.
    entry fun claim_box(
        config: &mut Config,
        nonce: u64,
        type: u64,
        name: vector<u8>,
        infinity_credits: u64,
        attribute_keys: vector<ascii::String>,
        attribute_values: vector<ascii::String>,
        signature: vector<u8>,
        ctx: &mut TxContext,
    ) {
        utility::assert_version(config);
        utility::assert_nonce(config, &nonce);

        let sender = tx_context::sender(ctx);
        let msg = address::to_bytes(sender);
        vec::append(&mut msg, bcs::to_bytes(&nonce));
        vec::append(&mut msg, bcs::to_bytes(&type));
        vec::append(&mut msg, bcs::to_bytes(&infinity_credits));

        let hashed_msg = hash::keccak256(&msg);
        utility::assert_signature(config, &signature, &hashed_msg);

        utility::mark_nonce_used(config, nonce);

        let id = object::new(ctx);
        let name_ = utf8(name);

        let box = Box {
            id,
            type,
            name: name_,
            infinity_credits,
            attributes: attributes::from_vec(attribute_keys, attribute_values),
        };

        emit(BoxCreated {
            id: object::uid_to_inner(&box.id),
            nonce,
            type,
            name: name_,
            infinity_credits,
            recipient: sender,
        });

        transfer::transfer(box, sender)
    }

    /// Entry function. Sync loyalty points in a `Box`.
    entry fun sync(
        config: &mut Config,
        box: &mut Box,
        nonce: u64,
        infinity_credits: u64,
        signature: vector<u8>,
        ctx: &mut TxContext,
    ) {
        utility::assert_version(config);
        utility::assert_nonce(config, &nonce);

        let sender = tx_context::sender(ctx);
        let msg = address::to_bytes(sender);
        vec::append(&mut msg, bcs::to_bytes(&nonce));
        vec::append(&mut msg, bcs::to_bytes(&infinity_credits));

        let hashed_msg = hash::keccak256(&msg);
        utility::assert_signature(config, &signature, &hashed_msg);

        utility::mark_nonce_used(config, nonce);
        box.infinity_credits = box.infinity_credits + infinity_credits;

        emit(BoxLoyaltyPointsSynced {
            id: object::uid_to_inner(&box.id),
            nonce,
            infinity_credits: box.infinity_credits,
            by: sender,
        });
    }

    /// Entry function. Issue a loyalty `Ticket`, so people can
    /// sell their loyalty points on marketplace.
    entry fun issue_loyalty_ticket(
        config: &mut Config,
        box: &mut Box,
        nonce: u64,
        name: vector<u8>,
        recipient: address,
        issuing_infinity_credits: u64,
        attribute_keys: vector<ascii::String>,
        attribute_values: vector<ascii::String>,
        signature: vector<u8>,
        ctx: &mut TxContext,
    ) {
        utility::assert_version(config);
        utility::assert_nonce(config, &nonce);
        assert!(issuing_infinity_credits <= box.infinity_credits, 1);

        let sender = tx_context::sender(ctx);
        let msg = address::to_bytes(sender);
        vec::append(&mut msg, bcs::to_bytes(&nonce));
        vec::append(&mut msg, address::to_bytes(recipient));
        vec::append(&mut msg, bcs::to_bytes(&issuing_infinity_credits));

        let hashed_msg = hash::keccak256(&msg);
        utility::assert_signature(config, &signature, &hashed_msg);

        utility::mark_nonce_used(config, nonce);

        box.infinity_credits = box.infinity_credits - issuing_infinity_credits;
        emit(BoxLoyaltyPointsUpdated {
            id: object::uid_to_inner(&box.id),
            infinity_credits: box.infinity_credits,
            by: sender,
        });

        let ticket = Ticket {
            id: object::new(ctx),
            type: box.type,
            name: utf8(name),
            infinity_credits: issuing_infinity_credits,
            attributes: attributes::from_vec(attribute_keys, attribute_values),
        };

        emit(TicketCreated {
            id: object::uid_to_inner(&ticket.id),
            box_id: object::uid_to_inner(&box.id),
            nonce,
            type: ticket.type,
            name: ticket.name,
            infinity_credits: box.infinity_credits,
            recipient,
        });

        mint_event::emit_mint<Ticket>(
            witness::from_witness(Witness {}),
            utility::collection_id_by_name(config, b"loyalty_ticket"),
            &ticket,
        );

        transfer::public_transfer(ticket, recipient)
    }

    /// Entry function. Apply a loyalty `Ticket` to a `Box` so people
    /// can level up their loyalty points by the points in the ticket.
    entry fun apply_loyalty_ticket(
        config: &mut Config,
        box: &mut Box,
        ticket: Ticket,
        nonce: u64,
        signature: vector<u8>,
        ctx: &mut TxContext,
    ) {
        utility::assert_version(config);
        utility::assert_nonce(config, &nonce);

        let ticket_guard = mint_event::start_burn(
            witness::from_witness(Witness {}),
            &ticket,
        );

        let Ticket { id, type, name: _, infinity_credits, attributes: _ } = ticket;
        assert!(box.type == type, ETicketTypeMisMatch);

        let sender = tx_context::sender(ctx);
        let msg = address::to_bytes(sender);
        vec::append(&mut msg, bcs::to_bytes(&nonce));

        let hashed_msg = hash::keccak256(&msg);
        utility::assert_signature(config, &signature, &hashed_msg);

        utility::mark_nonce_used(config, nonce);

        box.infinity_credits = box.infinity_credits + infinity_credits;

        emit(TicketApplied {
            box_id: object::uid_to_inner(&box.id),
            ticket_id: object::uid_to_inner(&id),
            nonce,
            applied_infinity_credits: infinity_credits,
            by: tx_context::sender(ctx),
        });

        mint_event::emit_burn(
            ticket_guard,
            utility::collection_id_by_name(config, b"loyalty_ticket"),
            id,
        );
    }

    public(friend) fun use_infinity_credits(box: &mut Box, infinity_credits: u64) {
        assert!(box.infinity_credits >= infinity_credits, 1);
        box.infinity_credits = box.infinity_credits - infinity_credits
    }

    // ======== View Functions ========

    /// Get the Box's `type`.
    public fun type(box: &Box): u64 {
        box.type
    }

    /// Get the Box's `name`.
    public fun name(box: &Box): &String {
        &box.name
    }

    /// Get the Box's `infinity_credits`.
    public fun infinity_credits(box: &Box): u64 {
        box.infinity_credits
    }

    /// Get the Ticket's `infinity_credits`.
    public fun ticket_infinity_credits(ticket: &Ticket): u64 {
        ticket.infinity_credits
    }

    /// === Helpers ====

    fun box_col_wit(): DelegatedWitness<Box> {
        witness::from_witness<Box, Witness>(Witness {})
    }

    fun ticket_col_wit(): DelegatedWitness<Ticket> {
        witness::from_witness<Ticket, Witness>(Witness {})
    }

    // ======== Tests Helpers ========

    #[test_only]
    public fun init_test(ctx: &mut TxContext) {
        let otw = LOYALTY {};
        init(otw, ctx)
    }

    #[test_only]
    public fun test_claim_box(
        config: &mut Config,
        nonce: u64,
        type: u64,
        name: vector<u8>,
        infinity_credits: u64,
        attribute_keys: vector<ascii::String>,
        attribute_values: vector<ascii::String>,
        signature: vector<u8>,
        ctx: &mut TxContext,
    ) {
        claim_box(
            config,
            nonce,
            type,
            name,
            infinity_credits,
            attribute_keys,
            attribute_values,
            signature,
            ctx,
        );
    }

    #[test_only]
    public fun test_sync(
        config: &mut Config,
        box: &mut Box,
        nonce: u64,
        infinity_credits: u64,
        signature: vector<u8>,
        ctx: &mut TxContext,
    ) {
        sync(
            config,
            box,
            nonce,
            infinity_credits,
            signature,
            ctx,
        );
    }

    #[test_only]
    public fun test_issue_loyalty_ticket(
        config: &mut Config,
        box: &mut Box,
        nonce: u64,
        name: vector<u8>,
        recipient: address,
        issuing_infinity_credits: u64,
        attribute_keys: vector<ascii::String>,
        attribute_values: vector<ascii::String>,
        signature: vector<u8>,
        ctx: &mut TxContext,
    ) {
        issue_loyalty_ticket(
            config,
            box,
            nonce,
            name,
            recipient,
            issuing_infinity_credits,
            attribute_keys,
            attribute_values,
            signature,
            ctx,
        );
    }

    #[test_only]
    public fun test_apply_loyalty_ticket(
        config: &mut Config,
        box: &mut Box,
        ticket: Ticket,
        nonce: u64,
        signature: vector<u8>,
        ctx: &mut TxContext,
    ) {
        apply_loyalty_ticket(
            config,
            box,
            ticket,
            nonce,
            signature,
            ctx,
        );
    }

    // #[test_only]
    public fun test_mint_box_for(
        cap: &AdminCap,
        type: u64,
        name: vector<u8>,
        infinity_credits: u64,
        attribute_keys: vector<ascii::String>,
        attribute_values: vector<ascii::String>,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        mint_box_for(
            cap,
            type,
            name,
            infinity_credits,
            attribute_keys,
            attribute_values,
            recipient,
            ctx,
        );
    }
}
