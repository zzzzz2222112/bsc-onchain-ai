#!/usr/bin/env python3
"""Development-only blend search over the exposed v1-v4 diagnostics.

This file must never be used as release evidence. It exists to compare the
linear heads without repeatedly retraining them. Any v5 suite is intentionally
kept out of this module and is authored only after the selected model freezes.
"""

from __future__ import annotations

import json
import random

import benchmark
import benchmark_sparse
import release_acceptance
import release_acceptance_v4
import train as corpus
import train_sparse


INTENT_RATIOS = ((0, 1), (1, 4), (1, 2), (1, 1), (2, 1), (3, 1), (4, 1), (8, 1), (1, 0))
SENTIMENT_RATIOS = ((0, 1), (1, 4), (1, 2), (1, 1), (2, 1), (3, 1), (4, 1), (1, 0))


def train_averaged_perceptron(
    samples: list[tuple[str, int]], classes: int, vocabulary: dict[str, int], epochs: int, seed: int
) -> tuple[list[list[int]], list[int]]:
    """Lazy averaged multiclass perceptron, scaled to retain small weights."""
    weights = [[0 for _ in vocabulary] for _ in range(classes)]
    totals = [[0 for _ in vocabulary] for _ in range(classes)]
    timestamps = [[0 for _ in vocabulary] for _ in range(classes)]
    bias = [0 for _ in range(classes)]
    bias_totals = [0 for _ in range(classes)]
    bias_timestamps = [0 for _ in range(classes)]
    prepared = [(train_sparse.vector(text, vocabulary), label) for text, label in samples]
    rng = random.Random(seed)
    step = 0
    for _ in range(epochs):
        order = list(range(len(prepared)))
        rng.shuffle(order)
        for position in order:
            step += 1
            features, expected = prepared[position]
            scores = train_sparse.score(weights, bias, features)
            actual = max(range(classes), key=lambda item: (scores[item], -item))
            if actual == expected:
                continue
            for feature, count in features.items():
                delta = min(count, 3)
                for label, change in ((expected, delta), (actual, -delta)):
                    totals[label][feature] += (step - timestamps[label][feature]) * weights[label][feature]
                    timestamps[label][feature] = step
                    weights[label][feature] += change
            for label, change in ((expected, 1), (actual, -1)):
                bias_totals[label] += (step - bias_timestamps[label]) * bias[label]
                bias_timestamps[label] = step
                bias[label] += change

    precision = 64
    averaged = [[0 for _ in vocabulary] for _ in range(classes)]
    for label in range(classes):
        for feature in range(len(vocabulary)):
            total = totals[label][feature] + (step + 1 - timestamps[label][feature]) * weights[label][feature]
            averaged[label][feature] = round(total * precision / step)
        total_bias = bias_totals[label] + (step + 1 - bias_timestamps[label]) * bias[label]
        bias[label] = round(total_bias * precision / step)
    return averaged, bias


def main() -> None:
    intent_samples = corpus.build_intent_samples()
    sentiment_samples = corpus.build_sentiment_samples()
    tokens = tuple(
        sorted(
            set(train_sparse.build_vocabulary(intent_samples, minimum_df=2))
            | set(train_sparse.build_vocabulary(sentiment_samples, minimum_df=1))
        )
    )
    vocabulary = {token: index for index, token in enumerate(tokens)}

    intent_p, intent_b = train_sparse.train_perceptron(
        intent_samples, train_sparse.INTENT_COUNT, vocabulary, epochs=120, seed=2026081602
    )
    intent_c, _ = train_sparse.train_centroid(intent_samples, train_sparse.INTENT_COUNT, vocabulary)
    sentiment_p, sentiment_b = train_sparse.train_perceptron(
        sentiment_samples, train_sparse.SENTIMENT_COUNT, vocabulary, epochs=100, seed=3105602
    )
    sentiment_c, _ = train_sparse.train_centroid(sentiment_samples, train_sparse.SENTIMENT_COUNT, vocabulary)
    averaged_intent_p, averaged_intent_b = train_averaged_perceptron(
        intent_samples, train_sparse.INTENT_COUNT, vocabulary, epochs=120, seed=2026081602
    )
    averaged_sentiment_p, averaged_sentiment_b = train_averaged_perceptron(
        sentiment_samples, train_sparse.SENTIMENT_COUNT, vocabulary, epochs=100, seed=3105602
    )

    sentiment_default, sentiment_default_bias, _ = train_sparse.blend(
        sentiment_p, sentiment_b, sentiment_c, (1, 1)
    )
    intent_default, intent_default_bias, _ = train_sparse.blend(intent_p, intent_b, intent_c, (3, 1))

    intent_results = []
    for ratio in INTENT_RATIOS:
        weights, bias, scale = train_sparse.blend(intent_p, intent_b, intent_c, ratio)
        model = {
            "vocabulary": vocabulary,
            "intentWeights": weights,
            "intentBias": bias,
            "sentimentWeights": sentiment_default,
            "sentimentBias": sentiment_default_bias,
        }
        intent_results.append(
            {
                "ratio": ratio,
                "scale": scale,
                "v1": benchmark_sparse.single_metrics(benchmark.SINGLE_INTENT_CASES, model),
                "v2": benchmark_sparse.single_metrics(release_acceptance.CASES, model),
                "v4": benchmark_sparse.single_metrics(release_acceptance_v4.CASES, model),
                "v4Multi": benchmark_sparse.multi_metrics(release_acceptance_v4.MULTI, model),
            }
        )

    sentiment_results = []
    for ratio in SENTIMENT_RATIOS:
        weights, bias, scale = train_sparse.blend(sentiment_p, sentiment_b, sentiment_c, ratio)
        model = {
            "vocabulary": vocabulary,
            "intentWeights": intent_default,
            "intentBias": intent_default_bias,
            "sentimentWeights": weights,
            "sentimentBias": bias,
        }
        sentiment_results.append(
            {
                "ratio": ratio,
                "scale": scale,
                "v1": benchmark_sparse.sentiment_metrics(benchmark.SENTIMENT_CASES, model),
                "v2": benchmark_sparse.sentiment_metrics(release_acceptance.SENTIMENT, model),
                "v4": benchmark_sparse.sentiment_metrics(release_acceptance_v4.SENTIMENT, model),
            }
        )

    averaged_intent_results = []
    for ratio in INTENT_RATIOS:
        weights, bias, scale = train_sparse.blend(averaged_intent_p, averaged_intent_b, intent_c, ratio)
        model = {
            "vocabulary": vocabulary,
            "intentWeights": weights,
            "intentBias": bias,
            "sentimentWeights": sentiment_default,
            "sentimentBias": sentiment_default_bias,
        }
        averaged_intent_results.append(
            {
                "ratio": ratio,
                "scale": scale,
                "v1": benchmark_sparse.single_metrics(benchmark.SINGLE_INTENT_CASES, model),
                "v2": benchmark_sparse.single_metrics(release_acceptance.CASES, model),
                "v4": benchmark_sparse.single_metrics(release_acceptance_v4.CASES, model),
                "v4Multi": benchmark_sparse.multi_metrics(release_acceptance_v4.MULTI, model),
            }
        )

    averaged_sentiment_results = []
    for ratio in SENTIMENT_RATIOS:
        weights, bias, scale = train_sparse.blend(averaged_sentiment_p, averaged_sentiment_b, sentiment_c, ratio)
        model = {
            "vocabulary": vocabulary,
            "intentWeights": intent_default,
            "intentBias": intent_default_bias,
            "sentimentWeights": weights,
            "sentimentBias": bias,
        }
        averaged_sentiment_results.append(
            {
                "ratio": ratio,
                "scale": scale,
                "v1": benchmark_sparse.sentiment_metrics(benchmark.SENTIMENT_CASES, model),
                "v2": benchmark_sparse.sentiment_metrics(release_acceptance.SENTIMENT, model),
                "v4": benchmark_sparse.sentiment_metrics(release_acceptance_v4.SENTIMENT, model),
            }
        )

    report = {
        "policy": "development-only exposed v1-v4 tuning",
        "intent": intent_results,
        "sentiment": sentiment_results,
        "averagedIntent": averaged_intent_results,
        "averagedSentiment": averaged_sentiment_results,
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
