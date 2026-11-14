# Changelog

## 1.3.1

### Fixed
- **Items that finish loading while a vendor is open** no longer recolor the wrong items. Names and borders now stay correct when filtering or hiding search results, and the quality border settings keep applying.
- **Filtered items and hidden search results** now look the same as in the normal vendor window:
  - The quest "!" mark shows on the right item.
  - Prices you can't afford are gray.
  - Prices no longer lose their silver and copper.
  - Items you can't buy are red, and heirlooms you already own are dimmed.
- **Currency containers** show the container's name, icon and amount. Search and the "In stock" filter use them too.

## 1.3

### Fixed
- **Leatrix Plus integration works again.** Better Vendor UI couldn't find Leatrix's exclusions box in current Leatrix versions. With "Sell junk automatically" on in Leatrix:
  - Grey items on your **Never Sell** list are now protected from Leatrix.
  - Items on your **Always Sell** list are now sold when you open a vendor (hold Shift to skip).
  - The settings page shows the correct Leatrix status.
- **Items that cost a currency, while filtering or hiding search results:** they show their real cost again and ask for confirmation before you buy.
- **Filtered items:** names use the right quality color, the currency sits in the right place, and the non-refundable warning belongs to the item shown.
- **Rows setting:** raising it with a vendor open no longer leaves new slots missing.
- **Always Sell** now includes the reagent bag.
- **Vendors that refuse a sale** (or the gold cap) stop the selling with the reason, instead of reporting a sale that didn't happen.
- **Dim strength 0:** invisible items can no longer be clicked and bought by accident.
- A new vendor's first draw no longer uses the previous vendor's items when search or filters are kept between vendors.

### Improved
- **Always Sell / Never Sell lists** scroll when they don't fit, stay sorted by name, and close with Escape. Opened without a vendor, the window appears in the middle of the screen.
- **Filters kept from another vendor** stay listed with a count of 0, so you can uncheck them.
- **Equip slot filters** no longer list Chest and Ranged twice.
- Much smaller addon icon (12.6 MB down to about 12 KB).

## 1.2

### Fixed
- The Next button and page number no longer overlap on a widened vendor window: Next sits at the right edge and the page number is centred.

## 1.1

### New: EllesmereUI support
- **Junk selling follows your lists:** with EllesmereUI Bags' Junk Marker on, EllesmereUI's Auto Sell Junk and its Sell Junk button:
  - Skip items on your **Never Sell** list. They also lose the junk badge and leave the Junk category.
  - Sell items on your **Always Sell** list. They also show in the Junk category.
- **Without the Junk Marker,** Better Vendor UI sells your Always Sell items when you open a vendor (hold Shift to skip). EllesmereUI then sells every grey item, so Never Sell items can't be protected; the settings page tells you when this is the case.
- **"Show As List" merchant view:**
  - Filters and search work on EllesmereUI's list.
  - Better Vendor UI keeps the default window width there, since the list draws the items itself.
  - The Rows setting still makes the window taller.
- **New EllesmereUI section in the settings,** with a status line and two options:
  - EllesmereUI never sells Never Sell items
  - EllesmereUI sells Always Sell items too

### New: EllesmereUI look
Better Vendor UI now follows your EllesmereUI theme (EUI or Modern, accent color included):
- The **Filters panel** and the **Always Sell / Never Sell lists window**
- **Chat messages** use your accent color

With EllesmereUI's merchant window skin on, also:
- The **search box** and the **buttons** next to it
- **Every grid slot past the first 12**, so a larger grid matches EllesmereUI's tiles

You can turn this off in EllesmereUI: Blizzard Skins+ → Window Skins → Third-Party Addons → BetterVendorUI.

### Improved
- Better Vendor UI's own auto-sell turns off while EllesmereUI sells junk automatically, so items aren't sold twice.
- The widened bottom bar no longer shows through EllesmereUI's merchant skin.
