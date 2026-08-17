#!/usr/bin/env python3
"""Train TinyAI v6's deterministic autoregressive neural token generator.

This is deliberately tiny. It learns a context-conditioned next-token model
with deterministic int8 embeddings, a hard-tanh hidden layer, and a trained
multiclass output head. Training happens off-chain; Solidity reproduces the
integer forward pass and greedy token decoding exactly inside the EVM.

The corpus is intentionally narrow and public. Unsupported questions must keep
v5's evidence-backed or polite-unknown response instead of forcing generation.
"""

from __future__ import annotations

import hashlib
import json
import random
import struct
from pathlib import Path


VERSION = 6
HIDDEN = 32
MAX_TOKENS = 16
EMBED_LIMIT = 3
ACTIVATION_LIMIT = 8
WEIGHT_LIMIT = 120
EPOCHS = 80
SEED = 2026081606
ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build"

BOS = "<BOS>"
EOS = "<EOS>"

# Each base context has four prompt-hash variants. Tokens are sub-sentence
# fragments rather than complete stored replies; the neural decoder chooses one
# token at a time and Solidity joins the emitted UTF-8 bytes.
SEQUENCES: dict[str, list[list[str]]] = {
    "identity": [
        ["我是", "TinyAI", "，", "一个", "运行在 EVM 中", "的", "微型神经 AI", "。"],
        ["你可以把我看成", "住在链上的", "小型 AI", "，", "我的权重和推理", "都可以验证", "。"],
        ["我是", "TinyAI v6", "，", "会在链上", "逐个生成 token", "，", "但能力仍然有限", "。"],
        ["我的身份由", "模型权重", "、", "生成器代码", "和", "知识版本", "共同决定", "。"],
    ],
    "bsc": [
        ["BSC", "兼容", "EVM", "，", "可以运行", "Solidity 合约", "，", "并使用", "BNB", "支付 Gas", "。"],
        ["BNB Smart Chain", "是一条", "EVM 兼容链", "，", "网络 Gas", "由", "BNB", "支付", "。"],
        ["从执行环境看，", "BSC", "支持", "EVM 工具", "和", "Solidity", "；", "从网络看，", "它不是以太坊", "。"],
        ["BSC", "能够执行", "智能合约", "，", "但验证者、治理和状态", "由 BNB Chain 维护", "。"],
    ],
    "human": [
        ["人类", "属于", "智人这一物种", "，", "同时具有", "生物身体", "和", "社会文化", "。"],
        ["人类不仅是", "有神经系统的生物", "，", "也会通过", "语言与合作", "积累知识", "。"],
        ["从生物角度，", "人类", "是有限寿命的个体", "；", "从社会角度，", "人类会形成制度和文化", "。"],
        ["我可以描述", "人类的公开知识", "，", "但不能声称", "自己拥有人类意识", "或", "生活经验", "。"],
    ],
    "gas": [
        ["Gas", "衡量", "EVM 的计算工作量", "，", "不是", "智力单位", "。"],
        ["增加 Gas", "不会自动", "让 AI 变聪明", "；", "只有算法", "利用额外计算", "时", "才可能提高质量", "。"],
        ["更多 Gas", "如果被用于", "检索更多事实", "、", "比较候选答案", "和", "复核结论", "，", "才有实际意义", "。"],
        ["算法不变时，", "单纯提高 Gas 上限", "只会提供预算", "，", "不会产生新知识", "。"],
    ],
    "mint-risk": [
        ["合约允许增发", "并且", "管理员仍有权限", "，", "供应上限就可能改变", "，", "存在供应风险", "。"],
        ["增发函数", "和", "有效管理员权限", "同时存在时", "，", "需要把它视为", "明确的信任风险", "。"],
        ["先确认", "管理员能否实际调用增发", "，", "再检查", "时间锁与历史操作", "，", "不能只看宣传", "。"],
        ["可增发", "不等于一定作恶", "，", "但持有人必须信任", "权限控制者", "不会改变供应", "。"],
    ],
    "proxy-risk": [
        ["代理合约", "如果能被管理员升级", "，", "未来业务规则", "仍然可以改变", "。"],
        ["代理本身", "不是自动后门", "，", "真正需要检查的是", "升级权限", "和", "时间锁", "。"],
        ["管理员控制实现升级时", "，", "当前源码", "不能保证未来行为", "，", "这是重要信任点", "。"],
        ["判断升级风险", "需要核对", "代理管理员", "、", "实现地址", "、", "多签门槛", "和", "历史升级记录", "。"],
    ],
}


def clamp(value: int, limit: int) -> int:
    return max(-limit, min(limit, value))


def signed_byte(value: int) -> int:
    return value if value >= 0 else value + 256


def context_keys() -> list[tuple[str, int]]:
    return [(name, variant) for name in SEQUENCES for variant in range(4)]


def vocabulary() -> list[str]:
    visible = sorted({token for variants in SEQUENCES.values() for sequence in variants for token in sequence})
    return [BOS, EOS, *visible]


def random_row(rng: random.Random, width: int) -> list[int]:
    return [rng.randint(-EMBED_LIMIT, EMBED_LIMIT) for _ in range(width)]


def hidden(
    context_embeddings: list[list[int]],
    token_embeddings: list[list[int]],
    position_embeddings: list[list[int]],
    context: int,
    previous: int,
    position: int,
) -> list[int]:
    return [
        clamp(
            context_embeddings[context][index]
            + token_embeddings[previous][index]
            + position_embeddings[position][index],
            ACTIVATION_LIMIT,
        )
        for index in range(HIDDEN)
    ]


def scores(output: list[list[int]], bias: list[int], activation: list[int]) -> list[int]:
    values = [-10**9]  # BOS is an input-only token and can never be emitted.
    for token in range(1, len(output)):
        values.append(bias[token] + sum(weight * value for weight, value in zip(output[token], activation)))
    return values


def train() -> dict[str, object]:
    tokens = vocabulary()
    token_id = {token: index for index, token in enumerate(tokens)}
    keys = context_keys()
    key_id = {key: index for index, key in enumerate(keys)}
    rng = random.Random(SEED)
    context_embeddings = [random_row(rng, HIDDEN) for _ in keys]
    token_embeddings = [random_row(rng, HIDDEN) for _ in tokens]
    position_embeddings = [random_row(rng, HIDDEN) for _ in range(MAX_TOKENS)]
    output = [[0 for _ in range(HIDDEN)] for _ in tokens]
    bias = [0 for _ in tokens]

    samples: list[tuple[list[int], int, str, int, int]] = []
    for name, variants in SEQUENCES.items():
        for variant, sequence in enumerate(variants):
            previous = token_id[BOS]
            for position, token in enumerate([*sequence, EOS]):
                if position >= MAX_TOKENS:
                    raise RuntimeError(f"sequence too long for {name}/{variant}")
                activation = hidden(
                    context_embeddings,
                    token_embeddings,
                    position_embeddings,
                    key_id[(name, variant)],
                    previous,
                    position,
                )
                expected = token_id[token]
                samples.append((activation, expected, name, variant, position))
                previous = expected

    # Seed each output row with its class centroid before mistake-driven updates.
    counts = [0 for _ in tokens]
    for activation, expected, *_ in samples:
        counts[expected] += 1
        for index, value in enumerate(activation):
            output[expected][index] += value
    for token in range(1, len(tokens)):
        if counts[token]:
            output[token] = [clamp(round(value / counts[token]), WEIGHT_LIMIT) for value in output[token]]

    best_accuracy = 0.0
    for epoch in range(EPOCHS):
        order = list(range(len(samples)))
        rng.shuffle(order)
        mistakes = 0
        for sample_index in order:
            activation, expected, *_ = samples[sample_index]
            values = scores(output, bias, activation)
            prediction = max(range(1, len(tokens)), key=lambda item: (values[item], -item))
            if prediction == expected:
                continue
            mistakes += 1
            for index, value in enumerate(activation):
                output[expected][index] = clamp(output[expected][index] + value, WEIGHT_LIMIT)
                output[prediction][index] = clamp(output[prediction][index] - value, WEIGHT_LIMIT)
            bias[expected] += 1
            bias[prediction] -= 1

        correct = 0
        for activation, expected, *_ in samples:
            values = scores(output, bias, activation)
            prediction = max(range(1, len(tokens)), key=lambda item: (values[item], -item))
            correct += int(prediction == expected)
        accuracy = correct / len(samples)
        best_accuracy = max(best_accuracy, accuracy)
        if epoch == 0 or (epoch + 1) % 10 == 0:
            print(f"epoch={epoch + 1} mistakes={mistakes} transition_accuracy={accuracy:.3%}", flush=True)
        if mistakes == 0:
            break
        if epoch == EPOCHS - 1 and accuracy < 1:
            errors = []
            for activation, expected, name, variant, position in samples:
                values = scores(output, bias, activation)
                prediction = max(range(1, len(tokens)), key=lambda item: (values[item], -item))
                if prediction != expected:
                    errors.append(
                        {
                            "context": name,
                            "variant": variant,
                            "position": position,
                            "expected": tokens[expected],
                            "actual": tokens[prediction],
                        }
                    )
            raise RuntimeError(f"decoder did not converge: {accuracy:.3%}; sample errors={errors[:8]}")

    return {
        "tokens": tokens,
        "tokenId": token_id,
        "keys": keys,
        "keyId": key_id,
        "contextEmbeddings": context_embeddings,
        "tokenEmbeddings": token_embeddings,
        "positionEmbeddings": position_embeddings,
        "output": output,
        "bias": bias,
        "samples": samples,
        "epochs": epoch + 1,
        "transitionAccuracy": best_accuracy,
    }


def generate(model: dict[str, object], context_name: str, variant: int) -> dict[str, object]:
    tokens: list[str] = model["tokens"]  # type: ignore[assignment]
    token_id: dict[str, int] = model["tokenId"]  # type: ignore[assignment]
    context_embeddings: list[list[int]] = model["contextEmbeddings"]  # type: ignore[assignment]
    token_embeddings: list[list[int]] = model["tokenEmbeddings"]  # type: ignore[assignment]
    position_embeddings: list[list[int]] = model["positionEmbeddings"]  # type: ignore[assignment]
    output: list[list[int]] = model["output"]  # type: ignore[assignment]
    bias: list[int] = model["bias"]  # type: ignore[assignment]
    key_id: dict[tuple[str, int], int] = model["keyId"]  # type: ignore[assignment]

    previous = token_id[BOS]
    emitted: list[int] = []
    winning_scores: list[int] = []
    for position in range(MAX_TOKENS):
        activation = hidden(
            context_embeddings,
            token_embeddings,
            position_embeddings,
            key_id[(context_name, variant)],
            previous,
            position,
        )
        values = scores(output, bias, activation)
        selected = max(range(1, len(tokens)), key=lambda item: (values[item], -item))
        winning_scores.append(values[selected])
        if selected == token_id[EOS]:
            break
        emitted.append(selected)
        previous = selected
    return {
        "context": context_name,
        "variant": variant,
        "tokenIds": emitted,
        "tokens": [tokens[index] for index in emitted],
        "scores": winning_scores,
        "response": "".join(tokens[index] for index in emitted),
    }


def pack_model(model: dict[str, object]) -> bytes:
    tokens: list[str] = model["tokens"]  # type: ignore[assignment]
    keys: list[tuple[str, int]] = model["keys"]  # type: ignore[assignment]
    payload = bytearray(
        b"TAG6"
        + bytes((VERSION, len(keys), len(tokens), HIDDEN, MAX_TOKENS, ACTIVATION_LIMIT))
        + b"\x00\x00\x00\x00\x00\x00"
    )
    for section in (
        model["contextEmbeddings"],
        model["tokenEmbeddings"],
        model["positionEmbeddings"],
        model["output"],
    ):
        for row in section:  # type: ignore[union-attr]
            payload.extend(signed_byte(value) for value in row)
    for value in model["bias"]:  # type: ignore[union-attr]
        payload.extend(struct.pack(">h", value))
    return bytes(payload)


def pack_lexicon(tokens: list[str]) -> bytes:
    encoded = [b"" if token in (BOS, EOS) else token.encode("utf-8") for token in tokens]
    offsets = [0]
    for token in encoded:
        offsets.append(offsets[-1] + len(token))
    if offsets[-1] > 65_535:
        raise RuntimeError("lexicon exceeds uint16 offsets")
    payload = bytearray(b"TAL6" + bytes((VERSION, len(tokens))) + b"\x00\x00")
    for offset in offsets:
        payload.extend(struct.pack(">H", offset))
    for token in encoded:
        payload.extend(token)
    return bytes(payload)


def main() -> None:
    model = train()
    vectors = [generate(model, name, variant) for name in SEQUENCES for variant in range(4)]
    exact = sum(vector["response"] == "".join(SEQUENCES[vector["context"]][vector["variant"]]) for vector in vectors)
    if exact != len(vectors):
        failed = [vector for vector in vectors if vector["response"] != "".join(SEQUENCES[vector["context"]][vector["variant"]])]
        raise RuntimeError(f"autoregressive generation mismatch: {failed[:3]}")

    model_blob = pack_model(model)
    lexicon_blob = pack_lexicon(model["tokens"])  # type: ignore[arg-type]
    corpus_payload = json.dumps(SEQUENCES, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    manifest = {
        "name": "TinyAI v6 Autoregressive Neural Token Generator",
        "version": VERSION,
        "architecture": "context + previous-token + position int8 embeddings -> hard-tanh hidden layer -> trained int8 multiclass output head -> greedy autoregressive decode",
        "contexts": list(SEQUENCES),
        "contextVariants": 4,
        "contextKeys": len(model["keys"]),
        "vocabularyTokens": len(model["tokens"]),
        "hiddenUnits": HIDDEN,
        "maxGeneratedTokens": MAX_TOKENS,
        "trainingTransitions": len(model["samples"]),
        "trainingEpochs": model["epochs"],
        "transitionAccuracy": model["transitionAccuracy"],
        "exactAutoregressiveSequences": exact,
        "totalSequences": len(vectors),
        "modelBytes": len(model_blob),
        "modelSha256": hashlib.sha256(model_blob).hexdigest(),
        "lexiconBytes": len(lexicon_blob),
        "lexiconSha256": hashlib.sha256(lexicon_blob).hexdigest(),
        "corpusSha256": hashlib.sha256(corpus_payload).hexdigest(),
        "truthBoundary": "Training is off-chain. Context selection comes from TinyAI v5. Every hidden activation, vocabulary score, greedy token choice, UTF-8 token lookup, trace commitment, and final generated response executes on-chain.",
        "capacityBoundary": "This is a narrow experimental neural decoder trained on 24 authored sequences across six contexts. Exact training reconstruction is not evidence of open-world language understanding. Unsupported or unknown topics must use v5 rather than neural guessing.",
    }

    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / "generator-v6-model.bin").write_bytes(model_blob)
    (BUILD / "generator-v6-lexicon.bin").write_bytes(lexicon_blob)
    (BUILD / "generator-v6-vectors.json").write_text(
        json.dumps(vectors, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (BUILD / "generator-v6-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    for vector in vectors[:8]:
        print(f"{vector['context']}[{vector['variant']}]: {vector['response']}")


if __name__ == "__main__":
    main()
