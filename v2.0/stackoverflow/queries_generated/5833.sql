-- {"query": "5833.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 936} 
WITH
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.Body,
    p.CommentCount,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '7 days'
),
TopTagActivity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPosts,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS ViewSum,
    MAX(p.LastActivityDate) AS LastActive
  FROM RecentActivity ra
  JOIN LATERAL (
    SELECT unnest(string_to_array(substring(ra.Tags, 2, length(ra.Tags)-2), '><')) AS TagName
  ) t ON TRUE
  JOIN Tags tg ON tg.TagName = t.TagName
  JOIN Posts p ON p.Id = ra.PostId
  GROUP BY t.TagName
  ORDER BY TagPosts DESC
  LIMIT 25
),
UserEngagement AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvotesGiven,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownvotesGiven,
    COUNT(DISTINCT pa.PostId) AS PostsCreated,
    SUM(COALESCE(v.BountyAmount,0)) AS TotalBountiesAwarded,
    MAX(p.LastActivityDate) AS LastActivity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Posts pa ON pa.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
CorrelatedActivity AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.CreationDate,
    ra.LastActivityDate,
    ra.OwnerUserId,
    ra.ViewCount,
    ra.Score,
    ra.Tags,
    ra.Body,
    up.Reputation AS OwnerReputation,
    up.DisplayName AS OwnerDisplayName,
    vtp.Name AS LastEditorVoteType
  FROM RecentActivity ra
  LEFT JOIN Users up ON up.Id = ra.OwnerUserId
  LEFT JOIN Votes v ON v.PostId = ra.PostId
  LEFT JOIN VoteTypes vtp ON vtp.Id = v.VoteTypeId
  WHERE ra.LastActivityDate >= NOW() - INTERVAL '30 days'
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  c.LastActivityDate,
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.OwnerReputation,
  c.ViewCount,
  c.Score,
  c.Tags,
  c.Body,
  (
    SELECT COUNT(*) FROM Comments cm
    WHERE cm.PostId = c.PostId
  ) AS CommentCount,
  (
    SELECT COUNT(*) FROM Votes wv
    WHERE wv.PostId = c.PostId AND wv.VoteTypeId = 2
  ) AS UpVotes,
  (
    SELECT COUNT(*) FROM Votes wv
    WHERE wv.PostId = c.PostId AND wv.VoteTypeId = 3
  ) AS DownVotes,
  (
    SELECT COUNT(*) FROM PostLinks pl
    WHERE pl.PostId = c.PostId
  ) AS RelatedLinks,
  (
    SELECT STRING_AGG(t.TagName, ',')
    FROM LATERAL (
      SELECT unnest(string_to_array(substring(c.Tags, 2, length(c.Tags)-2), '><')) AS TagName
    ) t
  ) AS TagList,
  (
    SELECT AVG(uv.Reputation)
    FROM Users uv
    JOIN Posts pp ON pp.OwnerUserId = uv.Id
    WHERE pp.Id = c.PostId
  ) AS AverageOwnerReputation
FROM CorrelatedActivity c
WHERE c.OwnerReputation IS NOT NULL
ORDER BY c.LastActivityDate DESC
LIMIT 100;