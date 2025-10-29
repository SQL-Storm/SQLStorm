-- {"query": "5185.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 574} 
WITH TopAsked AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.LastActivityDate,
    p.LastEditDate,
    p.Title
  FROM Posts p
  WHERE p.PostTypeId = 1
),
ActiveUsers AS (
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
    u.ProfileImageUrl
  FROM Users u
  WHERE u.Reputation > 1000
),
BadgeSummary AS (
  SELECT
    b.UserId,
    COUNT(*) AS GoldBadges
  FROM Badges b
  WHERE b.Class = 1
  GROUP BY b.UserId
),
CrossJoinStats AS (
  SELECT
    t.PostId,
    t.Title,
    t.CreationDate,
    t.Score,
    t.ViewCount,
    t.OwnerUserId,
    t.Tags,
    ra.LastActivityDate,
    ra.LastEditDate,
    ab.Reputation,
    bs.GoldBadges
  FROM TopAsked t
  LEFT JOIN RecentActivity ra ON ra.PostId = t.PostId
  LEFT JOIN ActiveUsers ab ON ab.UserId = t.OwnerUserId
  LEFT JOIN BadgeSummary bs ON bs.UserId = t.OwnerUserId
  WHERE t.rn = 1
),
Windowed AS (
  SELECT
    PostId,
    Title,
    CreationDate,
    Score,
    ViewCount,
    OwnerUserId,
    Tags,
    LastActivityDate,
    LastEditDate,
    Reputation,
    GoldBadges,
    ROW_NUMBER() OVER (ORDER BY Score DESC, ViewCount DESC, LastActivityDate DESC) AS rk
  FROM CrossJoinStats
  CROSS JOIN LATERAL (
    SELECT 1
  ) AS d
)
SELECT
  PostId,
  Title,
  CreationDate,
  Score,
  ViewCount,
  OwnerUserId,
  Tags,
  LastActivityDate,
  LastEditDate,
  Reputation,
  GoldBadges,
  rk
FROM Windowed
WHERE rk <= 100
ORDER BY rk ASC;