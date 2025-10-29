-- {"query": "5057.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 659} 
WITH TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.Reputation > 1000
),
RecentActivity AS (
  SELECT
    p.OwnerUserId,
    MAX(p.CreationDate) AS LastPostDate,
    COUNT(*) AS PostCount
  FROM Posts p
  GROUP BY p.OwnerUserId
),
BadgeActivity AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgesEarned,
    MAX(b.Date) AS LastBadgeDate
  FROM Badges b
  GROUP BY b.UserId
),
VoteActivity AS (
  SELECT
    v.UserId,
    SUM(CASE WHEN vt.Name = 'UpMod (AKA upvote)' THEN 1 ELSE 0 END) AS UpvotesGiven,
    SUM(CASE WHEN vt.Name = 'DownMod (AKA downvote)' THEN 1 ELSE 0 END) AS DownvotesGiven,
    COUNT(*) AS VotesCast
  FROM Votes v
  JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  GROUP BY v.UserId
),
Combined AS (
  SELECT
    t.UserId,
    t.DisplayName,
    t.Reputation,
    r.LastPostDate,
    r.PostCount,
    b.BadgesEarned,
    b.LastBadgeDate,
    v.UpvotesGiven,
    v.DownvotesGiven,
    v.VotesCast
  FROM TopUsers t
  LEFT JOIN RecentActivity r ON r.OwnerUserId = t.UserId
  LEFT JOIN BadgeActivity b ON b.UserId = t.UserId
  LEFT JOIN VoteActivity v ON v.UserId = t.UserId
)
SELECT
  c.UserId,
  c.DisplayName,
  c.Reputation,
  c.LastPostDate,
  c.PostCount,
  c.BadgesEarned,
  c.LastBadgeDate,
  c.UpvotesGiven,
  c.DownvotesGiven,
  c.VotesCast,
  CASE
    WHEN c.PostCount IS NULL THEN 0
    ELSE c.PostCount * 2 + COALESCE(c.UpvotesGiven,0) - COALESCE(c.DownvotesGiven,0)
  END AS ScoreBenchmark,
  ARRAY_AGG(DISTINCT lt.Name) FILTER (WHERE lnk.LinkTypeId = 1) AS LinkedPostTags
FROM Combined c
LEFT JOIN Posts p ON p.OwnerUserId = c.UserId
LEFT JOIN PostLinks lnk ON lnk.PostId = p.Id
LEFT JOIN LinkTypes lt ON lt.Id = lnk.LinkTypeId
GROUP BY
  c.UserId, c.DisplayName, c.Reputation, c.LastPostDate, c.PostCount,
  c.BadgesEarned, c.LastBadgeDate, c.UpvotesGiven, c.DownvotesGiven, c.VotesCast
HAVING
  (c.PostCount IS NULL OR c.PostCount > 0)
ORDER BY ScoreBenchmark DESC
LIMIT 100;