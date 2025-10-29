-- {"query": "4888.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1592} 

WITH
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.ViewCount AS QuestionViewCount,
      p.FavoriteCount AS QuestionFavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate,
      STRING_AGG(t.TagName, ',') WITHIN GROUP (
        ORDER BY
          t.TagName
      ) AS Tags
    FROM Posts AS p
    LEFT JOIN Posts AS t_post
      ON p.Id = t_post.Id
    LEFT JOIN (
      SELECT
        CAST(SUBSTRING(value, 2, LEN(value) - 2) AS VARCHAR(35)) AS TagName,
        Id
      FROM Posts
      CROSS APPLY STRING_SPLIT(Tags, '><')
    ) AS t
      ON p.Id = t.Id
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.Id,
      p.Title,
      p.OwnerUserId,
      u.DisplayName,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.ViewCount,
      p.FavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate
  ),
  AnswerDetails AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS AnswerCreationDate,
      p.Score AS AnswerScore,
      p.ViewCount AS AnswerViewCount,
      p.CommentCount AS AnswerCommentCount,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS RankByScore
    FROM Posts AS p
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 2
  ),
  UserReputationChanges AS (
    SELECT
      ph.UserId,
      ph.PostId,
      ph.CreationDate,
      CASE
        WHEN ph.PostHistoryTypeId = 2 THEN 1 -- Initial Body
        WHEN ph.PostHistoryTypeId = 4 THEN 5 -- Edit Title
        WHEN ph.PostHistoryTypeId = 5 THEN 5 -- Edit Body
        WHEN ph.PostHistoryTypeId = 6 THEN 3 -- Edit Tags
        WHEN ph.PostHistoryTypeId = 10 THEN -10 -- Post Closed
        WHEN ph.PostHistoryTypeId = 11 THEN 5 -- Post Reopened
        WHEN ph.PostHistoryTypeId = 12 THEN -50 -- Post Deleted
        WHEN ph.PostHistoryTypeId = 13 THEN 10 -- Post Undeleted
        WHEN ph.PostHistoryTypeId = 14 THEN -10 -- Post Locked
        WHEN ph.PostHistoryTypeId = 15 THEN 5 -- Post Unlocked
        WHEN ph.PostHistoryTypeId = 19 THEN 10 -- Question Protected
        WHEN ph.PostHistoryTypeId = 20 THEN -5 -- Question Unprotected
        WHEN ph.PostHistoryTypeId = 24 THEN 2 -- Suggested Edit Applied
        ELSE 0
      END AS ReputationDelta
    FROM PostHistory AS ph
    WHERE
      ph.UserId IS NOT NULL
      AND ph.PostHistoryTypeId IN (2, 4, 5, 6, 10, 11, 12, 13, 14, 15, 19, 20, 24)
  ),
  UserTotalReputation AS (
    SELECT
      UserId,
      SUM(ReputationDelta) AS TotalReputationChange
    FROM UserReputationChanges
    GROUP BY
      UserId
  ),
  TopQuestions AS (
    SELECT
      qd.QuestionId,
      qd.QuestionTitle,
      qd.OwnerDisplayName,
      qd.QuestionScore,
      qd.AnswerCount,
      qd.Tags,
      qd.QuestionCreationDate,
      utr.TotalReputationChange AS OwnerReputationChange
    FROM QuestionDetails AS qd
    LEFT JOIN UserTotalReputation AS utr
      ON qd.OwnerUserId = utr.UserId
    WHERE
      qd.QuestionScore > 100
      AND qd.AnswerCount BETWEEN 5 AND 50
      AND qd.ClosedDate IS NULL
      AND qd.CommunityOwnedDate IS NULL
      AND utr.TotalReputationChange IS NULL
      OR qd.QuestionScore > 500
      AND qd.AnswerCount >= 50
      AND qd.ClosedDate IS NULL
      AND qd.CommunityOwnedDate IS NULL
      AND utr.TotalReputationChange > 10000
  ),
  HighestRatedAnswers AS (
    SELECT
      ad.AnswerId,
      ad.QuestionId,
      ad.OwnerDisplayName,
      ad.AnswerScore,
      ad.AnswerCreationDate,
      ad.RankByScore
    FROM AnswerDetails AS ad
    WHERE
      ad.AnswerScore > 50
      AND ad.RankByScore <= 3
  )
SELECT
  tq.QuestionTitle,
  tq.OwnerDisplayName AS QuestionOwner,
  tq.QuestionScore,
  tq.AnswerCount,
  tq.Tags,
  tq.QuestionCreationDate,
  tq.OwnerReputationChange,
  hra.AnswerScore AS TopAnswerScore,
  hra.OwnerDisplayName AS TopAnswerOwner,
  hra.AnswerCreationDate AS TopAnswerDate,
  CASE
    WHEN tq.QuestionFavoriteCount IS NULL THEN 'No Favorites'
    WHEN tq.QuestionFavoriteCount > 100 THEN 'Very Popular'
    ELSE 'Moderately Popular'
  END AS PopularityStatus,
  IIF(tq.QuestionViewCount > AVG(tq.QuestionViewCount) OVER (), 'Above Average Views', 'Below Average Views') AS ViewStatus,
  COALESCE(tq.ClosedDate, tq.CommunityOwnedDate, '1900-01-01') AS EffectiveClosedOrCommunityDate
FROM TopQuestions AS tq
FULL OUTER JOIN HighestRatedAnswers AS hra
  ON tq.QuestionId = hra.QuestionId
WHERE
  tq.QuestionScore + COALESCE(hra.AnswerScore, 0) > 100
  AND tq.OwnerReputationChange IS NULL
  OR tq.QuestionScore + COALESCE(hra.AnswerScore, 0) > 500
  AND tq.OwnerReputationChange > 5000
ORDER BY
  tq.QuestionScore DESC,
  hra.AnswerScore DESC;
