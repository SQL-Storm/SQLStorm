-- {"query": "4152.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1053} 

WITH
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount AS QuestionViewCount,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      ROW_NUMBER() OVER (
        ORDER BY
          p.CreationDate DESC
      ) AS rn
    FROM Posts AS p
    JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= DATE('now', '-30 days')
  ),
  HighReputationAnswers AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.CreationDate AS AnswerCreationDate,
      p.Score AS AnswerScore,
      u.DisplayName AS AnswererDisplayName,
      u.Reputation AS AnswererReputation,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.ParentId
        ORDER BY
          p.Score DESC,
          p.CreationDate ASC
      ) AS answer_rank
    FROM Posts AS p
    JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 2
  ),
  QuestionAnswerSummary AS (
    SELECT
      rq.QuestionId,
      rq.Title,
      rq.QuestionCreationDate,
      rq.QuestionScore,
      rq.AnswerCount,
      rq.FavoriteCount,
      rq.QuestionViewCount,
      rq.OwnerDisplayName,
      rq.OwnerReputation,
      MAX(CASE WHEN ha.answer_rank = 1 THEN ha.AnswerScore ELSE 0 END) AS BestAnswerScore,
      COUNT(ha.AnswerId) AS TotalAnswers,
      AVG(ha.AnswerScore) AS AverageAnswerScore,
      SUM(ha.AnswererReputation) AS TotalAnswererReputation
    FROM RecentQuestions AS rq
    LEFT JOIN HighReputationAnswers AS ha
      ON rq.QuestionId = ha.QuestionId
    GROUP BY
      rq.QuestionId,
      rq.Title,
      rq.QuestionCreationDate,
      rq.QuestionScore,
      rq.AnswerCount,
      rq.FavoriteCount,
      rq.QuestionViewCount,
      rq.OwnerDisplayName,
      rq.OwnerReputation
  )
SELECT
  qas.QuestionId,
  qas.Title,
  qas.QuestionCreationDate,
  qas.QuestionScore,
  qas.AnswerCount,
  qas.FavoriteCount,
  qas.QuestionViewCount,
  qas.OwnerDisplayName,
  qas.OwnerReputation,
  qas.BestAnswerScore,
  qas.TotalAnswers,
  qas.AverageAnswerScore,
  qas.TotalAnswererReputation,
  (
    SELECT
      COUNT(*)
    FROM Votes AS v
    WHERE
      v.PostId = qas.QuestionId AND v.VoteTypeId = 2
  ) AS TotalUpVotes,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = qas.QuestionId
  ) AS TotalComments,
  CASE
    WHEN qas.FavoriteCount > 0 THEN 'Favorited'
    WHEN qas.QuestionScore > 10 THEN 'Popular'
    ELSE 'Standard'
  END AS QuestionStatus,
  COALESCE(
    (
      SELECT
        COUNT(*)
      FROM PostLinks AS pl
      WHERE
        pl.PostId = qas.QuestionId AND pl.LinkTypeId = 3
    ),
    0
  ) AS DuplicateLinks
FROM QuestionAnswerSummary AS qas
WHERE
  qas.rn <= 100
  AND qas.TotalAnswers > 0
  AND qas.OwnerReputation > 5000
UNION
SELECT
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL
FROM Users
WHERE
  NOT EXISTS (
    SELECT
      1
    FROM RecentQuestions
  )
ORDER BY
  QuestionScore DESC;
