-- {"query": "4018.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1091} 
WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.CreationDate AS AnswerCreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn,
      CASE
        WHEN p.OwnerUserId = q.OwnerUserId THEN 1
        ELSE 0
      END AS IsOwnerAnswer,
      p.Score,
      q.CreationDate AS QuestionCreationDate,
      q.ViewCount AS QuestionViewCount,
      q.FavoriteCount AS QuestionFavoriteCount
    FROM Posts AS p
    JOIN Posts AS q
      ON p.ParentId = q.Id
    WHERE
      p.PostTypeId = 2
      AND q.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
      AND q.OwnerUserId IS NOT NULL
  ),
  AnswerMetrics AS (
    SELECT
      ra.QuestionId,
      AVG(ra.Score) AS AvgAnswerScore,
      COUNT(ra.PostId) AS TotalAnswers,
      SUM(ra.IsOwnerAnswer) AS OwnerAnswerCount,
      MAX(ra.AnswerCreationDate) AS LatestAnswerDate
    FROM RankedAnswers AS ra
    GROUP BY
      ra.QuestionId
  )
SELECT
  q.Id AS QuestionId,
  q.Title AS QuestionTitle,
  q.CreationDate AS QuestionCreationDate,
  q.OwnerUserId AS QuestionOwnerUserId,
  u.DisplayName AS QuestionOwnerDisplayName,
  q.Score AS QuestionScore,
  q.ViewCount AS QuestionViewCount,
  q.FavoriteCount AS QuestionFavoriteCount,
  COALESCE(pt.Name, 'Unknown') AS QuestionPostType,
  am.TotalAnswers,
  am.AvgAnswerScore,
  am.OwnerAnswerCount,
  CASE
    WHEN am.OwnerAnswerCount > 0 THEN CAST(am.OwnerAnswerCount AS REAL) / am.TotalAnswers
    ELSE 0.0
  END AS OwnerAnswerRatio,
  CASE
    WHEN am.LatestAnswerDate > q.CreationDate THEN am.LatestAnswerDate
    ELSE q.CreationDate
  END AS LastActivityDate,
  LAG(q.Score, 1, 0) OVER (ORDER BY q.CreationDate DESC) AS PreviousQuestionScore,
  LEAD(q.ViewCount, 1, 0) OVER (ORDER BY q.ViewCount ASC) AS NextQuestionViewCount,
  CASE
    WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN q.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Open'
  END AS QuestionStatus,
  CASE
    WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Answered'
    ELSE 'Unanswered'
  END AS AnswerStatus,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = q.Id AND pl.LinkTypeId = 3
  ) AS DuplicateLinks,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = q.Id AND c.Score < 0
  ) AS NegativeScoreComments,
  CONCAT(u.DisplayName, ' (', u.Reputation, ')') AS OwnerInfo
FROM Posts AS q
LEFT JOIN Users AS u
  ON q.OwnerUserId = u.Id
LEFT JOIN PostTypes AS pt
  ON q.PostTypeId = pt.Id
LEFT JOIN AnswerMetrics AS am
  ON q.Id = am.QuestionId
WHERE
  q.PostTypeId = 1
  AND q.CreationDate > '2023-01-01'
  AND u.Views > 1000
  AND am.TotalAnswers BETWEEN 1 AND 10
  AND (
    q.Title LIKE '%SQL%' OR q.Tags LIKE '%<sql>%'
  )
  AND q.OwnerUserId NOT IN (
    SELECT
      UserId
    FROM Votes
    WHERE
      VoteTypeId = 3 AND CreationDate > '2023-06-01'
  )
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
  NULL,
  NULL,
  NULL
FROM Posts AS q
WHERE
  q.PostTypeId = 1
  AND q.CreationDate > '2023-01-01'
  AND q.OwnerUserId IS NULL;