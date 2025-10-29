WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.FavoriteCount,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_by_score_view,
      DENSE_RANK() OVER (ORDER BY p.CreationDate) AS dr_by_creation,
      LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousDayScore,
      SUM(p.AnswerCount) OVER (ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeAnswerCount
    FROM Posts p
    WHERE
      p.PostTypeId IN (1, 2)
      AND p.Score > 0
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(p.Id) AS PostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AveragePostScore,
      MAX(p.LastActivityDate) AS LastPostActivity,
      COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
    HAVING
      COUNT(p.Id) > 5
  ),
  HotQuestions AS (
    SELECT
      Id,
      Title,
      Score,
      ViewCount,
      FavoriteCount,
      CreationDate,
      OwnerUserId
    FROM Posts
    WHERE
      PostTypeId = 1
      AND Score > 100
      AND ViewCount > 1000
      AND FavoriteCount > 10
      AND CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
  ),
  RecentComments AS (
    SELECT
      c.PostId,
      c.UserId,
      c.UserDisplayName,
      c.Text,
      c.CreationDate AS CommentCreationDate,
      ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS rn_recent_comment
    FROM Comments c
    WHERE
      c.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7' DAY)
  )
SELECT
  rp.PostId,
  rp.Title,
  rp.PostTypeId,
  rp.CreationDate AS PostCreationDate,
  rp.Score AS PostScore,
  rp.ViewCount AS PostViewCount,
  rp.FavoriteCount AS PostFavoriteCount,
  rp.rn_by_score_view AS RankByScoreView,
  rp.dr_by_creation AS GlobalRankByCreation,
  rp.PreviousDayScore AS ScorePreviousDay,
  rp.CumulativeAnswerCount,
  ua.DisplayName AS OwnerDisplayName,
  ua.Reputation AS OwnerReputation,
  ua.UserCreationDate,
  ua.PostCount AS OwnerPostCount,
  ua.QuestionCount AS OwnerQuestionCount,
  ua.AnswerCount AS OwnerAnswerCount,
  ua.AveragePostScore AS OwnerAveragePostScore,
  ua.LastPostActivity AS OwnerLastPostActivity,
  ua.BadgeCount AS OwnerBadgeCount,
  hq.Title AS HotQuestionTitle,
  hq.Score AS HotQuestionScore,
  rc.Text AS LatestCommentText,
  rc.UserDisplayName AS LatestCommenter,
  rc.CommentCreationDate
FROM RankedPosts rp
JOIN UserActivity ua
  ON rp.OwnerUserId = ua.UserId
LEFT JOIN HotQuestions hq
  ON rp.PostId = hq.Id
LEFT JOIN RecentComments rc
  ON rp.PostId = rc.PostId AND rc.rn_recent_comment = 1
WHERE
  rp.rn_by_score_view <= 50
  AND ua.Reputation > 10000
  AND ua.UserCreationDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365' DAY)
  AND (
    hq.Id IS NOT NULL OR rc.PostId IS NOT NULL
  )
  AND SUBSTRING(rp.Title FROM 1 FOR 3) <> 'Re:'
  AND rp.Score BETWEEN 10 AND 1000
ORDER BY
  rp.Score DESC,
  rp.ViewCount DESC
LIMIT 100;