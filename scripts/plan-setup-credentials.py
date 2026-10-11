#!/usr/bin/env python3
"""Preview selected setup requirements without reading or obtaining secrets."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


CATALOG = Path(__file__).resolve().parents[1] / "config" / "credential-requirements.json"


def build_plan(catalog: dict, selections: list[str]) -> dict:
    options = catalog["options"]
    names = {name: name for name in options}
    for name, option in options.items():
        for alias in option["aliases"]:
            if alias in names:
                raise ValueError(f"Duplicate option name or alias: {alias}")
            names[alias] = name

    selected = []
    for selection in selections:
        # Bench checkboxes are represented as bench_<name> in the TUI.
        selection = selection.removeprefix("bench_")
        if selection not in names:
            raise ValueError(f"Unknown option: {selection}; use --list for available options")
        name = names[selection]
        if name not in selected:
            selected.append(name)

    requirements = {}
    for name in selected:
        for requirement in options[name]["additional"]:
            if requirement not in requirements:
                requirements[requirement] = {
                    "id": requirement,
                    **catalog["requirements"][requirement],
                    "neededBy": [],
                }
            requirements[requirement]["neededBy"].append(name)

    return {
        "schemaVersion": catalog["schemaVersion"],
        "mode": "requirements-preview",
        "notice": "Conditional requirements apply only to selected features/providers. "
        "Choose one applicable authentication alternative. No credentials are checked or retrieved.",
        "selectedOptions": [{"id": name, **options[name]} for name in selected],
        "common": catalog["common"],
        "additional": list(requirements.values()),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--option", action="append", default=[], help="Selected option; repeat as needed")
    parser.add_argument("--all", action="store_true", help="Inventory every option, without assuming every feature is needed")
    parser.add_argument("--list", action="store_true", help="List option names and aliases")
    parser.add_argument("--json", action="store_true", help="Output metadata as JSON")
    args = parser.parse_args()
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    if args.list:
        if args.option or args.all:
            parser.error("--list cannot be combined with selections")
        if args.json:
            print(json.dumps(catalog["options"], indent=2))
        else:
            for name, option in catalog["options"].items():
                aliases = f" (aliases: {', '.join(option['aliases'])})" if option["aliases"] else ""
                print(f"{name}: {option['label']} [{option['source']}]{aliases}")
        return 0

    if args.all and args.option:
        parser.error("Choose --all or --option selections")
    try:
        plan = build_plan(catalog, list(catalog["options"]) if args.all else args.option)
    except ValueError as error:
        parser.error(str(error))

    if args.json:
        print(json.dumps(plan, indent=2))
        return 0

    selected = ", ".join(option["id"] for option in plan["selectedOptions"]) or "none (common requirements only)"
    print(f"Selected options: {selected}\n{plan['notice']}\n")
    print("Common requirements")
    for common in plan["common"]:
        print(f"- {common['id']} [{common['phase']}]: {common['condition']}")
        print(f"  {common['requirement']}")
    print("\nAdditional requirements")
    if not plan["additional"]:
        print("None for the selected options. Agent workflows use the chosen agent's own credentials.")
    for requirement in plan["additional"]:
        print(f"- {requirement['label']} [{requirement['phase']}; {', '.join(requirement['neededBy'])}]")
        print(f"  When: {requirement['condition']}")
        print(f"  Authentication: {' OR '.join(requirement['alternatives'])}")
        if requirement["metadata"]:
            print(f"  Metadata: {', '.join(requirement['metadata'])}")
    notes = [option for option in plan["selectedOptions"] if option["notes"]]
    if notes:
        print("\nOption notes")
        for option in notes:
            print(f"- {option['id']}: {option['notes']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
