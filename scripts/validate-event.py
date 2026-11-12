#!/usr/bin/env python3
"""Checks an event against the envelope, and its data against the schema of
its type and version when one exists.

Usage: validate-event.py <event.json> [event.json ...]
       validate-event.py --stdin

Exits 0 if every event is valid and 1 otherwise, printing each problem with
the path of the value it concerns.

It implements the part of JSON Schema that the contracts use: type,
required, properties, additionalProperties, pattern, format (uuid and
date-time), enum, const, minimum, maximum, minLength, maxLength, items and
minItems. A schema that uses any other keyword is refused, so a contract
can never be written that this validator silently ignores. It has no
dependencies, so it runs anywhere Python does.
"""
import json
import pathlib
import re
import sys
from datetime import datetime

CONTRACTS = pathlib.Path(__file__).resolve().parent.parent / "contracts" / "events"

SUPPORTED = {
    "$schema", "$id", "title", "description", "type", "required", "properties",
    "additionalProperties", "pattern", "format", "enum", "const", "minimum",
    "maximum", "minLength", "maxLength", "items", "minItems",
}

UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

TYPES = {
    "object": dict,
    "array": list,
    "string": str,
    "boolean": bool,
    "null": type(None),
}


class UnsupportedSchema(Exception):
    """The schema uses a keyword this validator does not implement."""


def is_type(value, name):
    # In JSON a boolean is not a number, although in Python it is an int.
    if name == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if name == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    return isinstance(value, TYPES[name])


def is_format(value, name):
    if name == "uuid":
        return bool(UUID.match(value))
    if name == "date-time":
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return False
        return parsed.tzinfo is not None and "T" in value
    raise UnsupportedSchema(f"format {name!r}")


def validate(value, schema, path="$"):
    """Returns a list of problems, each a string. Empty means valid."""
    unknown = set(schema) - SUPPORTED
    if unknown:
        raise UnsupportedSchema(f"keyword(s) {sorted(unknown)} at {path}")

    problems = []
    expected = schema.get("type")
    if expected is not None and not is_type(value, expected):
        # Nothing else can be checked on a value of the wrong type.
        return [f"{path}: expected {expected}, found {type(value).__name__}"]

    if "const" in schema and value != schema["const"]:
        problems.append(f"{path}: must be {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        problems.append(f"{path}: must be one of {schema['enum']}")

    if isinstance(value, str):
        if "pattern" in schema and not re.search(schema["pattern"], value):
            problems.append(f"{path}: {value!r} does not match {schema['pattern']}")
        if "format" in schema and not is_format(value, schema["format"]):
            problems.append(f"{path}: {value!r} is not a valid {schema['format']}")
        if "minLength" in schema and len(value) < schema["minLength"]:
            problems.append(f"{path}: shorter than {schema['minLength']} characters")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            problems.append(f"{path}: longer than {schema['maxLength']} characters")

    if is_type(value, "number"):
        if "minimum" in schema and value < schema["minimum"]:
            problems.append(f"{path}: less than {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            problems.append(f"{path}: greater than {schema['maximum']}")

    if isinstance(value, dict):
        properties = schema.get("properties", {})
        for name in schema.get("required", []):
            if name not in value:
                problems.append(f"{path}: missing required field {name!r}")
        for name, item in value.items():
            if name in properties:
                problems.extend(validate(item, properties[name], f"{path}.{name}"))
            elif schema.get("additionalProperties") is False:
                problems.append(f"{path}: unexpected field {name!r}")

    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            problems.append(f"{path}: fewer than {schema['minItems']} items")
        if "items" in schema:
            for index, item in enumerate(value):
                problems.extend(validate(item, schema["items"], f"{path}[{index}]"))

    return problems


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def validate_event(event, contracts=CONTRACTS):
    """Validates the envelope, then data against the schema of the event's
    type and version if the repository has one."""
    problems = validate(event, load(contracts / "envelope.schema.json"))
    if problems or not isinstance(event, dict):
        return problems

    schema_file = contracts / f"{event['type']}.v{event['version']}.schema.json"
    if schema_file.exists():
        problems.extend(validate(event["data"], load(schema_file), "$.data"))
    return problems


def main(arguments):
    if not arguments:
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2

    sources = [("stdin", json.load(sys.stdin))] if arguments == ["--stdin"] else [
        (name, load(name)) for name in arguments
    ]
    failed = False
    for name, event in sources:
        problems = validate_event(event)
        if problems:
            failed = True
            print(f"INVALID {name}")
            for problem in problems:
                print(f"  {problem}")
        else:
            print(f"valid   {name}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
