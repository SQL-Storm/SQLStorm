-- {"query": "5947.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 701} 
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
  WHERE p.PostTypeId = 1 -- questions
),
ActivityWindow AS (
  SELECT
    tp.PostId,
    tp.OwnerUserId,
    tp.Score,
    tp.ViewCount,
    tp.LastActivityDate,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - tp.LastActivityDate)) / 3600 AS HoursSinceLastActivity
  FROM TopPosts tp
),
CorrelationSub AS (
  SELECT
    uw.UserId,
    uw.DisplayName,
    uw.Reputation,
    a.Score AS ActivityScore,
    b.BadgeCount,
    c.FavoriteCount,
    ROW_NUMBER() OVER (ORDER BY a.Score DESC, b.BadgeCount DESC) AS rank_score
  FROM UserStats uw
  LEFT JOIN RecentBadges b ON b.UserId = uw.UserId
  LEFT JOIN Posts p ON p.OwnerUserId = uw.UserId
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
  LEFT JOIN (
    SELECT OwnerUserId, SUM(Score) AS Score
    FROM Posts
    GROUP BY OwnerUserId
  ) a ON a.OwnerUserId = uw.UserId
)
SELECT
  cs.UserId,
  cs.DisplayName,
  cs.Reputation,
  cs.ActivityScore,
  cs.BadgeCount,
  cs.FavoriteCount,
  cs.rank_score,
  ac.LastBadgeDate,
  rp.rn_by_owner AS TopQuestionRank,
  rp.Title AS TopQuestionTitle,
  rp.Score AS TopQuestionScore,
  ac.HoursSinceLastActivity
FROM CorrelationSub cs
LEFT JOIN RecentBadges rb ON rb.UserId = cs.UserId
LEFT JOIN ActivityWindow aw ON aw.OwnerUserId = cs.UserId
LEFT JOIN TopPosts rp ON rp.OwnerUserId = cs.UserId AND rp.rn_by_owner = 1
LEFT JOIN (
  SELECT
    OwnerUserId,
    MAX(rn_by_owner) AS rn_by_owner
  FROM TopPosts
  GROUP BY OwnerUserId
) rp ON rp.OwnerUserId = cs.UserId
WHERE cs.Reputation > 1000
ORDER BY cs.rank_score ASC, cs.Reputation DESC
LIMIT 100;