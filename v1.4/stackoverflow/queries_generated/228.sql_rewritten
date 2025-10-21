-- {"query": "228.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 9417} 
WITH
SetA AS (
  SELECT p.Id AS PostId, p.OwnerUserId, p.Title, p.Tags, p.ViewCount, p.Score, p.CreationDate, p.LastActivityDate, p.PostTypeId
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
),
SetB AS (
  SELECT p.Id AS PostId, p.OwnerUserId, p.Title, p.Tags, p.ViewCount, p.Score, p.CreationDate, p.LastActivityDate, p.PostTypeId
  FROM Posts p
  WHERE p.PostTypeId IN (4,5)
    AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
),
UnionSet AS (
  SELECT * FROM SetA
  UNION ALL
  SELECT * FROM SetB
),
TagInfo AS (
  SELECT us.PostId,
         CASE WHEN us.Tags IS NULL THEN 0
              ELSE array_length(string_to_array(substring(us.Tags, 2, length(us.Tags)-2), '><'), 1)
         END AS TagCount
  FROM UnionSet us
)
SELECT
  COALESCE(ud.DisplayName, 'Community') AS Author,
  us.PostId,
  us.Title,
  us.Tags,
  us.ViewCount,
  us.Score,
  us.CreationDate,
  us.LastActivityDate,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = us.PostId AND v.VoteTypeId = 2) AS UpVotes,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = us.PostId AND v.VoteTypeId = 3) AS DownVotes,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = us.PostId) AS CommentCount,
  ti.TagCount,
  COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = us.OwnerUserId), 0) AS UserBadges,
  (CASE WHEN us.OwnerUserId = -1 OR us.OwnerUserId IS NULL THEN TRUE ELSE FALSE END) AS IsCommunityOwned,
  (us.Score + us.ViewCount * 0.4
   + ((SELECT COUNT(*) FROM Votes v WHERE v.PostId = us.PostId AND v.VoteTypeId = 2)
      - (SELECT COUNT(*) FROM Votes v WHERE v.PostId = us.PostId AND v.VoteTypeId = 3)) * 2.0
   + COALESCE(ti.TagCount, 0) * 0.8
   + COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = us.OwnerUserId), 0) * 1.5) AS PerformanceScore,
  ROW_NUMBER() OVER (PARTITION BY us.PostTypeId ORDER BY us.Score DESC, us.ViewCount DESC) AS RankWithinType
FROM UnionSet us
LEFT JOIN Users ud ON ud.Id = us.OwnerUserId
LEFT JOIN TagInfo ti ON ti.PostId = us.PostId
ORDER BY PerformanceScore DESC
LIMIT 200;