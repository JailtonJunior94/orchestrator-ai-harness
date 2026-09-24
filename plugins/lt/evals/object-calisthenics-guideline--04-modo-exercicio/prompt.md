Estou fazendo o kata de Object Calisthenics (1000 linhas, 100% das regras). Revisa evals/fixtures/kata/BowlingGame.java com rigor total.

O repositório não está disponível nesta sessão; o conteúdo atual dos arquivos citados vai abaixo.

`evals/fixtures/kata/BowlingGame.java`:

```
public class BowlingGame {
    private int[] rolls = new int[21];
    private int currentRoll;
    private String player;

    public BowlingGame(String player) {
        this.player = player;
    }

    public String getPlayer() {
        return player;
    }

    public void roll(int pins) {
        rolls[currentRoll++] = pins;
    }

    public int score() {
        int score = 0;
        int frameIndex = 0;
        for (int frame = 0; frame < 10; frame++) {
            if (rolls[frameIndex] == 10) {
                score += 10 + rolls[frameIndex + 1] + rolls[frameIndex + 2];
                frameIndex++;
            } else if (rolls[frameIndex] + rolls[frameIndex + 1] == 10) {
                score += 10 + rolls[frameIndex + 2];
                frameIndex += 2;
            } else {
                score += rolls[frameIndex] + rolls[frameIndex + 1];
                frameIndex += 2;
            }
        }
        return score;
    }
}
```
