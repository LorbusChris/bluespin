#!/usr/bin/python3
"""Append localised keys to a desktop entry from an installed gettext domain.

    desktop-translations.py FILE DOMAIN KEY=MSGID [KEY=MSGID ...]

For every locale under /usr/share/locale that ships DOMAIN, a ``KEY[locale]=``
line is appended for each KEY whose MSGID has a translation there. Lets a
desktop entry of ours reuse strings that a package in the image already has
translated, instead of carrying a copy of the catalog in this repo.
"""

import gettext
import sys
from pathlib import Path

LOCALEDIR = Path("/usr/share/locale")


def main(argv):
    if len(argv) < 4:
        sys.exit(__doc__)
    desktop, domain, pairs = Path(argv[1]), argv[2], argv[3:]
    keys = [pair.split("=", 1) for pair in pairs]

    text = desktop.read_text(encoding="utf-8")
    for key, msgid in keys:
        if f"\n{key}={msgid}\n" not in f"\n{text}":
            sys.exit(f"{desktop}: no '{key}={msgid}' line to translate")

    lines = []
    for mo in sorted(LOCALEDIR.glob(f"*/LC_MESSAGES/{domain}.mo")):
        locale = mo.parent.parent.name
        catalog = gettext.translation(domain, str(LOCALEDIR), languages=[locale])
        for key, msgid in keys:
            msgstr = catalog.gettext(msgid)
            if msgstr != msgid:
                lines.append(f"{key}[{locale}]={msgstr}")
    if not lines:
        sys.exit(f"no translations found in domain '{domain}'")

    with desktop.open("a", encoding="utf-8") as f:
        f.write("\n# Translations rendered at build time from the image's"
                f" '{domain}' catalogs\n")
        f.write("\n".join(lines) + "\n")
    print(f"{desktop}: {len(lines)} translated lines added from '{domain}'")


if __name__ == "__main__":
    main(sys.argv)
