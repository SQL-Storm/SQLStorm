-- {"query": "4583.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1174}
WITH
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate AS QuestionCreationDate,
      p.AnswerCount,
      p.Score AS QuestionScore,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      ROW_NUMBER() OVER (
        ORDER BY
          p.CreationDate DESC
      ) AS rn
    FROM Posts p
    JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
  ),
  TopAnswers AS (
    SELECT
      p.ParentId AS QuestionId,
      COUNT(p.Id) AS AnswerCount,
      SUM(p.Score) AS TotalAnswerScore,
      MAX(p.Score) AS MaxAnswerScore,
      AVG(p.Score) AS AvgAnswerScore,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.ParentId
        ORDER BY
          SUM(p.Score) DESC
      ) AS answer_rn
    FROM Posts p
    WHERE
      p.PostTypeId = 2
    GROUP BY
      p.ParentId
  ),
  QuestionEngagement AS (
    SELECT
      q.Id AS QuestionId,
      COUNT(DISTINCT c.Id) AS CommentCount,
      COUNT(DISTINCT v.Id) AS VoteCount
    FROM Posts q
    LEFT JOIN Comments c
      ON q.Id = c.PostId
    LEFT JOIN Votes v
      ON q.Id = v.PostId
    WHERE
      q.PostTypeId = 1
    GROUP BY
      q.Id
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      COUNT(DISTINCT ph.PostId) AS PostEdits,
      MAX(ph.CreationDate) AS LastEditDate
    FROM Users u
    JOIN PostHistory ph
      ON u.Id = ph.UserId
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
      u.Id
  ),
  PostData AS (
    SELECT
      rq.QuestionId,
      rq.Title,
      rq.QuestionCreationDate,
      rq.OwnerDisplayName,
      rq.OwnerReputation,
      ta.AnswerCount AS ApprovedAnswerCount,
      ta.TotalAnswerScore,
      ta.MaxAnswerScore,
      ta.AvgAnswerScore,
      qe.CommentCount AS QuestionCommentCount,
      qe.VoteCount AS QuestionVoteCount,
      ua.PostEdits AS OwnerPostEdits,
      ua.LastEditDate AS OwnerLastEditDate,
      CASE
        WHEN rq.QuestionScore > 0 THEN 'Positive'
        WHEN rq.QuestionScore < 0 THEN 'Negative'
        ELSE 'Neutral'
      END AS ScoreCategory,
      DENSE_RANK() OVER (
        ORDER BY
          rq.QuestionScore DESC
      ) AS RankByScore,
      NTILE(5) OVER (
        ORDER BY
          rq.AnswerCount DESC
      ) AS AnswerCountQuintile,
      rq.QuestionScore
    FROM RecentQuestions rq
    LEFT JOIN TopAnswers ta
      ON rq.QuestionId = ta.QuestionId AND ta.answer_rn = 1
    LEFT JOIN QuestionEngagement qe
      ON rq.QuestionId = qe.QuestionId
    LEFT JOIN UserActivity ua
      ON rq.OwnerUserId = ua.UserId
    WHERE
      rq.rn <= 100
  )
SELECT
  pd.QuestionId,
  pd.Title,
  pd.QuestionCreationDate,
  pd.OwnerDisplayName,
  pd.OwnerReputation,
  pd.ApprovedAnswerCount,
  pd.TotalAnswerScore,
  pd.MaxAnswerScore,
  pd.AvgAnswerScore,
  pd.QuestionCommentCount,
  pd.QuestionVoteCount,
  pd.OwnerPostEdits,
  pd.OwnerLastEditDate,
  pd.ScoreCategory,
  pd.RankByScore,
  pd.AnswerCountQuintile,
  CASE
    WHEN pd.OwnerReputation > 10000 THEN 'High Rep'
    WHEN pd.OwnerReputation BETWEEN 1000 AND 10000 THEN 'Medium Rep'
    ELSE 'Low Rep'
  END AS ReputationLevel,
  COALESCE(pd.OwnerLastEditDate, pd.QuestionCreationDate) AS EffectiveLastActivity,
  CASE
    WHEN pd.ApprovedAnswerCount IS NULL THEN 'No Answers'
    WHEN pd.ApprovedAnswerCount = 0 THEN 'Zero Answers'
    ELSE CAST(pd.ApprovedAnswerCount AS VARCHAR)
  END AS AnswerStatus,
  ROW_NUMBER() OVER (ORDER BY pd.QuestionScore DESC, pd.QuestionCreationDate ASC) AS GlobalRank
FROM PostData pd
WHERE
  pd.OwnerReputation > 0
ORDER BY
  pd.QuestionScore DESC
LIMIT 50;