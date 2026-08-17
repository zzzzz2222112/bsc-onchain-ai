#!/usr/bin/env python3
"""Diagnostic for a sparse hierarchical intent head over exposed suites."""

from __future__ import annotations

import json

import benchmark
import release_acceptance
import release_acceptance_v3
import train as corpus
import train_sparse


GROUPS = (
    {"greeting", "humor", "thanks", "goodbye"},
    {"identity", "capabilities", "onchain_truth", "comparison"},
    {"market_price", "security_risk", "tokenomics", "defi", "nft"},
    {"wallet", "transaction", "gas"},
    {"contract_explain", "code_help", "planning", "brainstorm", "governance"},
    {"positive_emotion", "negative_emotion"},
    {"privacy", "memory", "followup"},
    {"unknown"},
)
KEY_TO_GROUP = {key: group for group, keys in enumerate(GROUPS) for key in keys}


def evaluate(
    cases: dict[str, tuple[str, ...]],
    model: dict[str, object],
    group_weights: list[list[int]],
    group_bias: list[int],
    ratio: tuple[int, int],
) -> dict[str, float]:
    key_to_id = {intent.key: index for index, intent in enumerate(corpus.INTENTS)}
    total = top1 = top2 = group_top1 = 0
    for expected_key, prompts in cases.items():
        for prompt in prompts:
            features = train_sparse.vector(prompt, model["vocabulary"])
            intent_scores = train_sparse.score(model["intentWeights"], model["intentBias"], features)
            group_scores = train_sparse.score(group_weights, group_bias, features)
            combined = [
                ratio[0] * intent_scores[intent] + ratio[1] * group_scores[KEY_TO_GROUP[corpus.INTENTS[intent].key]]
                for intent in range(len(corpus.INTENTS))
            ]
            ranking = sorted(range(len(combined)), key=lambda item: (combined[item], -item), reverse=True)
            groups = sorted(range(len(GROUPS)), key=lambda item: (group_scores[item], -item), reverse=True)
            expected = key_to_id[expected_key]
            total += 1
            top1 += int(ranking[0] == expected)
            top2 += int(expected in ranking[:2])
            group_top1 += int(groups[0] == KEY_TO_GROUP[expected_key])
    return {"top1": top1 / total, "top2": top2 / total, "groupTop1": group_top1 / total}


def main() -> None:
    model = train_sparse.train_model()
    group_samples = [
        (text, KEY_TO_GROUP[corpus.INTENTS[intent].key]) for text, intent in corpus.build_intent_samples()
    ]
    vocabulary = model["vocabulary"]
    pw, pb = train_sparse.train_perceptron(group_samples, len(GROUPS), vocabulary, 120, 80260816)
    cw, _ = train_sparse.train_centroid(group_samples, len(GROUPS), vocabulary)
    gw, gb, scale = train_sparse.blend(pw, pb, cw, (3, 1))
    results = []
    for ratio in ((1, 0), (8, 1), (6, 1), (4, 1), (3, 1), (2, 1), (1, 1), (1, 2)):
        results.append(
            {
                "ratio": f"{ratio[0]}:{ratio[1]}",
                "groupScale": scale,
                "v1": evaluate(benchmark.SINGLE_INTENT_CASES, model, gw, gb, ratio),
                "v2": evaluate(release_acceptance.CASES, model, gw, gb, ratio),
                "v3": evaluate(release_acceptance_v3.CASES, model, gw, gb, ratio),
            }
        )
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
