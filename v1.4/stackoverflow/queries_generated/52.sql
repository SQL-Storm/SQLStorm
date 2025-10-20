-- {"query": "52.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1125} 
WITH
RecentActive AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews,
    STRING_AGG(DISTINCT u.DisplayName, ',') AS TopContributors
  FROM Tags t
  JOIN Posts p ON p.Id = t.ExcerptPostId OR p.Id = t.WikiPostId
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE t.IsModeratorOnly = 0
  GROUP BY t.TagName
),
CorrelatedEdges AS (
  SELECT
    rl.PostId,
    rl.RelatedPostId,
    lt.Name AS LinkTypeName,
    v1.CreationDate AS PostDate,
    v2.CreationDate AS RelatedPostDate
  FROM PostLinks rl
  JOIN LinkTypes lt ON rl.LinkTypeId = lt.Id
  LEFT JOIN Posts p ON rl.PostId = p.Id
  LEFT JOIN Posts rp ON rl.RelatedPostId = rp.Id
  LEFT JOIN Votes v1 ON rl.PostId = v1.PostId AND v1.CreationDate = (
    SELECT MAX(CreationDate) FROM Votes v WHERE v.PostId = rl.PostId
  )
  LEFT JOIN Votes v2 ON rl.RelatedPostId = v2.PostId AND v2.CreationDate = (
    SELECT MAX(CreationDate) FROM Votes v WHERE v.PostId = rl.RelatedPostId
  )
),
AggregatedActivity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    COALESCE(vs.UpModCount,0) AS UpModCount,
    COALESCE(vs.DownModCount,0) AS DownModCount,
    COALESCE(vs.EditedCount,0) AS EditedCount
  FROM Posts p
  LEFT JOIN (
    SELECT PostId,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpModCount,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownModCount,
           SUM(CASE WHEN VoteTypeId IN (4,6,7,8,9,10,11,12,14,15,16) THEN 1 ELSE 0 END) AS EditedCount
    FROM Votes
    GROUP BY PostId
  ) vs ON p.Id = vs.PostId
  WHERE p.LastActivityDate >= NOW() - INTERVAL '7 days'
),
Windowed AS (
  SELECT
    a.*,
    ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY a.LastActivityDate DESC) AS rn
  FROM AggregatedActivity a
)
SELECT
  ro.PostId AS PostId,
  ro.OwnerUserId AS OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  ro.Title AS Title,
  ro.Tags AS Tags,
  ro.CreationDate AS CreationDate,
  ro.LastActivityDate AS LastActivityDate,
  ro.Score AS Score,
  ro.ViewCount AS ViewCount,
  ro.AnswerCount AS AnswerCount,
  ro.CommentCount AS CommentCount,
  ro.FavoriteCount AS FavoriteCount,
  COALESCE(vs.UpModCount,0) AS UpVotes,
  COALESCE(vs.DownModCount,0) AS DownVotes,
  COALESCE(vs.EditedCount,0) AS Edits,
  ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS TagsList,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = ro.PostId) AS TotalLinks,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ro.PostId AND v.VoteTypeId = 2) AS UpModVotes,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ro.PostId AND v.VoteTypeId = 3) AS DownModVotes
FROM Windowed ro
LEFT JOIN Users u ON ro.OwnerUserId = u.Id
LEFT JOIN LATERAL (
  SELECT COUNT(*) AS UpModCount, COUNT(*) AS DownModCount, COUNT(*) AS EditedCount
  FROM Votes v
  WHERE v.PostId = ro.PostId
) AS vs ON TRUE
LEFT JOIN LATERAL (
  SELECT unnest(string_to_array(ro.Tags, '><')) AS TagName
) AS t ON TRUE
LEFT JOIN TopTags tt ON tt.TagName IN (SELECT TagName FROM unnest(string_to_array(ro.Tags, '><')) AS TagName)
WHERE ro.rn = 1
ORDER BY ro.LastActivityDate DESC
LIMIT 100;