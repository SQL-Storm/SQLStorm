-- {"query": "190.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1444} 
WITH
RecentPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    pt.Name AS PostTypeName,
    p.OwnerUserId
  FROM Posts p
  JOIN PostTypes pt ON pt.Id = p.PostTypeId
),
Owner AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation
  FROM Users u
),
OwnerBadges AS (
  SELECT
    b.UserId AS OwnerUserId,
    COUNT(*) AS BadgeCount
  FROM Badges b
  GROUP BY b.UserId
),
Joined AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Score,
    rp.ViewCount,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.PostTypeName,
    o.DisplayName AS Owner,
    o.Reputation,
    COALESCE(ob.BadgeCount, 0) AS BadgeCount
  FROM RecentPosts rp
  LEFT JOIN Users o ON o.Id = rp.OwnerUserId
  LEFT JOIN OwnerBadges ob ON ob.OwnerUserId = rp.OwnerUserId
  WHERE rp.CreationDate > CURRENT_TIMESTAMP - INTERVAL '30 days'
)
SELECT
  PostId,
  Title,
  Score,
  ViewCount,
  CreationDate,
  LastActivityDate,
  PostTypeName,
  Owner,
  Reputation,
  BadgeCount,
  ROW_NUMBER() OVER (ORDER BY Score DESC NULLS LAST, ViewCount DESC) AS rn
FROM Joined
ORDER BY Score DESC NULLS LAST, ViewCount DESC
LIMIT 100;