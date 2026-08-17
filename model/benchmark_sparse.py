#!/usr/bin/env python3
"""Development benchmark for the frozen sparse TinyAI architecture.

The v1 and v2 suites have been exposed during tuning. This report is a
regression diagnostic, not independent release evidence.
"""

from __future__ import annotations

import json

import benchmark
import release_acceptance
import train as corpus
import train_sparse


def single_metrics(cases: dict[str, tuple[str, ...]], model: dict[str, object]) -> dict[str, object]:
    total = top1 = top2 = 0
    misses = []
    for expected, prompts in cases.items():
        for prompt in prompts:
            result = train_sparse.predict(prompt, model)
            ranking = [item["intent"] for item in result["top"]]
            total += 1
            top1 += int(result["intent"] == expected)
            top2 += int(expected in ranking[:2])
            if result["intent"] != expected:
                misses.append({"prompt": prompt, "expected": expected, "actual": result["intent"], "top": result["top"]})
    return {"total": total, "accuracy": top1 / total, "top2Accuracy": top2 / total, "misses": misses}


def sentiment_metrics(cases: dict[int, tuple[str, ...]], model: dict[str, object]) -> dict[str, object]:
    total = correct = 0
    misses = []
    for expected, prompts in cases.items():
        for prompt in prompts:
            result = train_sparse.predict(prompt, model)
            total += 1
            correct += int(result["sentiment"] == expected)
            if result["sentiment"] != expected:
                misses.append({"prompt": prompt, "expected": expected, "actual": result["sentiment"]})
    return {"total": total, "accuracy": correct / total, "misses": misses}


def multi_metrics(cases: tuple[tuple[str, tuple[str, str]], ...], model: dict[str, object]) -> dict[str, object]:
    top2 = top3 = 0
    results = []
    for prompt, expected in cases:
        result = train_sparse.predict(prompt, model)
        ranking = [item["intent"] for item in result["top"]]
        expected_set = set(expected)
        pair2 = expected_set.issubset(set(ranking[:2]))
        pair3 = expected_set.issubset(set(ranking[:3]))
        top2 += int(pair2)
        top3 += int(pair3)
        results.append({"prompt": prompt, "expected": expected, "top": result["top"], "pairInTop2": pair2, "pairInTop3": pair3})
    return {"total": len(cases), "pairInTop2": top2 / len(cases), "pairInTop3": top3 / len(cases), "results": results}


def main() -> None:
    model = train_sparse.train_model()
    report = {
        "suite": "TinyAI sparse diagnostics over exposed v1 and v2 suites",
        "policy": "These prompts were viewed during architecture selection and are not independent release acceptance evidence.",
        "v1": {
            "single": single_metrics(benchmark.SINGLE_INTENT_CASES, model),
            "sentiment": sentiment_metrics(benchmark.SENTIMENT_CASES, model),
            "multi": multi_metrics(benchmark.MULTI_INTENT_CASES, model),
        },
        "v2": {
            "single": single_metrics(release_acceptance.CASES, model),
            "sentiment": sentiment_metrics(release_acceptance.SENTIMENT, model),
            "multi": multi_metrics(release_acceptance.MULTI, model),
        },
        "intents": [item.key for item in corpus.INTENTS],
    }
    path = train_sparse.BUILD / "sparse-diagnostics.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {
                "v1": {
                    "single": {key: value for key, value in report["v1"]["single"].items() if key != "misses"},
                    "sentiment": {key: value for key, value in report["v1"]["sentiment"].items() if key != "misses"},
                    "multi": {key: value for key, value in report["v1"]["multi"].items() if key != "results"},
                },
                "v2": {
                    "single": {key: value for key, value in report["v2"]["single"].items() if key != "misses"},
                    "sentiment": {key: value for key, value in report["v2"]["sentiment"].items() if key != "misses"},
                    "multi": {key: value for key, value in report["v2"]["multi"].items() if key != "results"},
                },
                "report": str(path),
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
