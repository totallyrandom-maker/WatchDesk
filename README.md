# Watch Desk

A small auction-house addon for Burning Crusade Anniversary (Interface 20506): an editable item checklist, scans, buying and bait scanning in one window.

## Install and open

Copy the entire **WatchDesk** folder into:

    World of Warcraft/_anniversary_/Interface/AddOns/

**WatchDesk.toc** must be directly inside the folder. Enable **Watch Desk**, then restart the client after adding the new addon folder. Type **/wd** or **/watchdesk**. If another addon uses **/wd**, use **/watchdesk**. The window stays closed at login.

No other addon is required. This version is for the legacy TBC Anniversary auction house, not Retail.

## Use

1. Open the auction house. Enter an item ID or paste an item link and press **Enter** to add it to the checklist. You can also drop a bag item into the item field. New items are checked automatically; check/uncheck, select or remove items directly in the list.
2. For each selected item, enter a **Max buy / item** and **Bait / item** price in gold. **2.5000** means 2g 50s; four decimal places preserve individual copper. Zero leaves the corresponding action off. Scan and Bait Scan apply edited prices, so pressing Apply separately is optional.
3. Press **Scan** to scan checked items. **Bait Scan** posts one of the selected, checked items at its entered bait price and scans the checked list after the post is acknowledged. It uses the same button throughout; if native loading is not ready yet, click **Bait Scan** again when requested. **Stop** stops further scanning.
4. Select a result and click **Buy selected stack** to buy the entire displayed stack within the selected item's unit-price limit. Each purchase requires your click and a fresh auction check. For stale results, use **Scan selected** first.

Results are temporary. Each scan reads one auction-house page per item; the AH page buttons inspect other pages of the selected item. Row buttons page through the current result list.

Left-drag moves the window. Shift + left-drag scales it. Escape or its close button closes it; a reachable edge stays on screen.

## Saved data

Only checklist entries, checkmarks, per-item prices and window position/scale are saved in **WatchDeskDB**. The package contains no personal watch list, accounting history, saved offers or market strategy.

Auction-house throttling, loading and final transaction success are controlled by WoW. Other auction activity can invalidate results. Scans and server callbacks never purchase items automatically.
