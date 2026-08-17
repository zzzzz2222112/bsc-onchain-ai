#!/usr/bin/env python3
"""Train TinyAI v3's sparse, deterministic on-chain semantic router.

The model is a quantized linear classifier over a public bounded vocabulary.
Training is off-chain. Tokenisation, feature lookup, integer scoring, context
resolution, and reply selection are reproduced by TinyAIChat inside the EVM.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import re
import struct
from collections import Counter
from pathlib import Path

import train as corpus


MODEL_VERSION = 3
INTENT_COUNT = len(corpus.INTENTS)
SENTIMENT_COUNT = 3
MAX_CODEPOINTS = 96
VARIANTS = 4
ENTRY_BYTES = 8 + INTENT_COUNT + SENTIMENT_COUNT
HEADER_BYTES = 16 + INTENT_COUNT * 2 + SENTIMENT_COUNT * 2
CHUNK_BYTES = 24_000
ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build"
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
    for suffix, replacement in (("ies", "y"), ("ing", ""), ("ed", ""), ("es", ""), ("s", "")):
        if len(word) >= len(suffix) + 4 and word.endswith(suffix):
            return word[: -len(suffix)] + replacement
    return word


def token_features(text: str) -> Counter[str]:
    """Extract exactly the semantic token family implemented in Solidity."""
    lowered = "".join(list(text)[:MAX_CODEPOINTS]).lower()
    features: Counter[str] = Counter()
    for word in ASCII_WORD.findall(lowered):
        if word in EN_STOP:
            continue
        features[f"w:{word}"] += 1
        root = stem(word)
        if root != word:
            features[f"w:{root}"] += 1

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


def feature_id(token: str) -> int:
    value = 0xCBF29CE484222325
    for byte in token.encode("utf-8"):
        value ^= byte
        value = value * 0x100000001B3 & 0xFFFFFFFFFFFFFFFF
    return value


def build_vocabulary(samples: list[tuple[str, int]], minimum_df: int) -> tuple[str, ...]:
    document_frequency: Counter[str] = Counter()
    for text, _ in samples:
        document_frequency.update(token_features(text).keys())
    return tuple(sorted(token for token, count in document_frequency.items() if count >= minimum_df))


def vector(text: str, vocabulary: dict[str, int]) -> Counter[int]:
    return Counter({vocabulary[token]: count for token, count in token_features(text).items() if token in vocabulary})


def score(weights: list[list[int]], bias: list[int], features: Counter[int]) -> list[int]:
    return [bias[label] + sum(weights[label][feature] * count for feature, count in features.items()) for label in range(len(weights))]


def train_perceptron(
    samples: list[tuple[str, int]], classes: int, vocabulary: dict[str, int], epochs: int, seed: int
) -> tuple[list[list[int]], list[int]]:
    weights = [[0 for _ in vocabulary] for _ in range(classes)]
    bias = [0 for _ in range(classes)]
    prepared = [(vector(text, vocabulary), label) for text, label in samples]
    rng = random.Random(seed)
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
                step = min(count, 3)
                weights[expected][feature] += step
                weights[actual][feature] -= step
            bias[expected] += 1
            bias[actual] -= 1
        if mistakes == 0:
            break
    return weights, bias


def train_centroid(
    samples: list[tuple[str, int]], classes: int, vocabulary: dict[str, int]
) -> tuple[list[list[int]], list[int]]:
    prepared = [(vector(text, vocabulary), label) for text, label in samples]
    document_frequency = [0 for _ in vocabulary]
    class_documents = [0 for _ in range(classes)]
    for features, label in prepared:
        class_documents[label] += 1
        for feature in features:
            document_frequency[feature] += 1
    total = len(prepared)
    rows = [[0.0 for _ in vocabulary] for _ in range(classes)]
    for features, label in prepared:
        normalization = math.sqrt(sum(count * count for count in features.values())) or 1
        for feature, count in features.items():
            inverse_frequency = math.log((total + 1) / (document_frequency[feature] + 1)) + 1
            rows[label][feature] += count * inverse_frequency / normalization
    for label, row in enumerate(rows):
        row[:] = [value / max(1, class_documents[label]) for value in row]
        norm = math.sqrt(sum(value * value for value in row)) or 1
        row[:] = [value / norm for value in row]
    maximum = max(value for row in rows for value in row) or 1
    return [[round(value / maximum * 120) for value in row] for row in rows], [0 for _ in range(classes)]


def blend(
    perceptron_weights: list[list[int]],
    perceptron_bias: list[int],
    centroid_weights: list[list[int]],
    ratio: tuple[int, int],
) -> tuple[list[list[int]], list[int], int]:
    perceptron_ratio, centroid_ratio = ratio
    mixed = [
        [
            perceptron_ratio * perceptron_weights[label][feature]
            + centroid_ratio * centroid_weights[label][feature]
            for feature in range(len(perceptron_weights[0]))
        ]
        for label in range(len(perceptron_weights))
    ]
    maximum = max(1, max(abs(value) for row in mixed for value in row))
    scale = max(1, math.ceil(maximum / 120))
    return (
        [[max(-127, min(127, round(value / scale))) for value in row] for row in mixed],
        [max(-32768, min(32767, round(perceptron_ratio * value / scale))) for value in perceptron_bias],
        scale,
    )


def train_model() -> dict[str, object]:
    intent_samples = corpus.build_intent_samples()
    sentiment_samples = corpus.build_sentiment_samples()
    intent_tokens = build_vocabulary(intent_samples, minimum_df=2)
    sentiment_tokens = build_vocabulary(sentiment_samples, minimum_df=1)
    tokens = tuple(sorted(set(intent_tokens) | set(sentiment_tokens)))
    vocabulary = {token: index for index, token in enumerate(tokens)}

    intent_perceptron, intent_perceptron_bias = train_perceptron(
        intent_samples, INTENT_COUNT, vocabulary, epochs=120, seed=2026081602
    )
    intent_centroid, _ = train_centroid(intent_samples, INTENT_COUNT, vocabulary)
    intent_weights, intent_bias, intent_scale = blend(
        intent_perceptron, intent_perceptron_bias, intent_centroid, (3, 1)
    )

    sentiment_perceptron, sentiment_perceptron_bias = train_perceptron(
        sentiment_samples, SENTIMENT_COUNT, vocabulary, epochs=100, seed=3105602
    )
    sentiment_centroid, _ = train_centroid(sentiment_samples, SENTIMENT_COUNT, vocabulary)
    sentiment_weights, sentiment_bias, sentiment_scale = blend(
        sentiment_perceptron, sentiment_perceptron_bias, sentiment_centroid, (1, 1)
    )

    token_ids: dict[int, str] = {}
    for token in tokens:
        token_id = feature_id(token)
        previous = token_ids.get(token_id)
        if previous is not None and previous != token:
            raise RuntimeError(f"64-bit feature collision: {previous!r} versus {token!r}")
        token_ids[token_id] = token

    active = []
    for token, feature in vocabulary.items():
        intent_row = [intent_weights[label][feature] for label in range(INTENT_COUNT)]
        sentiment_row = [sentiment_weights[label][feature] for label in range(SENTIMENT_COUNT)]
        if any(intent_row) or any(sentiment_row):
            active.append((feature_id(token), token, intent_row, sentiment_row))
    active.sort(key=lambda item: item[0])

    return {
        "tokens": tokens,
        "vocabulary": vocabulary,
        "active": active,
        "intentWeights": intent_weights,
        "intentBias": intent_bias,
        "sentimentWeights": sentiment_weights,
        "sentimentBias": sentiment_bias,
        "intentScale": intent_scale,
        "sentimentScale": sentiment_scale,
        "intentSamples": intent_samples,
        "sentimentSamples": sentiment_samples,
    }


def predict(text: str, model: dict[str, object]) -> dict[str, object]:
    vocabulary = model["vocabulary"]
    features = vector(text, vocabulary)  # type: ignore[arg-type]
    intent_scores = score(model["intentWeights"], model["intentBias"], features)  # type: ignore[arg-type]
    sentiment_scores = score(model["sentimentWeights"], model["sentimentBias"], features)  # type: ignore[arg-type]
    intent_ranking = sorted(range(INTENT_COUNT), key=lambda item: (intent_scores[item], -item), reverse=True)
    sentiment = max(range(SENTIMENT_COUNT), key=lambda item: (sentiment_scores[item], -item))
    if not features:
        intent_ranking.remove(26)
        intent_ranking.insert(0, 26)
    return {
        "intentId": intent_ranking[0],
        "intent": corpus.INTENTS[intent_ranking[0]].key,
        "sentiment": sentiment,
        "recognizedFeatures": sum(features.values()),
        "margin": intent_scores[intent_ranking[0]] - intent_scores[intent_ranking[1]],
        "top": [
            {"intentId": item, "intent": corpus.INTENTS[item].key, "score": intent_scores[item]}
            for item in intent_ranking[:3]
        ],
    }


def pack_model(model: dict[str, object]) -> bytes:
    active = model["active"]
    payload = bytearray(
        b"TAS1"
        + bytes((MODEL_VERSION, INTENT_COUNT, SENTIMENT_COUNT, MAX_CODEPOINTS))
        + struct.pack(">H", ENTRY_BYTES)
        + struct.pack(">I", len(active))
        + struct.pack(">H", HEADER_BYTES)
    )
    for value in model["intentBias"]:
        payload.extend(struct.pack(">h", value))
    for value in model["sentimentBias"]:
        payload.extend(struct.pack(">h", value))
    for token_id, _, intent_row, sentiment_row in active:
        payload.extend(struct.pack(">Q", token_id))
        payload.extend(struct.pack(f">{INTENT_COUNT}b", *intent_row))
        payload.extend(struct.pack(f">{SENTIMENT_COUNT}b", *sentiment_row))
    return bytes(payload)


def accuracy(samples: list[tuple[str, int]], model: dict[str, object], field: str) -> float:
    return sum(int(predict(text, model)[field] == expected) for text, expected in samples) / len(samples)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", help="print one reference inference")
    args = parser.parse_args()
    model = train_model()
    model_blob = pack_model(model)
    chunks = [model_blob[offset : offset + CHUNK_BYTES] for offset in range(0, len(model_blob), CHUNK_BYTES)]
    zh_lexicon = corpus.pack_lexicon("zh")
    en_lexicon = corpus.pack_lexicon("en")

    corpus_payload = json.dumps(
        {
            "intents": [
                {
                    "key": intent.key,
                    "zhExamples": intent.zh_examples,
                    "enExamples": intent.en_examples,
                    "zhReplies": intent.zh_replies,
                    "enReplies": intent.en_replies,
                }
                for intent in corpus.INTENTS
            ],
            "sentiment": corpus.SENTIMENT_EXAMPLES,
            "augmentation": corpus.AUGMENT_TERMS,
            "extraAugmentation": corpus.EXTRA_AUGMENT_TERMS,
            "semanticPrimitives": corpus.SEMANTIC_PRIMITIVES,
            "semanticExpansion": corpus.SEMANTIC_EXPANSION,
            "semanticRefinement": corpus.SEMANTIC_REFINEMENT,
            "architecture": "sparse-token-linear-v3",
        },
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")

    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / "model.bin").write_bytes(model_blob)
    for stale in BUILD.glob("model-*.bin"):
        stale.unlink()
    for index, chunk in enumerate(chunks):
        (BUILD / f"model-{index}.bin").write_bytes(chunk)
    (BUILD / "lexicon-zh.bin").write_bytes(zh_lexicon)
    (BUILD / "lexicon-en.bin").write_bytes(en_lexicon)
    corpus_hash = hashlib.sha256(corpus_payload).hexdigest()
    (BUILD / "corpus.sha256").write_text(corpus_hash + "\n", encoding="ascii")

    vectors = [
        "你好，你是谁", "这次聊天真的在链上推理吗", "一次聊天需要多少 Gas", "管理员能升级模型吗",
        "我今天终于成功了", "我的交易为什么失败", "How do I protect my wallet?", "Tell me the live BNB price",
        "Can the model be upgraded?", "Give me a fun onchain AI idea",
    ]
    (BUILD / "vectors.json").write_text(
        json.dumps([{"prompt": text, **predict(text, model)} for text in vectors], ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    manifest = {
        "name": "TinyAI Sparse Semantic Router",
        "version": MODEL_VERSION,
        "architecture": "bounded semantic tokens -> collision-checked uint64 dictionary -> int8 intent and sentiment heads -> immutable reply lexicon",
        "maxCodepoints": MAX_CODEPOINTS,
        "intents": [intent.key for intent in corpus.INTENTS],
        "intentCount": INTENT_COUNT,
        "sentimentCount": SENTIMENT_COUNT,
        "entryBytes": ENTRY_BYTES,
        "headerBytes": HEADER_BYTES,
        "vocabularyTokens": len(model["tokens"]),
        "activeFeatures": len(model["active"]),
        "intentTrainingExamples": len(model["intentSamples"]),
        "sentimentTrainingExamples": len(model["sentimentSamples"]),
        "intentTrainingAccuracy": accuracy(model["intentSamples"], model, "intentId"),
        "sentimentTrainingAccuracy": accuracy(model["sentimentSamples"], model, "sentiment"),
        "intentBlend": "3:1 quantized perceptron to TF-IDF centroid",
        "sentimentBlend": "1:1 quantized perceptron to TF-IDF centroid",
        "intentScale": model["intentScale"],
        "sentimentScale": model["sentimentScale"],
        "modelBytes": len(model_blob),
        "chunkBytes": CHUNK_BYTES,
        "chunks": [
            {"file": f"model-{index}.bin", "bytes": len(chunk), "sha256": hashlib.sha256(chunk).hexdigest()}
            for index, chunk in enumerate(chunks)
        ],
        "modelSha256": hashlib.sha256(model_blob).hexdigest(),
        "zhLexiconBytes": len(zh_lexicon),
        "enLexiconBytes": len(en_lexicon),
        "zhLexiconSha256": hashlib.sha256(zh_lexicon).hexdigest(),
        "enLexiconSha256": hashlib.sha256(en_lexicon).hexdigest(),
        "corpusSha256": corpus_hash,
        "truthBoundary": "Training is off-chain. Tokenisation, dictionary lookup, integer scoring, follow-up resolution, memory update, and final response bytes execute on-chain.",
        "capacityBoundary": "This is a bounded semantic classifier with immutable replies, not a generative LLM. Unknown synonyms and open-world facts can fail or fall back.",
    }
    (BUILD / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    if args.check:
        print(json.dumps(predict(args.check, model), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
