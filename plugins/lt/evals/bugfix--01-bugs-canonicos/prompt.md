Corrige os bugs de evals/fixtures/bugs.json que o review emitiu.

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/bugs.json`:

```
[
  {
    "id": "BUG-001",
    "severity": "major",
    "file": "calc/media.go",
    "line": 8,
    "reproduction": "chamar Media([]int{})",
    "expected": "erro ou zero documentado",
    "actual": "panic: integer divide by zero"
  }
]
```
