#!/usr/bin/env python3
"""Diagnose a hierarchical on-chain intent head.

All suites used here have already been exposed during development. Results are
diagnostic only and cannot be used as final release acceptance evidence.
"""

from __future__ import annotations

import json

import benchmark
import release_acceptance
import train


GROUPS = (
    ("social", {"greeting", "humor", "thanks", "goodbye"}),
    ("self", {"identity", "capabilities", "onchain_truth", "comparison"}),
    (
        "chain_topic",
        {"market_price", "security_risk", "contract_explain", "tokenomics", "defi", "nft", "wallet", "transaction", "gas", "code_help"},
    ),
    ("product", {"planning", "brainstorm", "governance"}),
    ("emotion", {"positive_emotion", "negative_emotion"}),
    ("context", {"privacy", "memory", "followup"}),
    ("unknown", {"unknown"}),
)
KEY_TO_GROUP = {key: group for group, (_, keys) in enumerate(GROUPS) for key in keys}


def build_group_samples() -> list[tuple[str, int]]:
    samples = []
    for text, intent_id in train.build_intent_samples():
        samples.append((text, KEY_TO_GROUP[train.INTENTS[intent_id].key]))
    return samples


def rankings(
    prompt: str,
    intent_weights: list[list[int]],
    intent_bias: list[int],
    group_weights: list[list[int]],
    group_bias: list[int],
    intent_ratio: int,
    group_ratio: int,
) -> tuple[list[int], list[int]]:
    features = train.feature_counts(prompt)
    intent_scores = train.score(intent_weights, intent_bias, features)
    group_scores = train.score(group_weights, group_bias, features)
    combined = [
        intent_ratio * intent_scores[intent]
        + group_ratio * group_scores[KEY_TO_GROUP[train.INTENTS[intent].key]]
        for intent in range(len(train.INTENTS))
    ]
    intent_ranking = sorted(range(len(combined)), key=lambda item: (combined[item], -item), reverse=True)
    group_ranking = sorted(range(len(group_scores)), key=lambda item: (group_scores[item], -item), reverse=True)
    return intent_ranking, group_ranking


def evaluate(
    cases: dict[str, tuple[str, ...]],
    heads: tuple[list[list[int]], list[int], list[list[int]], list[int]],
    ratio: tuple[int, int],
) -> dict[str, float | int]:
    iw, ib, gw, gb = heads
    key_to_intent = {intent.key: index for index, intent in enumerate(train.INTENTS)}
    total = top1 = top2 = group_top1 = 0
    for key, prompts in cases.items():
        expected_intent = key_to_intent[key]
        expected_group = KEY_TO_GROUP[key]
        for prompt in prompts:
            intent_ranking, group_ranking = rankings(prompt, iw, ib, gw, gb, *ratio)
            total += 1
            top1 += int(intent_ranking[0] == expected_intent)
            top2 += int(expected_intent in intent_ranking[:2])
            group_top1 += int(group_ranking[0] == expected_group)
    return {"total": total, "top1": top1 / total, "top2": top2 / total, "groupTop1": group_top1 / total}


def main() -> None:
    iw, ib, *_ = train.train_quantized_heads()
    gw, gb, scale = train.train_blended_head(build_group_samples(), len(GROUPS), 120, 90210)
    heads = iw, ib, gw, gb
    results = []
    for ratio in ((1, 0), (4, 1), (3, 1), (2, 1), (1, 1), (1, 2), (1, 3), (1, 4)):
        results.append(
            {
                "intentToGroupRatio": f"{ratio[0]}:{ratio[1]}",
                "groupScale": scale,
                "benchmark": evaluate(benchmark.SINGLE_INTENT_CASES, heads, ratio),
                "releaseV2Diagnostic": evaluate(release_acceptance.CASES, heads, ratio),
            }
        )
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
