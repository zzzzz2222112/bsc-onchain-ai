#!/usr/bin/env python3
"""Compare centroid/perceptron blends without changing the release model.

This is a diagnostic script. It evaluates already-exposed benchmark suites and
must never be treated as an independent release acceptance result.
"""

from __future__ import annotations

import json
import math
from collections import Counter

import benchmark
import release_acceptance
import train


RATIOS = ((0, 1), (1, 5), (1, 3), (1, 2), (1, 1), (2, 1), (3, 1), (4, 1))


def blend(
    perceptron_weights: list[list[int]],
    perceptron_bias: list[int],
    centroid_weights: list[list[int]],
    perceptron_ratio: int,
    centroid_ratio: int,
) -> tuple[list[list[int]], list[int]]:
    mixed = [
        [
            perceptron_ratio * perceptron_weights[label][feature]
            + centroid_ratio * centroid_weights[label][feature]
            for feature in range(train.FEATURE_DIM)
        ]
        for label in range(len(perceptron_weights))
    ]
    maximum = max(1, max(abs(value) for row in mixed for value in row))
    scale = max(1, (maximum + 119) // 120)
    weights = [[max(-127, min(127, round(value / scale))) for value in row] for row in mixed]
    bias = [
        max(-32768, min(32767, round(perceptron_ratio * value / scale)))
        for value in perceptron_bias
    ]
    return weights, bias


def build_components(
    samples: list[tuple[str, int]], classes: int, epochs: int, seed: int
) -> tuple[list[list[int]], list[int], list[list[int]]]:
    raw_weights, raw_bias = train.train_perceptron(samples, classes, epochs, seed)
    perceptron_weights, perceptron_bias, _ = train.quantize(raw_weights, raw_bias)
    centroid_weights, _ = train.train_centroid(samples, classes)
    return perceptron_weights, perceptron_bias, centroid_weights


def semantic_features(text: str) -> set[int]:
    """Return content features while dropping length/language markers."""
    features = set(train.feature_indices(text))
    cps = train.normalized_codepoints(text)
    features.discard(train.mix32(len(cps) ^ 0xE7E7E7E7) & (train.FEATURE_DIM - 1))
    features.discard(train.mix32((1 if any(cp > 127 for cp in cps) else 0) ^ 0xF8F8F8F8) & (train.FEATURE_DIM - 1))
    return features


def train_anchor_head() -> tuple[list[list[int]], list[int]]:
    """Train a positive semantic-vote head from raw anchors, not templates."""
    classes = len(train.INTENTS)
    per_class: list[Counter[int]] = [Counter() for _ in range(classes)]
    class_documents = [0 for _ in range(classes)]
    all_documents = Counter()
    for label, intent in enumerate(train.INTENTS):
        zh_terms, en_terms = train.augmentation_terms(intent.key)
        documents = (*intent.zh_examples, *intent.en_examples, *zh_terms, *en_terms)
        class_documents[label] = len(documents)
        for document in documents:
            features = semantic_features(document)
            per_class[label].update(features)
            all_documents.update(features)

    weights = [[0 for _ in range(train.FEATURE_DIM)] for _ in range(classes)]
    for label in range(classes):
        for feature, own_count in per_class[label].items():
            total_count = all_documents[feature]
            other_count = total_count - own_count
            own_rate = own_count / class_documents[label]
            other_docs = max(1, sum(class_documents) - class_documents[label])
            other_rate = other_count / other_docs
            evidence = math.log((own_rate + 0.0125) / (other_rate + 0.0125))
            purity = own_count / total_count
            if evidence <= 0.35 or purity < 0.30:
                continue
            weights[label][feature] = min(120, max(1, round(evidence * 18)))

    # Equalise row norms so classes with larger lexicons do not win by default.
    for row in weights:
        norm = math.sqrt(sum(value * value for value in row)) or 1
        row[:] = [round(value / norm * 900) for value in row]
    maximum = max(1, max(value for row in weights for value in row))
    scale = max(1, (maximum + 119) // 120)
    return [[min(127, round(value / scale)) for value in row] for row in weights], [0 for _ in range(classes)]


def blend_three(
    perceptron_weights: list[list[int]],
    perceptron_bias: list[int],
    centroid_weights: list[list[int]],
    anchor_weights: list[list[int]],
    ratios: tuple[int, int, int],
) -> tuple[list[list[int]], list[int]]:
    p_ratio, c_ratio, a_ratio = ratios
    mixed = [
        [
            p_ratio * perceptron_weights[label][feature]
            + c_ratio * centroid_weights[label][feature]
            + a_ratio * anchor_weights[label][feature]
            for feature in range(train.FEATURE_DIM)
        ]
        for label in range(len(perceptron_weights))
    ]
    maximum = max(1, max(abs(value) for row in mixed for value in row))
    scale = max(1, (maximum + 119) // 120)
    weights = [[max(-127, min(127, round(value / scale))) for value in row] for row in mixed]
    bias = [max(-32768, min(32767, round(p_ratio * value / scale))) for value in perceptron_bias]
    return weights, bias


def classification_metrics(
    cases: dict[str, tuple[str, ...]], weights: list[list[int]], bias: list[int]
) -> dict[str, float | int]:
    key_to_id = {intent.key: index for index, intent in enumerate(train.INTENTS)}
    total = top1 = top2 = 0
    for key, prompts in cases.items():
        expected = key_to_id[key]
        for prompt in prompts:
            scores = train.score(weights, bias, train.feature_counts(prompt))
            ranking = sorted(range(len(scores)), key=lambda item: (scores[item], -item), reverse=True)
            total += 1
            top1 += int(ranking[0] == expected)
            top2 += int(expected in ranking[:2])
    return {"total": total, "top1": top1 / total, "top2": top2 / total}


def sentiment_metrics(
    cases: dict[int, tuple[str, ...]], weights: list[list[int]], bias: list[int]
) -> dict[str, float | int]:
    total = correct = 0
    for expected, prompts in cases.items():
        for prompt in prompts:
            scores = train.score(weights, bias, train.feature_counts(prompt))
            actual = max(range(len(scores)), key=lambda item: (scores[item], -item))
            total += 1
            correct += int(actual == expected)
    return {"total": total, "accuracy": correct / total}


def main() -> None:
    intent_samples = train.build_intent_samples()
    sentiment_samples = train.build_sentiment_samples()
    intent_parts = build_components(intent_samples, len(train.INTENTS), 120, 20260816)
    sentiment_parts = build_components(sentiment_samples, 3, 100, 31056)
    anchor_weights, anchor_bias = train_anchor_head()

    results = []
    for perceptron_ratio, centroid_ratio in RATIOS:
        iw, ib = blend(*intent_parts, perceptron_ratio, centroid_ratio)
        sw, sb = blend(*sentiment_parts, perceptron_ratio, centroid_ratio)
        results.append(
            {
                "ratio": f"{perceptron_ratio}:{centroid_ratio}",
                "intent": {
                    "benchmark": classification_metrics(benchmark.SINGLE_INTENT_CASES, iw, ib),
                    "releaseV2Diagnostic": classification_metrics(release_acceptance.CASES, iw, ib),
                },
                "sentiment": {
                    "benchmark": sentiment_metrics(benchmark.SENTIMENT_CASES, sw, sb),
                    "releaseV2Diagnostic": sentiment_metrics(release_acceptance.SENTIMENT, sw, sb),
                },
            }
        )
    for ratios in ((0, 0, 1), (1, 0, 1), (1, 1, 1), (1, 1, 2), (2, 1, 2), (3, 1, 2), (3, 1, 3), (3, 1, 4)):
        iw, ib = blend_three(*intent_parts, anchor_weights, ratios)
        results.append(
            {
                "ratio": f"perceptron:centroid:anchor={ratios[0]}:{ratios[1]}:{ratios[2]}",
                "intent": {
                    "benchmark": classification_metrics(benchmark.SINGLE_INTENT_CASES, iw, ib),
                    "releaseV2Diagnostic": classification_metrics(release_acceptance.CASES, iw, ib),
                },
            }
        )
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
