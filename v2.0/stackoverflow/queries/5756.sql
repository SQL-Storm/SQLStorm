-- {"query": "5756.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1065}
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    SUM(COALESCE(t.Count,0)) AS TagTotal,
    COUNT(*) AS TagEntries
  FROM Tags t
  GROUP BY t.TagName
  ORDER BY TagTotal DESC
  LIMIT 50
),
UserAgg AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.Location,
    u.AboutMe,
    COALESCE(b.GoldCount,0) AS GoldBadges,
    COALESCE(b.SilverCount,0) AS SilverBadges,
    COALESCE(b.BronzeCount,0) AS BronzeBadges,
    COALESCE(v.UpVotesTotal,0) AS UpVotesTotal
  FROM Users u
  LEFT JOIN (
    SELECT UserId,
           SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
           SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
           SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCount
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, SUM(BountyAmount) AS UpVotesTotal
    FROM Votes v
    WHERE v.VoteTypeId = 8 OR v.VoteTypeId = 9
    GROUP BY UserId
  ) v ON v.UserId = u.Id
),
Activity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    EXISTS (
      SELECT 1
      FROM Votes w
      WHERE w.PostId = p.Id
        AND w.VoteTypeId = 2
        AND w.UserId = p.OwnerUserId
    ) AS IsOwnerUpvoted
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
)
SELECT
  rh.PostId,
  rh.Title,
  rh.Tags,
  rh.Score,
  rh.ViewCount,
  rh.CreationDate,
  rh.OwnerUserId AS QuestionOwnerId,
  rh.LastActivityDate,
  ua.DisplayName AS OwnerDisplayName,
  ua.Reputation,
  ua.GoldBadges,
  ua.SilverBadges,
  ua.BronzeBadges,
  ua.ProfileImageUrl,
  ua.Location,
  ua.AboutMe,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rh.PostId) AS CommentCount,
  (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = rh.PostId AND v2.VoteTypeId = 2) AS UpVotes,
  (SELECT COUNT(*) FROM Votes v3 WHERE v3.PostId = rh.PostId AND v3.VoteTypeId = 3) AS DownVotes,
  (SELECT AVG(v4.BountyAmount) FROM Votes v4 WHERE v4.PostId = rh.PostId AND v4.BountyAmount IS NOT NULL) AS AvgBounty,
  (SELECT STRING_AGG(CAST(t2.TagName AS varchar), ',')
     FROM Tags t2
     JOIN Posts p2 ON p2.Id = rh.PostId
     WHERE p2.Id = rh.PostId) AS TagList,
  (SELECT MAX(v5.CreationDate) FROM Votes v5 WHERE v5.PostId = rh.PostId AND v5.VoteTypeId = 2) AS LastUpvoteDate,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rh.PostId) AS LinkCount,
  CASE
    WHEN rh.Score > 20 THEN 'Hot'
    WHEN rh.Score > 0 THEN 'Active'
    ELSE 'New'
  END AS StatusTag,
  CASE
    WHEN rh.LastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7 days' THEN TRUE
    ELSE FALSE
  END AS RecentlyActive,
  (SELECT MIN(p2.LastEditDate) FROM Posts p2 WHERE p2.Id = rh.PostId) AS LastEditDate
FROM RecentHot rh
JOIN UserAgg ua ON ua.UserId = rh.OwnerUserId
LEFT JOIN TopTags tt ON 1=1
WHERE rh.rn = 1
GROUP BY
  rh.PostId,
  rh.Title,
  rh.Tags,
  rh.Score,
  rh.ViewCount,
  rh.CreationDate,
  rh.OwnerUserId,
  rh.LastActivityDate,
  ua.DisplayName,
  ua.Reputation,
  ua.GoldBadges,
  ua.SilverBadges,
  ua.BronzeBadges,
  ua.ProfileImageUrl,
  ua.Location,
  ua.AboutMe
ORDER BY rh.LastActivityDate DESC, rh.Score DESC
LIMIT 100;