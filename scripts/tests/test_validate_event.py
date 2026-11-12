"""Tests for scripts/validate-event.py. Run with: make contract-test"""
import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
EXAMPLES = ROOT / "contracts" / "events" / "examples"

spec = importlib.util.spec_from_file_location("validate_event", ROOT / "scripts" / "validate-event.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


class ExampleEvents(unittest.TestCase):
    def test_every_valid_example_passes(self):
        files = sorted((EXAMPLES / "valid").glob("*.json"))
        self.assertTrue(files, "there are no valid examples")
        for file in files:
            with self.subTest(file=file.name):
                self.assertEqual(validator.validate_event(load(file)), [])

    def test_every_invalid_example_fails(self):
        files = sorted((EXAMPLES / "invalid").glob("*.json"))
        self.assertTrue(files, "there are no invalid examples")
        for file in files:
            with self.subTest(file=file.name):
                self.assertNotEqual(validator.validate_event(load(file)), [])

    def test_each_invalid_example_breaks_exactly_one_rule(self):
        # An example that fails for two reasons does not show which rule it
        # was written to demonstrate.
        for file in sorted((EXAMPLES / "invalid").glob("*.json")):
            with self.subTest(file=file.name):
                self.assertEqual(len(validator.validate_event(load(file))), 1)


class Envelope(unittest.TestCase):
    def setUp(self):
        self.event = load(EXAMPLES / "valid" / "product-published.json")

    def problems(self, **changes):
        event = dict(self.event)
        for name, value in changes.items():
            if value is None:
                event.pop(name, None)
            else:
                event[name] = value
        return validator.validate_event(event)

    def test_every_required_field_is_required(self):
        for name in ["id", "type", "version", "source", "occurredAt", "correlationId", "data"]:
            with self.subTest(field=name):
                self.assertTrue(any(name in problem for problem in self.problems(**{name: None})))

    def test_causation_is_optional(self):
        self.assertEqual(self.problems(causationId=None), [])

    def test_a_boolean_is_not_an_integer(self):
        self.assertNotEqual(self.problems(version=True), [])

    def test_version_starts_at_one(self):
        self.assertNotEqual(self.problems(version=0), [])

    def test_a_date_without_a_time_is_refused(self):
        self.assertNotEqual(self.problems(occurredAt="2031-03-04"), [])

    def test_a_time_without_a_zone_is_refused(self):
        self.assertNotEqual(self.problems(occurredAt="2031-03-04T09:30:00"), [])

    def test_data_must_be_an_object(self):
        self.assertNotEqual(self.problems(data="SKU-1042"), [])

    def test_an_event_that_is_not_an_object_is_refused(self):
        self.assertNotEqual(validator.validate_event(["not", "an", "event"]), [])

    def test_the_problem_names_the_path_of_the_value(self):
        self.assertTrue(self.problems(source="acme.catalog")[0].startswith("$.source:"))


class DataSchemas(unittest.TestCase):
    """The data of an event is checked when a schema for its type and
    version exists."""

    def setUp(self):
        import tempfile

        self.directory = pathlib.Path(tempfile.mkdtemp())
        (self.directory / "envelope.schema.json").write_text(
            (ROOT / "contracts" / "events" / "envelope.schema.json").read_text(encoding="utf-8"), encoding="utf-8"
        )
        (self.directory / "ProductPublished.v1.schema.json").write_text(
            json.dumps(
                {
                    "type": "object",
                    "required": ["sku"],
                    "additionalProperties": False,
                    "properties": {"sku": {"type": "string", "pattern": "^SKU-[0-9]+$"}, "name": {"type": "string"}},
                }
            ),
            encoding="utf-8",
        )
        self.event = load(EXAMPLES / "valid" / "product-published.json")

    def test_data_matching_its_schema_passes(self):
        self.assertEqual(validator.validate_event(self.event, self.directory), [])

    def test_data_breaking_its_schema_fails_with_a_path_under_data(self):
        self.event["data"] = {"sku": "1042"}
        problems = validator.validate_event(self.event, self.directory)
        self.assertEqual(len(problems), 1)
        self.assertTrue(problems[0].startswith("$.data.sku:"))

    def test_a_version_without_a_schema_is_checked_against_the_envelope_only(self):
        self.event["version"] = 2
        self.event["data"] = {"anything": True}
        self.assertEqual(validator.validate_event(self.event, self.directory), [])


class SchemaSupport(unittest.TestCase):
    def test_an_unsupported_keyword_is_refused_and_not_ignored(self):
        with self.assertRaises(validator.UnsupportedSchema):
            validator.validate({}, {"type": "object", "oneOf": []})

    def test_an_unsupported_format_is_refused(self):
        with self.assertRaises(validator.UnsupportedSchema):
            validator.validate("a@b.c", {"type": "string", "format": "email"})

    def test_items_of_an_array_are_checked(self):
        schema = {"type": "array", "minItems": 1, "items": {"type": "integer", "minimum": 1}}
        self.assertEqual(validator.validate([1, 2], schema), [])
        self.assertEqual(len(validator.validate([1, 0], schema)), 1)
        self.assertEqual(len(validator.validate([], schema)), 1)

    def test_every_schema_in_the_repository_uses_supported_keywords_only(self):
        def keywords(schema):
            found = set(schema)
            for child in schema.get("properties", {}).values():
                found |= keywords(child)
            if isinstance(schema.get("items"), dict):
                found |= keywords(schema["items"])
            return found

        for file in sorted((ROOT / "contracts" / "events").glob("*.schema.json")):
            with self.subTest(file=file.name):
                self.assertEqual(keywords(load(file)) - validator.SUPPORTED, set())


if __name__ == "__main__":
    unittest.main()
