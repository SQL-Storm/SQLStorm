WITH VoteSums AS (
  SELECT
    p.Id AS PostId,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesRecent,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesRecent
  FROM Posts p
  LEFT JOIN Votes v
    ON v.PostId = p.Id
    AND v.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '7' DAY)
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
    AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
    AND p.OwnerUserId IS NOT NULL
  GROUP BY p.Id
),
TrendingPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Tags,
    p.OwnerUserId,
    COALESCE(vs.UpVotesRecent, 0) AS UpVotesRecent,
    COALESCE(vs.DownVotesRecent, 0) AS DownVotesRecent,
    (p.Score * 2
      + COALESCE(p.ViewCount, 0) * 0.5
      + COALESCE(vs.UpVotesRecent, 0)
      - COALESCE(vs.DownVotesRecent, 0)
    ) AS TrendingScore
  FROM Posts p
  LEFT JOIN VoteSums vs ON vs.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
    AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
    AND p.OwnerUserId IS NOT NULL
),
Numbered AS (
  SELECT
    tp.*,
    ROW_NUMBER() OVER (ORDER BY tp.TrendingScore DESC) AS rn
  FROM TrendingPosts tp
),
Aggregated AS (
  SELECT
    n.PostId,
    n.Title,
    n.Score,
    n.ViewCount,
    n.CreationDate,
    n.Tags,
    n.OwnerUserId,
    u.DisplayName,
    u.Reputation,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = n.PostId) AS CommentCount,
    (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = n.PostId) AS AnswerCount,
    n.rn
  FROM Numbered n
  JOIN Users u ON u.Id = n.OwnerUserId
  WHERE n.rn <= 100
),
HotTags AS (
  SELECT
    tg.TagName,
    COUNT(*) AS TagCount
  FROM Tags tg
  WHERE tg.Count > 0
  GROUP BY tg.TagName
  ORDER BY COUNT(*) DESC
  LIMIT 5
)
SELECT
  a.PostId,
  a.Title,
  a.Score,
  a.ViewCount,
  a.CreationDate,
  a.Tags,
  a.OwnerUserId,
  a.DisplayName AS OwnerDisplayName,
  a.Reputation,
  a.CommentCount,
  a.AnswerCount,
  ht.TagName AS HotTag,
  ht.TagCount
FROM Aggregated a
LEFT JOIN HotTags ht ON 1=1
ORDER BY a.rn, a.CreationDate DESC;