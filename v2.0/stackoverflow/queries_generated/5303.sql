-- {"query": "5303.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 915} 
WITH
PostsWithStats AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Title,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.CloseReasonTypesId
  FROM Posts p
),
TagMatches AS (
  SELECT
    p.PostId,
    UNNEST(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag
  FROM PostsWithStats p
  WHERE p.PostTypeId = 1
),
TopTags AS (
  SELECT Tag, COUNT(*) AS TagCount
  FROM TagMatches
  GROUP BY Tag
  ORDER BY TagCount DESC
  LIMIT 10
),
RecentActive AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    u.Reputation,
    u.DisplayName,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.LastActivityDate >= NOW() - INTERVAL '30 days'
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
    COUNT(DISTINCT p.Id) AS PostsCreated
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
CorrelatedActivity AS (
  SELECT
    r.PostId,
    r.OwnerUserId,
    r.Reputation,
    r.DisplayName,
    r.CreationDate AS PostCreationDate,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    a.UpvotesGiven,
    a.DownvotesGiven,
    a.PostsCreated
  FROM RecentActive r
  LEFT JOIN UserActivity a ON r.OwnerUserId = a.UserId
),
MixedMetrics AS (
  SELECT
    c.PostId,
    c.OwnerUserId,
    c.Reputation,
    c.DisplayName,
    c.PostCreationDate,
    c.LastActivityDate,
    c.Score,
    c.ViewCount,
    c.UpvotesGiven,
    c.DownvotesGiven,
    c.PostsCreated,
    CASE
      WHEN c.Reputation IS NULL THEN 0
      ELSE c.Reputation
    END AS ReputationSafe,
    CASE
      WHEN c.UpvotesGiven IS NULL THEN 0
      ELSE c.UpvotesGiven
    END AS UpvotesGivenSafe
  FROM CorrelatedActivity c
),
FinalOutput AS (
  SELECT
    m.PostId,
    m.OwnerUserId,
    m.DisplayName AS OwnerDisplayName,
    m.PostCreationDate,
    m.LastActivityDate,
    m.Score,
    m.ViewCount,
    m.ReputationSafe,
    m.UpvotesGivenSafe,
    m.DownvotesGiven,
    m.PostsCreated,
    t.Tag AS RelatedTag
  FROM MixedMetrics m
  CROSS JOIN TopTags t
  WHERE m.OwnerUserId IS NOT NULL
    AND m.LastActivityDate >= (SELECT MIN(CreationDate) FROM Posts)
    AND m.LastActivityDate <= NOW()
    AND (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = m.PostId) >= 0
)
SELECT
  PostId,
  OwnerUserId,
  OwnerDisplayName,
  PostCreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  ReputationSafe AS Reputation,
  UpvotesGivenSafe AS Upvotes,
  DownvotesGiven,
  PostsCreated,
  RelatedTag,
  (CASE WHEN Score > 0 THEN 'Trending' ELSE 'Steady' END) AS TrendCategory,
  (CASE
     WHEN ViewCount > 1000 THEN 'HighTraffic'
     WHEN ViewCount > 100 THEN 'Moderate'
     ELSE 'Low'
   END) AS TrafficBucket
FROM FinalOutput
ORDER BY LastActivityDate DESC, Score DESC
LIMIT 100;