O evals/fixtures/ops/rotate-logs.sh deveria apagar os logs com mais de 7 dias, mas quase nada é apagado. Corrige.

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/ops/rotate-logs.sh`:

```
#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${LOG_DIR:-/var/log/app}"

find "$LOG_DIR" -type f -name '*.log' -mtime 7 -delete
```
