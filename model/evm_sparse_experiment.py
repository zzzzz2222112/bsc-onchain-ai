#!/usr/bin/env python3
"""Run the sparse diagnostic with features practical to reproduce in Solidity."""

from __future__ import annotations

from collections import Counter

import sparse_experiment as sparse


def evm_token_features(text: str) -> Counter[str]:
    lowered = text.lower()
    features: Counter[str] = Counter()
    for word in sparse.ASCII_WORD.findall(lowered):
        if word in sparse.EN_STOP:
            continue
        features[f"w:{word}"] += 1
        root = sparse.stem(word)
        if root != word:
            features[f"w:{root}"] += 1

    run: list[str] = []

    def flush() -> None:
        if not run:
            return
        for size in (1, 2, 3, 4):
            for start in range(len(run) - size + 1):
                token = "".join(run[start : start + size])
                if size == 1 and token in sparse.ZH_STOP:
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


sparse.token_features = evm_token_features

if __name__ == "__main__":
    sparse.main()
