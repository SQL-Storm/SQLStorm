WITH UserStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
),
RecentBadges AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    MAX(b.Date) AS LastBadgeDate
  FROM Badges b
  GROUP BY b.UserId
),
TopPosts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    p.CreationDate,
    p.LastActivityDate,
    p.PostTypeId,
    p.Tags,
    p.AnswerCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.LastActivityDate DESC) AS rn_by_owner
  FROM Posts p
  WHERE p.PostTypeId = 1
),
ActivityWindow AS (
  SELECT
    tp.PostId,
    tp.OwnerUserId,
    tp.Score,
    tp.ViewCount,
    tp.LastActivityDate,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - tp.LastActivityDate)) / 3600.0 AS HoursSinceLastActivity
  FROM TopPosts tp
),
CorrelationSub AS (
  SELECT
    uw.UserId,
    uw.DisplayName,
    uw.Reputation,
    COALESCE(a.Score, 0) AS ActivityScore,
    COALESCE(b.BadgeCount, 0) AS BadgeCount,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
    ROW_NUMBER() OVER (ORDER BY COALESCE(a.Score, 0) DESC, COALESCE(b.BadgeCount, 0) DESC) AS rank_score
  FROM UserStats uw
  LEFT JOIN RecentBadges b ON b.UserId = uw.UserId
  LEFT JOIN (
    SELECT OwnerUserId, SUM(Score) AS Score
    FROM Posts
    GROUP BY OwnerUserId
  ) a ON a.OwnerUserId = uw.UserId
  LEFT JOIN Posts p ON p.OwnerUserId = uw.UserId
)
SELECT
  cs.UserId,
  cs.DisplayName,
  cs.Reputation,
  cs.ActivityScore,
  cs.BadgeCount,
  cs.FavoriteCount,
  cs.rank_score,
  rb.LastBadgeDate,
  tp_top.rn_by_owner AS TopQuestionRank,
  tp_top.Title AS TopQuestionTitle,
  tp_top.Score AS TopQuestionScore,
  aw.HoursSinceLastActivity
FROM CorrelationSub cs
LEFT JOIN RecentBadges rb ON rb.UserId = cs.UserId
LEFT JOIN ActivityWindow aw ON aw.OwnerUserId = cs.UserId
LEFT JOIN TopPosts tp_top ON tp_top.OwnerUserId = cs.UserId AND tp_top.rn_by_owner = 1
WHERE cs.Reputation > 1000
ORDER BY cs.rank_score ASC, cs.Reputation DESC
LIMIT 100;