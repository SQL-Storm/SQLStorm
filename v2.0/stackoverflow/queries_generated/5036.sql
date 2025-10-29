-- {"query": "5036.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 999} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.PostTypeId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.LastActivityDate,
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '180 days'
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    MAX(p.ViewCount) AS MaxViews
  FROM Tags t
  JOIN Posts p ON t.Id = p.Tags::int  -- approximate link via tag id if any; keep generic
  WHERE t.TagName IS NOT NULL
  GROUP BY t.TagName
),
InsaneMerge AS (
  SELECT
    p1.Id AS PostA,
    p2.Id AS PostB,
    p1.Title AS TitleA,
    p2.Title AS TitleB,
    p1.CreationDate AS DateA,
    p2.CreationDate AS DateB,
    p1.Score AS ScoreA,
    p2.Score AS ScoreB
  FROM Posts p1
  JOIN Posts p2 ON p1.OwnerUserId = p2.OwnerUserId AND p1.Id <> p2.Id
  WHERE p1.PostTypeId = 1 AND p2.PostTypeId = 1
    AND p1.LastActivityDate > p2.LastActivityDate
),
PostLinkage AS (
  SELECT
    pl.Id,
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    pl.CreationDate,
    p1.Title AS PostTitle,
    p2.Title AS RelatedPostTitle
  FROM PostLinks pl
  JOIN Posts p1 ON pl.PostId = p1.Id
  JOIN Posts p2 ON pl.RelatedPostId = p2.Id
  WHERE pl.LinkTypeId IN (1,3)
),
TaggedActivity AS (
  SELECT
    t.TagName,
    COUNT(p.Id) AS PostCount,
    SUM(p.ViewCount) AS TotalViews,
    SUM(p.Score) AS TotalScore
  FROM Posts p
  JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
)
SELECT
  -- a rich set of derived metrics to stress various features
  rp.PostId,
  rp.Title,
  rp.CreationDate,
  rp.ViewCount,
  rp.Score,
  rp.OwnerUserId,
  rp.PostTypeId,
  rp.Tags,
  rp.AnswerCount,
  rp.CommentCount,
  rp.LastActivityDate,
  rp.FavoriteCount,
  t.TagName AS TopTag,
  t2.AvgScore AS AvgTagPostScore,
  o.DisplayName AS OwnerName,
  u.Reputation,
  v.VoteTypeId,
  v.CreationDate AS VoteDate,
  vb.BountyAmount,
  cl.Name AS CloseReason,
  -- window functions to create rolling aggregates over recent activity
  SUM(rp.ViewCount) OVER (PARTITION BY rp.OwnerUserId ORDER BY rp.CreationDate ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) AS ViewsLast30,
  AVG(rp.Score) OVER (PARTITION BY rp.OwnerUserId) AS AvgScorePerUser,
  ROW_NUMBER() OVER (ORDER BY rp.LastActivityDate DESC) AS rn
FROM RecentActivePosts rp
LEFT JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN PostLinks pl ON pl.PostId = rp.Id
LEFT JOIN Posts p2 ON pl.RelatedPostId = p2.Id
LEFT JOIN Tags t ON p2.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN TopTags tt ON tt.TagName = t.TagName
LEFT JOIN InsaneMerge im ON rp.Id = im.PostA
LEFT JOIN CloseReasonTypes cl ON cl.Id = (SELECT TOP 1 CAST(rtp.Comment AS int) FROM PostHistory rtp WHERE rtp.PostId = rp.Id AND rtp.PostHistoryTypeId = 10 LIMIT 1)
LEFT JOIN Votes v ON v.PostId = rp.Id
LEFT JOIN Badges b ON b.UserId = rp.OwnerUserId AND b.Class = 1
LEFT JOIN (SELECT DISTINCT OwnerUserId, BountyAmount FROM Votes WHERE VoteTypeId = 8) vb ON vb.OwnerUserId = rp.OwnerUserId
WHERE rp.PostTypeId IN (1,2)
  AND rp.CreationDate >= NOW() - INTERVAL '365 days'
ORDER BY rp.LastActivityDate DESC
LIMIT 100;