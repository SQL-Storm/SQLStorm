-- {"query": "305.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 17080} 
WITH
TaggedPosts AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.PostTypeId,
    t.TagName
  FROM Posts p
  CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName)
  WHERE p.Tags IS NOT NULL
    AND p.Tags <> ''
    AND p.CreationDate >= now() - interval '365 days'
),
RankedScore AS (
  SELECT
    TagName, PostId, OwnerUserId, Title, CreationDate, Score, ViewCount, PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY TagName ORDER BY Score DESC, ViewCount DESC, CreationDate DESC) AS rn
  FROM TaggedPosts
),
TopScore AS (
  SELECT * FROM RankedScore WHERE rn <= 8
),
RankedViews AS (
  SELECT
    TagName, PostId, OwnerUserId, Title, CreationDate, Score, ViewCount, PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY TagName ORDER BY ViewCount DESC, Score DESC) AS rv
  FROM TaggedPosts
),
TopViews AS (
  SELECT * FROM RankedViews WHERE rv <= 8
),
UnionTop AS (
  SELECT TagName, PostId, OwnerUserId, Title, CreationDate, Score, ViewCount, PostTypeId
  FROM TopScore
  UNION ALL
  SELECT TagName, PostId, OwnerUserId, Title, CreationDate, Score, ViewCount, PostTypeId
  FROM TopViews
),
Enriched AS (
  SELECT
    ut.TagName,
    ut.PostId,
    ut.OwnerUserId,
    ut.Title,
    ut.CreationDate,
    ut.Score,
    ut.ViewCount,
    ut.PostTypeId,
    COALESCE(u.DisplayName, 'Unknown') AS OwnerDisplayName,
    COALESCE(u.Reputation, 0) AS OwnerReputation
  FROM UnionTop ut
  LEFT JOIN Users u ON u.Id = ut.OwnerUserId
),
Engagement AS (
  SELECT
    e.TagName,
    e.PostId,
    e.OwnerUserId,
    e.OwnerDisplayName,
    e.OwnerReputation,
    e.Title,
    e.CreationDate,
    e.Score,
    e.ViewCount,
    e.PostTypeId,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = e.PostId AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = e.PostId AND v.VoteTypeId = 3) AS DownVotes,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = e.PostId AND pl.LinkTypeId = 3) AS Duplicates
  FROM Enriched e
),
BadgeAgg AS (
  SELECT UserId,
         SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
         SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
         SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges
  GROUP BY UserId
),
OwnerAvg AS (
  SELECT OwnerUserId, AVG(Score) AS AvgScore
  FROM Posts
  WHERE OwnerUserId IS NOT NULL
  GROUP BY OwnerUserId
)
SELECT
  g.TagName,
  g.PostId,
  g.Title,
  g.OwnerUserId,
  g.OwnerDisplayName,
  g.OwnerReputation,
  g.Score,
  g.ViewCount,
  g.CreationDate,
  g.PostTypeId,
  g.UpVotes,
  g.DownVotes,
  g.Duplicates,
  COALESCE(ba.GoldBadges, 0) AS GoldBadges,
  COALESCE(ba.SilverBadges, 0) AS SilverBadges,
  COALESCE(ba.BronzeBadges, 0) AS BronzeBadges,
  COALESCE(oa.AvgScore, 0) AS OwnerAvgPostScore
FROM Engagement g
LEFT JOIN BadgeAgg ba ON ba.UserId = g.OwnerUserId
LEFT JOIN OwnerAvg oa ON oa.OwnerUserId = g.OwnerUserId
ORDER BY g.TagName, g.Score DESC
LIMIT 200;