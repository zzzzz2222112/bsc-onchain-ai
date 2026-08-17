#!/usr/bin/env python3
"""Test a collision-free sparse token model for TinyAI.

The benchmark suites used here are already exposed and therefore diagnostic.
This script helps select an architecture; it is not release evidence.
"""

from __future__ import annotations

import json
import math
import random
import re
from collections import Counter

import benchmark
import release_acceptance
import train


ASCII_WORD = re.compile(r"[a-z0-9]+(?:[-'][a-z0-9]+)*")
ZH_STOP = set("的了吗呢啊呀吧是有在和与或又我你他她它这那请想问说给帮把个一会能可为从到很太更最再先后也都就而及其")
EN_STOP = {
    "a", "an", "the", "is", "are", "am", "be", "been", "being", "to", "of", "for", "in", "on", "at", "by",
    "with", "and", "or", "but", "if", "then", "than", "this", "that", "these", "those", "it", "its", "i", "me",
    "my", "you", "your", "we", "our", "they", "their", "what", "which", "who", "where", "when", "why", "how",
    "can", "could", "would", "should", "will", "do", "does", "did", "have", "has", "had", "about", "tell", "explain",
    "help", "want", "please", "give", "show", "make", "get", "from", "into", "after", "before", "also", "really",
}


def stem(word: str) -> str:
    replacements = (("ies", "y"), ("ing", ""), ("ed", ""), ("es", ""), ("s", ""))
    for suffix, replacement in replacements:
        if len(word) >= len(suffix) + 4 and word.endswith(suffix):
            return word[: -len(suffix)] + replacement
    return word


def token_features(text: str) -> Counter[str]:
    lowered = text.lower()
    features: Counter[str] = Counter()
    words = ASCII_WORD.findall(lowered)
    content_words = []
    for word in words:
        root = stem(word)
        if root not in EN_STOP:
            features[f"w:{root}"] += 1
            content_words.append(root)
    for left, right in zip(content_words, content_words[1:]):
        features[f"b:{left}_{right}"] += 1

    run: list[str] = []
    def flush() -> None:
        if not run:
            return
        for size in (1, 2, 3, 4):
            for start in range(len(run) - size + 1):
                token = "".join(run[start : start + size])
                if size == 1 and token in ZH_STOP:
                    continue
                features[f"z{size}:{token}"] += 1
        run.clear()

    for char in lowered:
        cp = ord(char)
        if 0x3400 <= cp <= 0x9FFF:
            run.append(char)
        else:
            flush()
    flush()
    return features


def build_vocabulary(samples: list[tuple[str, int]], minimum_df: int = 2) -> dict[str, int]:
    df: Counter[str] = Counter()
    for text, _ in samples:
        df.update(token_features(text).keys())
    tokens = sorted(token for token, count in df.items() if count >= minimum_df)
    return {token: index for index, token in enumerate(tokens)}


def vector(text: str, vocabulary: dict[str, int]) -> Counter[int]:
    return Counter({vocabulary[token]: count for token, count in token_features(text).items() if token in vocabulary})


def score(weights: list[list[int]], bias: list[int], features: Counter[int]) -> list[int]:
    return [bias[label] + sum(weights[label][feature] * count for feature, count in features.items()) for label in range(len(weights))]


def perceptron(
    samples: list[tuple[str, int]], classes: int, vocabulary: dict[str, int], epochs: int = 120
) -> tuple[list[list[int]], list[int]]:
    weights = [[0 for _ in vocabulary] for _ in range(classes)]
    bias = [0 for _ in range(classes)]
    prepared = [(vector(text, vocabulary), label) for text, label in samples]
    rng = random.Random(2026081602)
    for _ in range(epochs):
        order = list(range(len(prepared)))
        rng.shuffle(order)
        mistakes = 0
        for position in order:
            features, expected = prepared[position]
            scores = score(weights, bias, features)
            actual = max(range(classes), key=lambda item: (scores[item], -item))
            if actual == expected:
                continue
            mistakes += 1
            for feature, count in features.items():
                step = min(3, count)
                weights[expected][feature] += step
                weights[actual][feature] -= step
            bias[expected] += 1
            bias[actual] -= 1
        if mistakes == 0:
            break
    return weights, bias


def centroid(
    samples: list[tuple[str, int]], classes: int, vocabulary: dict[str, int]
) -> tuple[list[list[int]], list[int]]:
    prepared = [(vector(text, vocabulary), label) for text, label in samples]
    df = [0 for _ in vocabulary]
    class_documents = [0 for _ in range(classes)]
    for features, label in prepared:
        class_documents[label] += 1
        for feature in features:
            df[feature] += 1
    rows = [[0.0 for _ in vocabulary] for _ in range(classes)]
    total = len(prepared)
    for features, label in prepared:
        norm = math.sqrt(sum(count * count for count in features.values())) or 1
        for feature, count in features.items():
            idf = math.log((total + 1) / (df[feature] + 1)) + 1
            rows[label][feature] += count * idf / norm
    for label, row in enumerate(rows):
        row[:] = [value / max(1, class_documents[label]) for value in row]
        norm = math.sqrt(sum(value * value for value in row)) or 1
        row[:] = [value / norm for value in row]
    maximum = max(value for row in rows for value in row) or 1
    return [[round(value / maximum * 120) for value in row] for row in rows], [0 for _ in range(classes)]


def quantized_blend(
    p_weights: list[list[int]], p_bias: list[int], c_weights: list[list[int]], ratio: tuple[int, int]
) -> tuple[list[list[int]], list[int]]:
    p_ratio, c_ratio = ratio
    mixed = [
        [p_ratio * p_weights[label][feature] + c_ratio * c_weights[label][feature] for feature in range(len(p_weights[0]))]
        for label in range(len(p_weights))
    ]
    maximum = max(1, max(abs(value) for row in mixed for value in row))
    scale = max(1, math.ceil(maximum / 120))
    return (
        [[max(-127, min(127, round(value / scale))) for value in row] for row in mixed],
        [max(-32768, min(32767, round(p_ratio * value / scale))) for value in p_bias],
    )


def evaluate(cases: dict[str, tuple[str, ...]], weights: list[list[int]], bias: list[int], vocabulary: dict[str, int]) -> dict[str, object]:
    key_to_id = {intent.key: index for index, intent in enumerate(train.INTENTS)}
    total = top1 = top2 = 0
    misses = []
    for expected_key, prompts in cases.items():
        expected = key_to_id[expected_key]
        for prompt in prompts:
            features = vector(prompt, vocabulary)
            scores = score(weights, bias, features)
            ranking = sorted(range(len(scores)), key=lambda item: (scores[item], -item), reverse=True)
            total += 1
            top1 += int(ranking[0] == expected)
            top2 += int(expected in ranking[:2])
            if ranking[0] != expected:
                misses.append((prompt, expected_key, train.INTENTS[ranking[0]].key, len(features)))
    return {"total": total, "top1": top1 / total, "top2": top2 / total, "misses": misses}


def evaluate_numeric(cases: dict[int, tuple[str, ...]], weights: list[list[int]], bias: list[int], vocabulary: dict[str, int]) -> dict[str, object]:
    total = correct = 0
    misses = []
    for expected, prompts in cases.items():
        for prompt in prompts:
            features = vector(prompt, vocabulary)
            scores = score(weights, bias, features)
            actual = max(range(len(scores)), key=lambda item: (scores[item], -item))
            total += 1
            correct += int(actual == expected)
            if actual != expected:
                misses.append((prompt, expected, actual, len(features)))
    return {"total": total, "accuracy": correct / total, "misses": misses}


def main() -> None:
    samples = train.build_intent_samples()
    vocabulary = build_vocabulary(samples)
    p_weights, p_bias = perceptron(samples, len(train.INTENTS), vocabulary)
    c_weights, _ = centroid(samples, len(train.INTENTS), vocabulary)

    sentiment_samples = train.build_sentiment_samples()
    sentiment_vocabulary = build_vocabulary(sentiment_samples, minimum_df=1)
    sp_weights, sp_bias = perceptron(sentiment_samples, 3, sentiment_vocabulary)
    sc_weights, _ = centroid(sentiment_samples, 3, sentiment_vocabulary)
    sentiment_weights, sentiment_bias = quantized_blend(sp_weights, sp_bias, sc_weights, (1, 1))
    results = []
    for ratio in ((1, 0), (0, 1), (1, 3), (1, 2), (1, 1), (2, 1), (3, 1)):
        weights, bias = quantized_blend(p_weights, p_bias, c_weights, ratio)
        results.append(
            {
                "ratio": f"{ratio[0]}:{ratio[1]}",
                "vocabulary": len(vocabulary),
                "benchmark": evaluate(benchmark.SINGLE_INTENT_CASES, weights, bias, vocabulary),
                "releaseV2Diagnostic": evaluate(release_acceptance.CASES, weights, bias, vocabulary),
                "sentiment": {
                    "vocabulary": len(sentiment_vocabulary),
                    "benchmark": evaluate_numeric(benchmark.SENTIMENT_CASES, sentiment_weights, sentiment_bias, sentiment_vocabulary),
                    "releaseV2Diagnostic": evaluate_numeric(release_acceptance.SENTIMENT, sentiment_weights, sentiment_bias, sentiment_vocabulary),
                },
            }
        )
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
