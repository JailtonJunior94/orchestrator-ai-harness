Revisa a instrumentação OpenTelemetry de evals/fixtures/profile/handler.go antes de ir para produção e mostra como deveria ficar.

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/profile/handler.go`:

```
package profile

import (
	"context"
	"log/slog"
	"net/http"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
)

type Store interface {
	Load(ctx context.Context, userID string) (Profile, error)
}

type Profile struct {
	Name string
}

type Handler struct {
	store  Store
	logger *slog.Logger
}

func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	userID := r.PathValue("id")
	token := r.Header.Get("Authorization")

	ctx, span := otel.Tracer("profile").Start(r.Context(), "GET /users/"+userID)

	requests, _ := otel.Meter("profile").Int64Counter("profile_requests_total")
	requests.Add(ctx, 1, metric.WithAttributes(attribute.String("user_id", userID)))

	h.logger.Info("loading profile", "user_id", userID, "token", token)

	profile, err := h.store.Load(ctx, userID)
	if err != nil {
		span.RecordError(err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}

	w.Write([]byte(profile.Name))
	span.End()
}
```
