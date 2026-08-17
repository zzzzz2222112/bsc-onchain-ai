#!/usr/bin/env python3
"""Diagnose semantic-anchor oversampling on already exposed suites."""

from __future__ import annotations

import argparse
import json

import benchmark
import release_acceptance
import release_acceptance_v3
import train as corpus
import train_sparse


def semantic_samples(repeats: int) -> list[tuple[str, int]]:
    samples = corpus.build_intent_samples()
    for label, intent in enumerate(corpus.INTENTS):
        zh_terms, en_terms = corpus.augmentation_terms(intent.key)
        anchors = (*intent.zh_examples, *intent.en_examples, *zh_terms, *en_terms)
        for _ in range(repeats):
            samples.extend((term, label) for term in anchors)
    return samples


def evaluate(cases: dict[str, tuple[str, ...]], model: dict[str, object]) -> dict[str, float]:
    total = top1 = top2 = 0
    for expected, prompts in cases.items():
        for prompt in prompts:
            result = train_sparse.predict(prompt, model)
            ranking = [item["intent"] for item in result["top"]]
            total += 1
            top1 += int(result["intent"] == expected)
            top2 += int(expected in ranking[:2])
    return {"top1": top1 / total, "top2": top2 / total}


def build(repeats: int) -> dict[str, object]:
    intent_samples = semantic_samples(repeats)
    sentiment_samples = corpus.build_sentiment_samples()
    tokens = tuple(sorted(set(train_sparse.build_vocabulary(intent_samples, 2)) | set(train_sparse.build_vocabulary(sentiment_samples, 1))))
    vocabulary = {token: index for index, token in enumerate(tokens)}
    pw, pb = train_sparse.train_perceptron(intent_samples, len(corpus.INTENTS), vocabulary, 120, 2026081602)
    cw, _ = train_sparse.train_centroid(intent_samples, len(corpus.INTENTS), vocabulary)
    iw, ib, _ = train_sparse.blend(pw, pb, cw, (3, 1))
    return {"vocabulary": vocabulary, "intentWeights": iw, "intentBias": ib, "sentimentWeights": [[0] * len(tokens) for _ in range(3)], "sentimentBias": [0, 0, 0]}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repeats", type=int, nargs="+", default=(0, 1, 2, 4, 8))
    args = parser.parse_args()
    results = []
    for repeats in args.repeats:
        model = build(repeats)
        results.append(
            {
                "anchorRepeats": repeats,
                "vocabulary": len(model["vocabulary"]),
                "v1": evaluate(benchmark.SINGLE_INTENT_CASES, model),
                "v2": evaluate(release_acceptance.CASES, model),
                "v3": evaluate(release_acceptance_v3.CASES, model),
            }
        )
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
