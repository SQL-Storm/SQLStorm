-- {"query": "5500.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1062} 
WITH RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.AcceptedAnswerId,
    p.ParentId
  FROM Posts p
  WHERE p.CreationDate >= now() - interval '180 days'
),
TopTags AS (
  SELECT
    t.TagName,
    t.Id AS TagId,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
    AND t.Count > 100
),
PopularPostLinks AS (
  SELECT
    pl.Id,
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    pl.CreationDate,
    plm.LinkedName = (SELECT u.DisplayName FROM Users u WHERE u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = pl.PostId))
  FROM PostLinks pl
  WHERE pl.LinkTypeId IN (1, 3)
),
AggregatedVotes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotes,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountyStarts,
    SUM(CASE WHEN v.VoteTypeId = 9 THEN 1 ELSE 0 END) AS BountyCloses,
    COUNT(*) AS VoteCount
  FROM Votes v
  GROUP BY v.PostId
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(p.Id) AS PostsCount,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
CTE_Final AS (
  SELECT
    rap.PostId,
    rap.PostTypeId,
    rap.OwnerUserId,
    rap.Title,
    rap.Tags,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.Score,
    rap.ViewCount,
    rap.CommentCount,
    rap.AnswerCount,
    rap.FavoriteCount,
    COALESCE(av.UpVotes, 0) AS UpVotes,
    COALESCE(av.DownVotes, 0) AS DownVotes,
    COALESCE(av.CloseVotes, 0) AS CloseVotes,
    COALESCE(av.BountyStarts, 0) AS BountyStarts,
    COALESCE(av.BountyCloses, 0) AS BountyCloses,
    COALESCE(av.VoteCount, 0) AS TotalVotes,
    ua.PostsCount AS UserPosts,
    ua.AvgPostScore AS UserAvgScore,
    ua.LastActive AS UserLastActive,
    Row_Number() OVER (
      PARTITION BY rap.PostTypeId
      ORDER BY rap.Score DESC, rap.ViewCount DESC, rap.LastActivityDate DESC
    ) AS RankInType
  FROM RecentActivePosts rap
  LEFT JOIN AggregatedVotes av ON av.PostId = rap.Id
  LEFT JOIN UserActivity ua ON ua.UserId = rap.OwnerUserId
)
SELECT
  cf.PostId,
  cf.PostTypeId,
  cf.Title,
  cf.Tags,
  cf.CreationDate,
  cf.LastActivityDate,
  cf.Score,
  cf.ViewCount,
  cf.CommentCount,
  cf.AnswerCount,
  cf.FavoriteCount,
  cf.UpVotes,
  cf.DownVotes,
  cf.CloseVotes,
  cf.BountyStarts,
  cf.BountyCloses,
  cf.TotalVotes,
  cf.UserPosts,
  cf.UserAvgScore,
  cf.UserLastActive,
  ct.Name AS PostTypeName,
  au.DisplayName AS OwnerDisplayName,
  pt.Name AS PrimaryTag
FROM CTE_Final cf
LEFT JOIN PostTypes pt ON pt.Id = cf.PostTypeId
LEFT JOIN PostTypes ct ON ct.Id = cf.PostTypeId
LEFT JOIN Users au ON au.Id = cf.OwnerUserId
LEFT JOIN (
  SELECT
    t.TagName AS PrimaryTag,
    t.Id AS TagId
  FROM Tags t
  WHERE t.Id = (SELECT TOP 1 t2.Id FROM Tags t2 WHERE t2.Count = t.Count ORDER BY t2.Count DESC)
) AS g ON 1=1
WHERE cf.RankInType <= 50
ORDER BY cf.Score DESC, cf.ViewCount DESC, cf.LastActivityDate DESC
LIMIT 100;