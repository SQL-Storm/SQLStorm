-- {"query": "23.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1025} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.AnswerCount,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS rn_type
  FROM Posts p
  WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
),
UserReputationHash AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate,
    u.DisplayName,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.AccountId,
    md5(COALESCE(u.DisplayName, '')) AS DisplayHash
  FROM Users u
),
TagStats AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    CASE
      WHEN t.Count > 10000 THEN 'hot'
      WHEN t.Count > 1000 THEN 'warm'
      ELSE 'cold'
    END AS Popularity,
    ARRAY_AGG(p.Title) FILTER (WHERE p.Title IS NOT NULL) AS Titles
  FROM Tags t
  LEFT JOIN Posts p ON p.Id = t.Id AND p.PostTypeId = 1
  GROUP BY t.TagName, t.Count
),
JoinedPosts AS (
  SELECT
    rap.PostId,
    rap.PostTypeId,
    rap.OwnerUserId,
    rap.Title,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.Score,
    rap.ViewCount,
    rap.Tags,
    rap.ParentId,
    rap.AcceptedAnswerId,
    rap.CommentCount,
    rap.AnswerCount,
    ur.UserId AS UpdaterId,
    ur.Reputation AS UpdaterReputation,
    ur.DisplayName AS UpdaterDisplayName,
    v2.VoteCount AS Upvotes,
    v3.VoteCount AS Downvotes,
    bm.Name AS BadgeName,
    bm.Date AS BadgeDate,
    L2.Name AS LinkedTypeName
  FROM RecentActivePosts rap
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS VoteCount
    FROM Votes
    WHERE VoteTypeId = 2
    GROUP BY UserId
  ) v2 ON v2.UserId = rap.OwnerUserId
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS VoteCount
    FROM Votes
    WHERE VoteTypeId = 3
    GROUP BY UserId
  ) v3 ON v3.UserId = rap.OwnerUserId
  LEFT JOIN UserReputationHash ur ON ur.UserId = rap.OwnerUserId
  LEFT JOIN Badges bm ON bm.UserId = rap.OwnerUserId AND bm.Class = 1
  LEFT JOIN (
    SELECT Id, Name
    FROM LinkTypes
  ) L2 ON L2.Id = (SELECT MAX(LinkTypeId) FROM PostLinks pl WHERE pl.PostId = rap.PostId)
  WHERE rap.rn_type = 1
),
CorrelatedSubquery AS (
  SELECT
    jp.*,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = jp.PostId) AS CommentCountTotal,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = jp.OwnerUserId AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '365 days') AS AvgOwnerScoreYear
  FROM JoinedPosts jp
),
WindowAggregates AS (
  SELECT
    cs.*,
    SUM(cs.Upvotes) OVER (PARTITION BY cs.OwnerUserId ORDER BY cs.LastActivityDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS Upvotes30d,
    AVG(cs.Score) OVER (PARTITION BY cs.OwnerUserId) AS AvgUserScore
  FROM CorrelatedSubquery cs
),
FinalChoose AS (
  SELECT
    *
  FROM WindowAggregates
  ORDER BY LastActivityDate DESC
  LIMIT 200
)
SELECT
  fc.PostId,
  fc.Title,
  fc.OwnerUserId,
  fu.DisplayName AS OwnerDisplayName,
  fc.LastActivityDate,
  fc.Score,
  fc.ViewCount,
  fc.Tags,
  fc.CommentCount,
  fc.AnswerCount,
  fc.ParentId,
  fc.AcceptedAnswerId,
  fc.CommentCountTotal,
  fc.AvgOwnerScoreYear,
  fc.Upvotes,
  fc.Downvotes,
  fc.Upvotes30d,
  fc.AvgUserScore,
  fc.LinkedTypeName,
  fc.BadgeName,
  fc.BadgeDate
FROM FinalChoose fc
LEFT JOIN Users fu ON fu.Id = fc.OwnerUserId
ORDER BY fc.LastActivityDate DESC
;