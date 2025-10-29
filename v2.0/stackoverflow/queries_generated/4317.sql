-- {"query": "4317.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1253} 

WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.Score,
      p.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS Rank,
      CASE WHEN p.OwnerUserId = q.OwnerUserId THEN 1 ELSE 0 END AS IsOwnedByQuestionAuthor,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS PreviousScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS NextScore
    FROM Posts AS p
    JOIN Posts AS q
      ON p.ParentId = q.Id
    WHERE
      p.PostTypeId = 2 AND q.PostTypeId = 1
  ),
  UsersWithHighReputation AS (
    SELECT
      Id
    FROM Users
    WHERE
      Reputation > 50000
  ),
  QuestionsWithManyAnswers AS (
    SELECT
      Id
    FROM Posts
    WHERE
      PostTypeId = 1 AND AnswerCount > 10
  ),
  RecentPostHistory AS (
    SELECT
      PostId,
      PostHistoryTypeId,
      UserId,
      CreationDate
    FROM PostHistory
    WHERE
      CreationDate > DATE('now', '-30 days')
  )
SELECT
  q.Id AS QuestionId,
  q.Title AS QuestionTitle,
  q.OwnerUserId AS QuestionOwnerUserId,
  q.CreationDate AS QuestionCreationDate,
  q.Score AS QuestionScore,
  q.ViewCount AS QuestionViewCount,
  q.FavoriteCount AS QuestionFavoriteCount,
  ra.OwnerUserId AS BestAnswerOwnerUserId,
  ra.Score AS BestAnswerScore,
  ra.CreationDate AS BestAnswerCreationDate,
  u.DisplayName AS QuestionOwnerDisplayName,
  u.Reputation AS QuestionOwnerReputation,
  COUNT(DISTINCT c.Id) AS CommentCountOnQuestion,
  SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
  AVG(ra.Score) OVER (PARTITION BY q.Id) AS AvgAnswerScoreForQuestion,
  CASE
    WHEN q.OwnerUserId IN (
      SELECT
        Id
      FROM UsersWithHighReputation
    ) THEN 'High Reputation Owner'
    ELSE 'Standard Reputation Owner'
  END AS OwnerReputationCategory,
  CASE
    WHEN ra.IsOwnedByQuestionAuthor = 1 THEN 'Owned by Question Author'
    ELSE 'Owned by Other'
  END AS AnswerOwnershipStatus,
  CASE
    WHEN ra.Score > 0 AND ra.PreviousScore < ra.Score AND ra.NextScore <= ra.Score THEN 'Top Answer with Improvement'
    WHEN ra.Score > 0 AND ra.PreviousScore >= ra.Score AND ra.NextScore < ra.Score THEN 'Top Answer Holding Position'
    ELSE 'Other Answer Scenario'
  END AS AnswerRankingScenario,
  CASE
    WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN q.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Open'
  END AS QuestionStatus,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = q.Id AND pl.LinkTypeId = 3
  ) AS DuplicateLinkCount,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM RecentPostHistory AS rph
      WHERE
        rph.PostId = q.Id AND rph.PostHistoryTypeId = 19
    ) THEN 'Protected'
    ELSE 'Not Protected'
  END AS IsProtected,
  COALESCE(u.Location, 'Unknown Location') AS UserLocation,
  u.WebsiteUrl,
  CASE
    WHEN INSTR(LOWER(u.DisplayName), 'bot') > 0 THEN 'Is Bot'
    WHEN u.DisplayName IS NULL THEN 'Anonymous'
    ELSE 'Human'
  END AS UserType
FROM Posts AS q
LEFT JOIN Users AS u
  ON q.OwnerUserId = u.Id
LEFT JOIN RankedAnswers AS ra
  ON q.Id = ra.QuestionId AND ra.Rank = 1
LEFT JOIN Comments AS c
  ON q.Id = c.PostId
LEFT JOIN RecentPostHistory AS ph
  ON q.Id = ph.PostId
WHERE
  q.PostTypeId = 1
  AND q.Id IN (
    SELECT
      Id
    FROM QuestionsWithManyAnswers
  )
GROUP BY
  q.Id,
  q.Title,
  q.OwnerUserId,
  q.CreationDate,
  q.Score,
  q.ViewCount,
  q.FavoriteCount,
  ra.OwnerUserId,
  ra.Score,
  ra.CreationDate,
  u.DisplayName,
  u.Reputation,
  u.Location,
  u.WebsiteUrl,
  q.ClosedDate,
  q.CommunityOwnedDate
HAVING
  COUNT(DISTINCT c.Id) > 5 -- Only consider questions with more than 5 comments
ORDER BY
  q.CreationDate DESC
LIMIT 100;
