-- {"query": "4486.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 766} 

WITH
  TopQuestions AS (
    SELECT
      Id,
      Title,
      OwnerUserId,
      CASE
        WHEN Score > 1000 THEN 'Legendary'
        WHEN Score > 500 THEN 'Epic'
        WHEN Score > 100 THEN 'Heroic'
        ELSE 'Notable'
      END AS BadgeTitle,
      ROW_NUMBER() OVER (ORDER BY Score DESC, ViewCount DESC) AS rn
    FROM Posts
    WHERE
      PostTypeId = 1 AND ClosedDate IS NULL AND CreationDate > '2023-01-01'
  ),
  UserQuestionStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS QuestionCount,
      AVG(p.Score) AS AvgQuestionScore,
      SUM(p.AnswerCount) AS TotalAnswersReceived
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.OwnerUserId
  ),
  MostActiveUsers AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COALESCE(us.QuestionCount, 0) AS QuestionsAnswered,
      COALESCE(us.AvgQuestionScore, 0) AS AverageScore,
      COALESCE(us.TotalAnswersReceived, 0) AS AnswersProvided
    FROM Users AS u
    LEFT JOIN UserQuestionStats AS us
      ON u.Id = us.OwnerUserId
    WHERE
      u.Id IN (
        SELECT DISTINCT
          OwnerUserId
        FROM Posts
        WHERE
          PostTypeId = 1
      )
      AND u.Id NOT IN (
        SELECT
          UserId
        FROM Comments
        WHERE
          Text LIKE '%spam%'
      )
  )
SELECT
  tq.rn AS Rank,
  tq.Title AS QuestionTitle,
  tq.BadgeTitle AS ReputationTier,
  mu.DisplayName AS TopContributor,
  mu.Reputation AS ContributorReputation,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM PostLinks AS pl
      WHERE
        pl.PostId = tq.Id AND pl.LinkTypeId = 3
    ) THEN 'Is Duplicate'
    ELSE 'Not a Duplicate'
  END AS DuplicateStatus,
  SUM(COALESCE(c.Score, 0)) OVER (PARTITION BY tq.OwnerUserId ORDER BY tq.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeCommentScore
FROM TopQuestions AS tq
LEFT JOIN MostActiveUsers AS mu
  ON tq.OwnerUserId = mu.UserId
LEFT JOIN Comments AS c
  ON tq.Id = c.PostId
WHERE
  tq.rn BETWEEN 1 AND 100
  AND mu.ContributorReputation > 10000
  AND LEFT(mu.DisplayName, 3) <> 'Mod'
GROUP BY
  tq.rn,
  tq.Title,
  tq.BadgeTitle,
  mu.DisplayName,
  mu.Reputation,
  tq.OwnerUserId,
  tq.CreationDate
HAVING
  COUNT(c.Id) > 5 OR SUM(COALESCE(c.Score, 0)) > 50
ORDER BY
  tq.rn;
