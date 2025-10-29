WITH
  UserPostCounts AS (
    SELECT
      OwnerUserId,
      COUNT(Id) AS TotalPosts,
      COUNT(CASE WHEN PostTypeId = 1 THEN 1 END) AS QuestionCount,
      COUNT(CASE WHEN PostTypeId = 2 THEN 1 END) AS AnswerCount,
      SUM(Score) AS TotalScore
    FROM Posts
    WHERE
      OwnerUserId IS NOT NULL
    GROUP BY
      OwnerUserId
  ),
  HighReputationUsers AS (
    SELECT
      Id,
      DisplayName,
      Reputation,
      CreationDate,
      (
        SELECT
          COUNT(Id)
        FROM Badges
        WHERE
          Badges.UserId = Users.Id AND Class = 1
      ) AS GoldBadges,
      (
        SELECT
          COUNT(Id)
        FROM Badges
        WHERE
          Badges.UserId = Users.Id AND Class = 2
      ) AS SilverBadges
    FROM Users
    WHERE
      Reputation > 10000
  ),
  RecentActivity AS (
    SELECT
      PostId,
      MAX(CreationDate) AS LastActivityDate
    FROM PostHistory
    GROUP BY
      PostId
  ),
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount,
      COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
      COALESCE(u.Reputation, 0) AS OwnerReputation,
      COALESCE(ra.LastActivityDate, p.LastActivityDate) AS LastPostActivity,
      (
        SELECT
          COUNT(c.Id)
        FROM Comments c
        WHERE
          c.PostId = p.Id AND c.Score > 5
      ) AS HighScoringCommentCount,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
      END AS PostStatus
    FROM Posts p
    LEFT JOIN HighReputationUsers u
      ON p.OwnerUserId = u.Id
    LEFT JOIN RecentActivity ra
      ON p.Id = ra.PostId
    WHERE
      p.PostTypeId = 1 AND p.CreationDate > DATE '2023-01-01'
  )
SELECT
  qd.QuestionId,
  qd.Title,
  qd.OwnerDisplayName,
  qd.OwnerReputation,
  qd.QuestionCreationDate,
  qd.AnswerCount,
  qd.FavoriteCount,
  qd.ViewCount,
  qd.LastPostActivity,
  qd.PostStatus,
  qd.HighScoringCommentCount,
  upc.TotalPosts AS OwnerTotalPosts,
  upc.QuestionCount AS OwnerQuestionCount,
  upc.AnswerCount AS OwnerAnswerCount,
  upc.TotalScore AS OwnerTotalScore,
  CASE
    WHEN CAST((EXTRACT(EPOCH FROM (qd.LastPostActivity - qd.QuestionCreationDate)) / 86400) AS INTEGER) < 7 THEN 'New'
    WHEN CAST((EXTRACT(EPOCH FROM (qd.LastPostActivity - qd.QuestionCreationDate)) / 86400) AS INTEGER) BETWEEN 7 AND 30 THEN 'Recent'
    ELSE 'Old'
  END AS AgeCategory,
  ROW_NUMBER() OVER (ORDER BY qd.ViewCount DESC, qd.FavoriteCount DESC) AS RankByPopularity,
  LAG(qd.ViewCount, 1, 0) OVER (ORDER BY qd.QuestionCreationDate) AS PreviousDayViewCount
FROM QuestionDetails qd
LEFT JOIN UserPostCounts upc
  ON qd.OwnerUserId = upc.OwnerUserId
WHERE
  qd.OwnerReputation > 5000
UNION ALL
SELECT
  NULL AS QuestionId,
  '--- Summary ---' AS Title,
  NULL AS OwnerDisplayName,
  AVG(qd.OwnerReputation) AS OwnerReputation,
  MIN(qd.QuestionCreationDate) AS QuestionCreationDate,
  AVG(qd.AnswerCount) AS AnswerCount,
  SUM(qd.FavoriteCount) AS FavoriteCount,
  SUM(qd.ViewCount) AS ViewCount,
  MAX(qd.LastPostActivity) AS LastPostActivity,
  'All' AS PostStatus,
  COUNT(qd.QuestionId) AS HighScoringCommentCount,
  AVG(upc.TotalPosts) AS OwnerTotalPosts,
  AVG(upc.QuestionCount) AS OwnerQuestionCount,
  AVG(upc.AnswerCount) AS OwnerAnswerCount,
  AVG(upc.TotalScore) AS OwnerTotalScore,
  NULL AS AgeCategory,
  NULL AS RankByPopularity,
  NULL AS PreviousDayViewCount
FROM QuestionDetails qd
LEFT JOIN UserPostCounts upc
  ON qd.OwnerUserId = upc.OwnerUserId
WHERE
  qd.OwnerReputation > 5000 AND qd.PostStatus <> 'Closed'
GROUP BY
  qd.QuestionId,
  qd.Title,
  qd.OwnerDisplayName,
  qd.OwnerReputation,
  qd.QuestionCreationDate,
  qd.AnswerCount,
  qd.FavoriteCount,
  qd.ViewCount,
  qd.LastPostActivity,
  qd.PostStatus,
  qd.HighScoringCommentCount,
  upc.TotalPosts,
  upc.QuestionCount,
  upc.AnswerCount,
  upc.TotalScore;