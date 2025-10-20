-- {"query": "9040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 5071} 

WITH
-- recent 30‑day posts per user, with rank
RecentPosts AS (
  SELECT
    p.Id,
    p.OwnerUserId,
    p.PostTypeId,
    p.CreationDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.CreationDate DESC
    ) AS rn
  FROM Posts p
  WHERE p.CreationDate > now() - INTERVAL '30 days'
),
-- top users by reputation (at least 1k views)
TopUsers AS (
  SELECT
    u.Id        AS UserId,
    u.DisplayName,
    RANK() OVER (ORDER BY u.Reputation DESC) AS RepRank,
    COALESCE(u.AboutMe, '')                 AS AboutMeText
  FROM Users u
  WHERE u.Views > 1000
),
-- total posts per user
UserPostCounts AS (
  SELECT
    OwnerUserId AS UserId,
    COUNT(*)     AS PostCount
  FROM Posts
  GROUP BY OwnerUserId
),
-- tag usage via splitting the Tags string
TagPosts AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagUsage
  FROM Posts p
    CROSS JOIN LATERAL unnest(
      string_to_array(
        substring(p.Tags,2,length(p.Tags)-2)
      , '><')
    ) AS t(TagName)
  GROUP BY t.TagName
),
-- flatten badges by class
BadgeUnion AS (
  SELECT Name, 'Gold'   AS Tier, UserId, Date FROM Badges WHERE Class = 1
  UNION ALL
  SELECT Name, 'Silver' AS Tier, UserId, Date FROM Badges WHERE Class = 2
  UNION ALL
  SELECT Name, 'Bronze' AS Tier, UserId, Date FROM Badges WHERE Class = 3
),
-- most recent badge per user
RecentBadge AS (
  SELECT DISTINCT ON (UserId)
    UserId,
    Name   AS LatestBadge
  FROM BadgeUnion
  ORDER BY UserId, Date DESC
),
-- filter to top 100 users with some posts
FilteredUsers AS (
  SELECT
    tu.UserId,
    tu.DisplayName,
    COALESCE(up.PostCount,0) AS PostCount,
    tu.RepRank,
    rb.LatestBadge
  FROM TopUsers tu
  LEFT JOIN UserPostCounts up ON up.UserId = tu.UserId
  LEFT JOIN RecentBadge rb      ON rb.UserId = tu.UserId
  WHERE tu.RepRank <= 100
    AND (up.PostCount > 10 OR up.PostCount IS NULL)
),
-- main result combining posts, tags, window functions, correlated subquery, NULL/CASE logic
MainResult AS (
  SELECT
    fu.UserId,
    fu.DisplayName,
    fu.PostCount,
    fu.RepRank,
    COUNT(rp.Id) OVER (PARTITION BY fu.UserId)      AS RecentPostCount,
    MAX(tp.TagUsage) OVER (PARTITION BY fu.UserId)   AS MaxTagUsage,
    CASE WHEN fu.PostCount = 0 THEN 'NoPosts' ELSE 'Active' END AS ActivityStatus,
    (SELECT COUNT(*)
     FROM Comments c
     WHERE c.UserId = fu.UserId
       AND c.CreationDate > now() - INTERVAL '60 days'
    ) AS RecentComments
  FROM FilteredUsers fu
  FULL OUTER JOIN RecentPosts rp
    ON rp.OwnerUserId = fu.UserId AND rp.rn <= 5
  LEFT JOIN TagPosts tp
    ON tp.TagName = fu.LatestBadge
  WHERE EXISTS (
    SELECT 1
    FROM Posts p2
    WHERE p2.OwnerUserId = fu.UserId
      AND p2.Score > COALESCE(
        (SELECT AVG(p3.Score) FROM Posts p3 WHERE p3.OwnerUserId = p2.OwnerUserId)
      ,0)
  )
    AND fu.DisplayName ~ '^[A-Za-z]'
),
-- posts with huge viewcounts
PostFilter AS (
  SELECT
    p.OwnerUserId                 AS UserId,
    NULL::varchar                 AS DisplayName,
    COUNT(*)                      AS PostCount,
    0                             AS RepRank,
    MAX(p.ViewCount)              AS RecentPostCount,
    CASE WHEN MAX(p.Score) > 0 THEN 'HighScore' ELSE 'LowScore' END AS ActivityStatus,
    MAX(p.Score)                  AS MaxTagUsage
  FROM Posts p
  WHERE p.ViewCount > 10000
  GROUP BY p.OwnerUserId
),
-- users who cast down‑votes
VoteFilter AS (
  SELECT
    v.UserId,
    NULL::varchar  AS DisplayName,
    0              AS PostCount,
    0              AS RepRank,
    0              AS RecentPostCount,
    'VotedDown'    AS ActivityStatus,
    0              AS MaxTagUsage
  FROM Votes v
  WHERE v.VoteTypeId = 3
)
-- final combination with set operators
SELECT *
FROM MainResult
INTERSECT
SELECT * FROM PostFilter
EXCEPT
SELECT * FROM VoteFilter
ORDER BY UserId;
