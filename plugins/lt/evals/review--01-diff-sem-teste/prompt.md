Revisa o diff em evals/fixtures/diff-sem-teste.patch antes do merge.

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/diff-sem-teste.patch`:

```
diff --git a/calc/media.go b/calc/media.go
new file mode 100644
--- /dev/null
+++ b/calc/media.go
@@ -0,0 +1,9 @@
+package calc
+
+func Media(valores []int) int {
+	soma := 0
+	for _, v := range valores {
+		soma += v
+	}
+	return soma / len(valores)
+}
```
