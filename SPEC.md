# BatchNameForge — specification

**Tagline:** Drop a pile of files and rename them all with stackable rules and a live before and after preview.

**Category:** Files & Conversion

**Inspired by (paid):** Better Rename ($20 one-time)

**Frameworks:** SwiftUI, AppKit, UniformTypeIdentifiers, Foundation, ImageIO, AVFoundation

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: Better Rename, also sold as A Better Finder Rename, applies chains of actions to many file names at once, such as replace, number, change case, insert dates and read metadata. It has been on the Mac App Store for years at around twenty dollars, with frequent sale prices, and long-running reviews and roundups of Mac renamers name it as a staple, which signals durable demand.

Our clean-room feature set: a window where you drop files or folders into a table. A rule stack sits beside it, with these rule types: find and replace with optional regular expression, add prefix or suffix, remove characters, change case, add sequence number with start, step and padding, insert modification date or creation date with a chosen format, insert image capture date from EXIF, and trim whitespace. Each rule can be reordered, disabled or removed. The table shows the original name and the proposed name live, flags collisions in red, and offers Rename and Undo last batch. About five hundred lines.

UI spec: a normal single-window SwiftUI app. Left side holds the file table with columns for Original, New name and Folder. Right side holds the rule stack with an Add Rule menu. The bottom bar shows counts, a Rename button bound to Command Return, and an Undo button bound to Command Z. Menu bar commands include Open Files with Command O, Clear List, and Presets submenu with save and load of rule stacks. Empty state: a large dashed drop zone with the text Drop files here. Settings are limited to default date format and whether to confirm before renaming.

Technical approach: files arrive through onDrop with UTType fileURL or an NSOpenPanel. Each rule is a small struct conforming to a protocol with one function that maps a name and index to a new name. Preview recomputes whenever the rule stack changes. Dates come from URLResourceValues creationDate and contentModificationDate, EXIF dates come from CGImageSource properties. Renaming uses FileManager moveItem and performs a two-phase rename through temporary names so swaps and chained names do not collide. Store the undo log of old and new URLs in memory and persist presets as JSON in Application Support. No special permissions are needed beyond the user choosing the files, and the app is not sandboxed so folders are accessible.

Edge cases: detect duplicate target names within the batch and across the destination folder, then block renaming and highlight the rows. Keep file extensions untouched unless a toggle says to include them. Invalid characters such as a slash are replaced. Hidden files and packages are handled as normal files. If a rename fails halfway, roll back everything already moved and show the failing file. Regular expression errors show inline instead of crashing. Very large batches use lazy preview computation to keep scrolling smooth.
