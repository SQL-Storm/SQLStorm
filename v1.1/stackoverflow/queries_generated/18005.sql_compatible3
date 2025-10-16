WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.Score,
      p.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts p
    WHERE
      p.PostTypeId = 2 AND p.ParentId IS NOT NULL
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      COUNT(DISTINCT a.Id) AS AnswerCount,
      SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) AS PositiveAnswerCount,
      AVG(a.Score) AS AvgAnswerScore,
      (
        SELECT
          COUNT(*)
        FROM Votes v
        WHERE
          v.UserId = u.Id AND v.VoteTypeId = 2
      ) AS TotalUpvotesGiven,
      (
        SELECT
          COUNT(*)
        FROM Votes v
        WHERE
          v.UserId = u.Id AND v.VoteTypeId = 3
      ) AS TotalDownvotesGiven,
      MAX(p.CreationDate) AS LastQuestionDate,
      MAX(a.CreationDate) AS LastAnswerDate
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Posts a
      ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
    HAVING
      COUNT(DISTINCT p.Id) > 5 OR COUNT(DISTINCT a.Id) > 10
  ),
  TagPopularity AS (
    SELECT
      SUBSTRING(t.TagName FROM 2 FOR (LENGTH(t.TagName) - 2)) AS TagName,
      COUNT(p.Id) AS QuestionCount
    FROM Tags t
    JOIN Posts p
      ON p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1
    GROUP BY
      t.TagName
    ORDER BY
      QuestionCount DESC
    LIMIT 20
  )
SELECT
  q.Id AS QuestionId,
  q.Title AS QuestionTitle,
  q.OwnerUserId AS QuestionOwnerUserId,
  q.CreationDate AS QuestionCreationDate,
  q.Score AS QuestionScore,
  q.ViewCount AS QuestionViewCount,
  q.AnswerCount AS QuestionAnswerCount,
  q.FavoriteCount AS QuestionFavoriteCount,
  q.ClosedDate,
  COALESCE(best_answer.PostId, -1) AS BestAnswerId,
  COALESCE(best_answer.OwnerUserId, -1) AS BestAnswerOwnerUserId,
  COALESCE(best_answer.Score, 0) AS BestAnswerScore,
  ue.DisplayName AS QuestionOwnerDisplayName,
  ue.Reputation AS QuestionOwnerReputation,
  ue.AvgAnswerScore AS AvgScoreOfUserAnswers,
  tp.TagName AS TopRelatedTag,
  tp.QuestionCount AS TopRelatedTagQuestionCount,
  CASE
    WHEN q.CreationDate > (cast('2024-10-01' as date) - INTERVAL '7' DAY) THEN 'Recent'
    WHEN q.Score > 100 THEN 'HighScore'
    WHEN q.ViewCount > 10000 THEN 'Popular'
    ELSE 'Standard'
  END AS QuestionCategory,
  LENGTH(q.Body) AS QuestionBodyLength,
  (
    SELECT
      COUNT(*)
    FROM Comments c
    WHERE
      c.PostId = q.Id AND c.Score > 5
  ) AS HighScoreCommentCount
FROM Posts q
LEFT JOIN RankedAnswers best_answer
  ON q.Id = best_answer.QuestionId AND best_answer.rn = 1
LEFT JOIN UserEngagement ue
  ON q.OwnerUserId = ue.UserId
LEFT JOIN Posts q_tags
  ON q.Id = q_tags.Id AND q_tags.PostTypeId = 1
LEFT JOIN TagPopularity tp
  ON q_tags.Tags LIKE '%' || tp.TagName || '%'
WHERE
  q.PostTypeId = 1 AND q.AcceptedAnswerId IS NOT NULL AND q.Score > 0 AND q.OwnerUserId IS NOT NULL AND ue.Reputation > 1000
UNION ALL
SELECT
  NULL AS QuestionId,
  'Total Questions with Accepted Answers' AS QuestionTitle,
  NULL AS QuestionOwnerUserId,
  NULL AS QuestionCreationDate,
  NULL AS QuestionScore,
  NULL AS QuestionViewCount,
  COUNT(DISTINCT q_union.Id) AS QuestionAnswerCount,
  NULL AS QuestionFavoriteCount,
  NULL AS ClosedDate,
  NULL AS BestAnswerId,
  NULL AS BestAnswerOwnerUserId,
  NULL AS BestAnswerScore,
  NULL AS QuestionOwnerDisplayName,
  NULL AS QuestionOwnerReputation,
  NULL AS AvgScoreOfUserAnswers,
  NULL AS TopRelatedTag,
  NULL AS TopRelatedTagQuestionCount,
  NULL AS QuestionCategory,
  NULL AS QuestionBodyLength,
  NULL AS HighScoreCommentCount
FROM Posts q_union
WHERE
  q_union.PostTypeId = 1 AND q_union.AcceptedAnswerId IS NOT NULL AND q_union.Score > 0 AND q_union.OwnerUserId IS NOT NULL;