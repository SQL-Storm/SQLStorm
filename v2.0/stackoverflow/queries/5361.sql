-- {"query": "5361.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 804}
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.ParentId
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
  FROM Tags t
  WHERE t.Count > 0
),
UserEngagement AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.CreationDate AS UserSince,
    u.LastAccessDate,
    COALESCE(SUM(v.BountyAmount),0) AS TotalBounties,
    COUNT(DISTINCT p.Id) AS PostsCreated,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
CorrelatedSubquery AS (
  SELECT
    r.Id AS PostId,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = r.Id) AS CommentCountOnPost,
    (SELECT AVG(v2.BountyAmount) FROM Votes v2 WHERE v2.PostId = r.Id AND v2.BountyAmount > 0) AS AvgBountyOnPost
  FROM RecentActivePosts r
),
WindowedStats AS (
  SELECT
    rp.PostId,
    rp.CommentCountOnPost,
    rp.AvgBountyOnPost,
    ROW_NUMBER() OVER (PARTITION BY rp.PostId ORDER BY rp.CommentCountOnPost DESC) AS rn
  FROM CorrelatedSubquery rp
),
Joined AS (
  SELECT
    rap.Id AS PostId,
    rap.Title,
    rap.OwnerUserId,
    rap.Tags,
    rap.ViewCount,
    rap.Score,
    rap.AnswerCount,
    rap.CommentCount,
    rap.FavoriteCount,
    rap.Body,
    rap.CreationDate,
    rap.LastActivityDate,
    uw.DisplayName AS OwnerName,
    uw.Reputation AS OwnerReputation,
    wt.Name AS PostTypeName,
    tt.rn AS TagRank
  FROM RecentActivePosts rap
  LEFT JOIN Users uw ON rap.OwnerUserId = uw.Id
  LEFT JOIN (
    SELECT Id, Name FROM PostTypes
  ) wt ON rap.PostTypeId = wt.Id
  LEFT JOIN TopTags tt ON substring(rap.Tags FROM 2 FOR char_length(rap.Tags) - 2) LIKE '%' || tt.TagName || '%'
  WHERE rap.PostTypeId = 1 OR rap.PostTypeId = 2
)
SELECT
  PostId,
  PostTypeName,
  Title,
  OwnerName,
  OwnerReputation,
  CreationDate,
  LastActivityDate,
  ViewCount,
  Score,
  AnswerCount,
  CommentCount,
  FavoriteCount,
  Body,
  Tags,
  OwnerUserId,
  TagRank
FROM Joined
WHERE TagRank IS NOT NULL
  AND LastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '14 days'
ORDER BY LastActivityDate DESC
LIMIT 200;