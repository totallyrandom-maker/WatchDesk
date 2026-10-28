# Watch Desk

A self-contained watch-list and auction desk for **Burning Crusade Anniversary, interface 20506**. It uses your own items, prices and auction scans. No other addon is required. This guide covers version **0.2.1**.

**A new installation starts with an empty watch list and zero prices. There are no starter watches, bait suggestions, pricing formulas, market feeds or recommendations.**

## Install and open

Copy the entire **WatchDesk** folder into:

    World of Warcraft/_anniversary_/Interface/AddOns/

WatchDesk.toc must be directly inside that folder. Keep its Lua files and ThirdParty notice together. Restart WoW when adding the addon folder for the first time. Updating an existing installation needs **/reload**.

Use **/watchdesk**, or **/wd** when that alias is available. If another addon already owns /wd, Watch Desk leaves it with that addon. The window stays closed at login.

## Add and organize items

The main window displays all three entry methods:

- Drag an owned bag item into the item box or its icon. WD catches the item and adds a checklist entry; the item stays in your inventory. This does not delete, sell or mail it.
- Type the **Item ID displayed directly beneath its name in an item tooltip**, then press Enter. A pasted item link also works.
- Click the item box, then **Shift-click** an item from bags, chat or a compatible addon. WD adds it immediately. Other focused editors keep their normal item-link behavior.

For an item you do not own, use **Find items** and its labelled **Search item names or IDs** box. Enter a name, press Enter or click **Search**, then click a matching identity to add it. The selected category limits the search. The item-entry box at the top also accepts a name through **Find item**. The bundled catalogue contains public historical English item identities, with live native names preferred when available. It is a search aid; a catalogue match does not prove that an item currently exists or can be auctioned on Anniversary. No catalogue entry is automatically added to your watch list.

New watches are checked and have zero buy and bait prices. Adding an existing item selects it without making a duplicate. Remove deletes only the checklist entry.

Use the saved-watch search, **Category** dropdown and **Checked only** filter together. **Sort** offers saved order, name, item ID or checked first. **Check shown** and **Uncheck shown** apply to every matching watch across all list pages and preserve watches outside the current filter. Category filtering selects item types; it never supplies a strategy or price.

## Set prices and limits

Select a watch and enter your own **Max buy / item** and **Bait list / item**. Plain numbers are gold: 2.5000 is 2g 50s. Entries such as 1g20s, 75s and 25c also work. **Zero disables that action.**

Choose an optional unit limit and spending limit for this watch during the current login. A whole stack must fit both remaining limits. Zero leaves a limit off. Stop, closing the window and reopening the auctioneer do not reset these totals. **Reset session** clears purchase totals and unconfirmed-purchase reservations for **all watches**, when no scan or action is pending. Saved price and cap values remain.

An unconfirmed purchase conservatively reserves its quantity and cost against those limits, even after reopening the auctioneer. Check your mail and auctions before deliberately resetting an uncertain session. A confirmed purchase is counted only once.

Choose a bait stack quantity and 12, 24 or 48-hour duration. These are posting controls, not suggested bait prices. **Save** persists the selected watch. Scan and Bait Scan save only the currently selected watch before acting. **Save each watch before scanning a list**; drafts on other watches are not applied. Unsaved drafts remain while switching between watches in the same login; save them before reload/logout.

## Scan, review and buy

- **Scan checked** queries your checked watches once. **All AH pages** enables page-by-page results for each item; the safety bound is 200 pages per item, with partial results labeled.
- **Scan selected** reads one auction-house page for the selected item. **All pages: selected** reads its pages in sequence. AH page buttons inspect individual pages; row arrows page through displayed results.
- **Repeat scan** repeats read-only scans of checked watches after the entered 5–300-second delay. **Pause** lets you review; **Resume** continues; **Stop** ends the cycle. Another auction search, combat, timeouts or closing the auctioneer can pause or stop scanning. A deliberate restart is required.
- Rows show quantity, per-item price, whole-stack total, seller, observation age and AH page. Own auctions are excluded from buyable results. Current carried-bag stock and scan/session summaries are informational.
- **Review scans** retains this login's observations across scanned items. Click an observation or **Recheck offer** for a fresh query of that exact stack's page. This does not buy anything. Changed or missing stacks cannot be treated as the old offer.
- Select a freshly verified stack and click **Buy selected stack**. WD checks the native listing, seller, variant, count, whole-stack price, remaining limits and available gold immediately before bidding. Old pages require a recheck. Every purchase requires your click; scans and callbacks never buy automatically.

Stopping or pausing a scan does not erase an outstanding server request. WD waits for a complete late reply and discards it before allowing another query. If overlapping queries make the reply ambiguous, close and reopen the auctioneer before restarting.

The Review scans tray shows up to 2,000 recent observations. The session result cache is bounded to 20,000 rows; the oldest other-item observations can expire and need a new scan. Selected-item scans remain bounded to 200 AH pages.

Auction pages can change while being read. Aggregated observations are not a transaction guarantee, and the auction server controls final success.

## Bait Scan

Check and select your chosen bait watch, enter its price and quantity, then click **Bait Scan**. WD prepares the matching unlocked, unbound bag item, verifies its native identity and deposit, and posts one stack within your click. If native preparation is not ready, click again when prompted. After the server acknowledges the post, WD begins the checked-item scan.

Bait Scan never chooses a bait item or price for you. It does not buy automatically, replace bait in the background, or cancel other auctions. Stop, closing WD, errors and timeouts clear any unstarted scan continuation. A submitted transaction still needs the server's response.

## Windows and addon coexistence

The top-right **X** explicitly closes WD and stops scanning. Ordinary left-drag moves it; Shift-left-drag scales it. The initial size fits the screen, and a usable edge remains reachable. Escape closes one topmost WD window or menu at a time. If another addon provides compatible window coordination, WD can participate in its shared Escape ordering.

Hover the selected item icon to open its normal item tooltip, including financial details supplied by your installed tooltip addons.

Item IDs are added beneath the name in standard hover, item-link and comparison tooltips. The existing body rows, scripts, fonts, colors and other addon information are preserved. Hidden scanner tips are not annotated. Other tooltip addons may also display their own ID line according to their settings.

WD uses native auction APIs and yields when another auction search takes over. It does not modify other addons' source files, bindings, profiles, pricing operations or saved settings.

## Optional companion addons

[**Auctionator**](https://www.curseforge.com/wow/addons/auctionator) is recommended for its Buying interface, item-price tooltips and full auction-house scans. It can make browsing and comparing observed prices much easier. WD remains usable without it. Use an edition compatible with TBC Anniversary and keep its scan data current.

[**LibItemDB**](https://www.curseforge.com/wow/addons/libitemdb) is an optional item database that also includes a full auction-house scanner. Its own scan can supply price context to supported tools and tooltips. A current full-house scan is useful context; it does not guarantee that a specific old listing remains available. You can use Auctionator’s full scan or another compatible full-house scanner rather than running overlapping scans.

When Auctionator is available, **Auctionator selected** and **Auctionator checked** send the selected item or checked list to its native Shopping search interface. A successful handoff closes WD so the native results are visible; reopen it with /watchdesk. No buy or post is submitted by the handoff. Stop any active WD scan first, and wait for an outstanding reply to drain before retrying a handoff. Run only one auction search or full-house scan at a time.

These addons and their observed prices are optional. WD does not preload their prices into your buy or bait fields, choose bait, or distribute your personal data.

## Saved data and sharing

Your own watches, checkmarks, saved prices/limits and window position/scale live in **WatchDeskDB**, saved by WoW in WTF. Scan results, drafts and session counters are temporary. This distributable addon folder contains generic code and public item identities only; it includes no player's SavedVariables, chosen watches, prices, bait choices, accounting history, private market data or trading recommendations.

Share the **WatchDesk addon folder**, not your WTF/SavedVariables files. The public identity catalogue retains its MIT notice in ThirdParty/ItemDB-NOTICE.txt.

