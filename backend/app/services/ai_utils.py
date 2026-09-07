"""Shared helpers for Groq-based structured-output generation. Used by
`app.db.ai_seed` (offline exercise/achievement/challenge content seeding)
and `app.services.ai_plan_generator` (live, per-user workout program
generation) — both need the same "ask for JSON matching a Pydantic model,
get a validated instance back" pattern.

Only a handful of Groq-hosted models support `response_format: {"type":
"json_schema", ..., "strict": true}` (GPT-OSS 20B/120B, Qwen3(.6/.8) 27B as
of writing) — see `MODEL` below.
"""

from typing import Any

from groq import AsyncGroq
from pydantic import BaseModel

MODEL = "openai/gpt-oss-120b"


def strict_schema(model: type[BaseModel]) -> dict[str, Any]:
    """Pydantic's `model_json_schema()` only marks a field `required` when
    it has no Python-side default — Groq's strict mode requires *every*
    property to be listed in `required` (a nullable/optional field is
    expressed by its type accepting `null`, not by omitting it from
    `required`) and every object to set `additionalProperties: false`.
    Walks the schema (including `$defs`, array `items`, and `anyOf`/
    `allOf`/`oneOf` branches) and forces both, recursively.
    """
    schema = model.model_json_schema()

    def _tighten(node: Any) -> None:
        if not isinstance(node, dict):
            return
        if node.get("type") == "object" and "properties" in node:
            node["required"] = list(node["properties"].keys())
            node["additionalProperties"] = False
        for key in ("properties", "$defs"):
            for v in node.get(key, {}).values():
                _tighten(v)
        if isinstance(node.get("items"), dict):
            _tighten(node["items"])
        for key in ("anyOf", "allOf", "oneOf"):
            for v in node.get(key, []):
                _tighten(v)

    _tighten(schema)
    return schema


def max_tokens_for(count: int, per_item: int, base: int = 1000, cap: int = 32000) -> int:
    """Groq's default completion cap (undocumented) is small enough that a
    real batch request silently truncated mid-generation once, producing
    invalid JSON and a 400 from the strict-schema validator — always pass
    an explicit `max_tokens` sized to how much content was actually asked
    for instead of relying on the default."""
    return min(cap, base + count * per_item)


async def generate_structured(
    client: AsyncGroq, model: type[BaseModel], schema_name: str, prompt: str, max_tokens: int, schema: dict[str, Any] | None = None
) -> BaseModel:
    """One structured-output call: `prompt` in, a validated `model` instance
    out. Raises (via Groq's own 400 on schema-validate failure, or Pydantic's
    `ValidationError` on `model_validate_json`) if the model's response
    doesn't match `model`'s schema — callers decide how to handle that.

    `schema` lets a caller pass an already-built (and possibly further
    tightened, e.g. an exact array length via `minItems`/`maxItems`) JSON
    schema instead of the default `strict_schema(model)` — see
    `ai_plan_generator.generate_program_ai` for why that matters: without an
    exact-length constraint, the model can silently drop a day whose target
    muscles happen to match another day's (e.g. an "Upper A"/"Upper B" pair)
    and still pass basic schema validation.
    """
    response = await client.chat.completions.create(
        model=MODEL,
        max_tokens=max_tokens,
        messages=[{"role": "user", "content": prompt}],
        response_format={"type": "json_schema", "json_schema": {"name": schema_name, "strict": True, "schema": schema or strict_schema(model)}},
    )
    content = response.choices[0].message.content
    return model.model_validate_json(content)
