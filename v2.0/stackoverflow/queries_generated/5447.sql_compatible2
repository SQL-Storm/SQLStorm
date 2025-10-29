WITH recent_top_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.tags AS Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
top_tags AS (
  SELECT
    t2.TagName,
    COUNT(*) AS PostCount,
    AVG(t2.Score) AS AvgScore,
    MAX(t2.ViewCount) AS MaxViews
  FROM (
    SELECT
      unnest(string_to_array(substr(p.tags, 2, length(p.tags) - 2), '><')) AS TagName,
      p.Score,
      p.ViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
  ) AS t2
  JOIN Tags tg ON tg.TagName = t2.TagName
  GROUP BY t2.TagName
  ORDER BY PostCount DESC
  LIMIT 5
),
activity_by_user AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes,
    MAX(p.LastActivityDate) AS LastActivePostDate,
    SUM(p.ViewCount) AS TotalViews
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
complex_surf AS (
  SELECT
    rt.PostId,
    rt.Title,
    rt.LastActivityDate,
    rt.ViewCount,
    rt.Score,
    rt.CommentCount,
    rt.AnswerCount,
    rt.FavoriteCount,
    u.Id AS UserId,
    u.DisplayName AS OwnerName,
    u.Reputation,
    ARRAY_AGG(DISTINCT tl.TagName) AS TagList
  FROM recent_top_posts rt
  LEFT JOIN Users u ON u.Id = rt.OwnerUserId
  LEFT JOIN Posts p2 ON p2.Id = rt.PostId
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p2.tags, 2, length(p2.tags) - 2), '><')) AS TagName
  ) AS tl ON TRUE
  GROUP BY rt.PostId, rt.Title, rt.LastActivityDate, rt.ViewCount, rt.Score, rt.CommentCount, rt.AnswerCount, rt.FavoriteCount, u.Id, u.DisplayName, u.Reputation
)
SELECT
  c.PostId,
  c.Title,
  c.OwnerName,
  c.Reputation AS OwnerReputation,
  c.LastActivityDate,
  c.ViewCount,
  c.Score,
  c.CommentCount,
  c.AnswerCount,
  c.FavoriteCount,
  c.TagList,
  aup.Upvotes,
  aup.Downvotes,
  atv.TotalViews AS OwnerTotalViews,
  atv.LastActivePostDate
FROM complex_surf c
LEFT JOIN activity_by_user aup ON aup.UserId = c.UserId
LEFT JOIN activity_by_user atv ON atv.UserId = c.UserId
LEFT JOIN top_tags tt ON TRUE
ORDER BY c.LastActivityDate DESC
LIMIT 100
OFFSET 0;