#!/usr/bin/env python3
"""Print selected reference feature IDs and predictions for parity debugging."""

import train_sparse


for token in ("z1:你", "z1:好", "z2:你好", "z2:是谁", "w:wallet", "w:transactions", "w:transaction"):
    print(token, hex(train_sparse.feature_id(token)))

model = train_sparse.train_model()
for prompt in ("你好，你是谁", "my transaction is stuck and I cannot afford the gas"):
    print(prompt)
    print(train_sparse.token_features(prompt))
    print(train_sparse.predict(prompt, model))
