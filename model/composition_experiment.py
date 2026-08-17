#!/usr/bin/env python3
"""Diagnostic for sparse multi-topic detection and top-two intent recall."""

from __future__ import annotations

import json
import re

import benchmark
import evm_sparse_experiment as evm
import release_acceptance
import sparse_experiment as sparse
import train


sparse.token_features = evm.evm_token_features


def gate_metrics(
    single_cases: dict[str, tuple[str, ...]],
    multi_cases: tuple[tuple[str, tuple[str, str]], ...],
    weights: list[list[int]],
    bias: list[int],
    vocabulary: dict[str, int],
) -> dict[str, float]:
    single_total = single_correct = 0
    for prompts in single_cases.values():
        for prompt in prompts:
            scores = sparse.score(weights, bias, sparse.vector(prompt, vocabulary))
            actual = max(range(2), key=lambda item: (scores[item], -item))
            single_total += 1
            single_correct += int(actual == 0)
    multi_correct = 0
    for prompt, _ in multi_cases:
        scores = sparse.score(weights, bias, sparse.vector(prompt, vocabulary))
        actual = max(range(2), key=lambda item: (scores[item], -item))
        multi_correct += int(actual == 1)
    specificity = single_correct / single_total
    recall = multi_correct / len(multi_cases)
    return {"singleSpecificity": specificity, "multiRecall": recall, "balancedAccuracy": (specificity + recall) / 2}


def pair_metrics(
    multi_cases: tuple[tuple[str, tuple[str, str]], ...],
    weights: list[list[int]],
    bias: list[int],
    vocabulary: dict[str, int],
) -> dict[str, float]:
    key_to_id = {intent.key: index for index, intent in enumerate(train.INTENTS)}
    top2 = top3 = 0
    for prompt, expected_keys in multi_cases:
        expected = {key_to_id[key] for key in expected_keys}
        scores = sparse.score(weights, bias, sparse.vector(prompt, vocabulary))
        ranking = sorted(range(len(scores)), key=lambda item: (scores[item], -item), reverse=True)
        top2 += int(expected.issubset(set(ranking[:2])))
        top3 += int(expected.issubset(set(ranking[:3])))
    return {"pairInTop2": top2 / len(multi_cases), "pairInTop3": top3 / len(multi_cases)}


SEPARATORS = re.compile(
    r"(?:，?\s*(?:顺便|另外|同时|以及|并且|然后|再说|还要|又|再讲|再解释)\s*|[；;]|,?\s+(?:and|plus|while|then|also)\s+)",
    re.IGNORECASE,
)


def best_intent(prompt: str, weights: list[list[int]], bias: list[int], vocabulary: dict[str, int]) -> tuple[int, int, int]:
    features = sparse.vector(prompt, vocabulary)
    scores = sparse.score(weights, bias, features)
    ranking = sorted(range(len(scores)), key=lambda item: (scores[item], -item), reverse=True)
    margin = scores[ranking[0]] - scores[ranking[1]]
    return ranking[0], margin, len(features)


def segmented_pair_metrics(
    multi_cases: tuple[tuple[str, tuple[str, str]], ...],
    weights: list[list[int]],
    bias: list[int],
    vocabulary: dict[str, int],
) -> dict[str, object]:
    key_to_id = {intent.key: index for index, intent in enumerate(train.INTENTS)}
    correct = split_count = 0
    results = []
    for prompt, expected_keys in multi_cases:
        expected = {key_to_id[key] for key in expected_keys}
        candidates = []
        for match in SEPARATORS.finditer(prompt):
            left = prompt[: match.start()].strip(" ,，;；")
            right = prompt[match.end() :].strip(" ,，;；")
            if not left or not right:
                continue
            left_intent, left_margin, left_known = best_intent(left, weights, bias, vocabulary)
            right_intent, right_margin, right_known = best_intent(right, weights, bias, vocabulary)
            if left_intent == right_intent or left_known == 0 or right_known == 0:
                continue
            candidates.append((left_margin + right_margin + left_known + right_known, left_intent, right_intent, left, right))
        if candidates:
            _, left_intent, right_intent, left, right = max(candidates)
            pair = {left_intent, right_intent}
            split_count += 1
        else:
            features = sparse.vector(prompt, vocabulary)
            scores = sparse.score(weights, bias, features)
            ranking = sorted(range(len(scores)), key=lambda item: (scores[item], -item), reverse=True)
            pair = set(ranking[:2])
            left = right = ""
        matched = pair == expected
        correct += int(matched)
        results.append(
            {
                "prompt": prompt,
                "expected": expected_keys,
                "actual": tuple(train.INTENTS[item].key for item in sorted(pair)),
                "split": (left, right) if left else None,
                "matched": matched,
            }
        )
    return {"accuracy": correct / len(multi_cases), "splitRate": split_count / len(multi_cases), "results": results}


def main() -> None:
    intent_samples = train.build_intent_samples()
    iv = sparse.build_vocabulary(intent_samples)
    ipw, ipb = sparse.perceptron(intent_samples, len(train.INTENTS), iv)
    icw, _ = sparse.centroid(intent_samples, len(train.INTENTS), iv)
    iw, ib = sparse.quantized_blend(ipw, ipb, icw, (3, 1))

    composition_samples = train.build_composition_samples(intent_samples)
    cv = sparse.build_vocabulary(composition_samples)
    cpw, cpb = sparse.perceptron(composition_samples, 2, cv)
    ccw, _ = sparse.centroid(composition_samples, 2, cv)
    results = {
        "intentVocabulary": len(iv),
        "compositionVocabulary": len(cv),
        "pairRecall": {
            "benchmark": pair_metrics(benchmark.MULTI_INTENT_CASES, iw, ib, iv),
            "releaseV2Diagnostic": pair_metrics(release_acceptance.MULTI, iw, ib, iv),
        },
        "intentBlendPairDiagnostics": [],
        "segmentedPair": {
            "benchmark": segmented_pair_metrics(benchmark.MULTI_INTENT_CASES, iw, ib, iv),
            "releaseV2Diagnostic": segmented_pair_metrics(release_acceptance.MULTI, iw, ib, iv),
        },
        "gate": [],
    }
    for intent_ratio in ((1, 0), (3, 1), (2, 1), (1, 1), (1, 2), (1, 3), (0, 1)):
        diagnostic_iw, diagnostic_ib = sparse.quantized_blend(ipw, ipb, icw, intent_ratio)
        results["intentBlendPairDiagnostics"].append(
            {
                "ratio": f"{intent_ratio[0]}:{intent_ratio[1]}",
                "benchmark": pair_metrics(benchmark.MULTI_INTENT_CASES, diagnostic_iw, diagnostic_ib, iv),
                "releaseV2Diagnostic": pair_metrics(release_acceptance.MULTI, diagnostic_iw, diagnostic_ib, iv),
            }
        )
    for ratio in ((1, 0), (3, 1), (1, 1), (1, 2), (0, 1)):
        cw, cb = sparse.quantized_blend(cpw, cpb, ccw, ratio)
        # Conservative bias: require extra evidence before returning two full replies.
        for margin in (0, 20, 50, 100, 200):
            adjusted = [cb[0] + margin // 2, cb[1] - margin // 2]
            results["gate"].append(
                {
                    "ratio": f"{ratio[0]}:{ratio[1]}",
                    "margin": margin,
                    "benchmark": gate_metrics(benchmark.SINGLE_INTENT_CASES, benchmark.MULTI_INTENT_CASES, cw, adjusted, cv),
                    "releaseV2Diagnostic": gate_metrics(release_acceptance.CASES, release_acceptance.MULTI, cw, adjusted, cv),
                }
            )
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
