-- {"query": "5649.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 992} 
WITH RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
TagPopularity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgPostScore,
    MAX(p.ViewCount) AS MaxViews,
    MIN(p.CreationDate) AS FirstPostDate
  FROM Posts p
  CROSS APPLY STRING_SPLIT(p.Tags, '><') AS tag
  INNER JOIN Tags t ON t.TagName = tag.value
  GROUP BY t.TagName
),
UserEngagement AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT rp.PostId) AS RepliedPosts,
    SUM(COALESCE(v.BountyAmount,0)) AS TotalBounties,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast,
    MAX(p.LastActivityDate) AS LastActivePostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  GROUP BY u.Id, u.DisplayName
),
CrossJoinStats AS (
  SELECT
    up.UserId,
    up.DisplayName,
    rh.MaxViews,
    cl.FirstPostDate,
    tp.TagCount,
    tp.AvgPostScore,
    tp.MaxViews AS PeakViews
  FROM UserEngagement up
  CROSS JOIN (
    SELECT MAX(MaxViews) AS MaxViews FROM TagPopularity
  ) AS rh
  CROSS JOIN (
    SELECT MIN(FirstPostDate) AS FirstPostDate FROM TagPopularity
  ) AS cl
  CROSS JOIN TagPopularity tp
  WHERE tp.TagCount > 0
)
SELECT
  rp.Id AS PostId,
  rp.Title,
  rp.PostTypeId,
  pt.Name AS PostTypeName,
  rp.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.Score,
  rp.ViewCount,
  rp.Tags,
  rp.CommentCount,
  rp.AnswerCount,
  rp.FavoriteCount,
  rp.ParentId,
  rp.AcceptedAnswerId,
  CASE
    WHEN rp.PostTypeId = 1 THEN 'Question'
    WHEN rp.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostKind,
  CASE
    WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS Status,
  -- Complex calculation with NULL handling
  COALESCE(rp.Score, 0) + COALESCE(rp.ViewCount, 0) * 0.01 AS ScoreIndex,
  -- Window function: rank posts by LastActivityDate per day
  ROW_NUMBER() OVER (PARTITION BY DATE(rp.LastActivityDate) ORDER BY rp.LastActivityDate DESC) AS RNPerDay,
  -- Correlated subquery example: latest edit date by the post's owner
  (SELECT MAX(hl.CreationDate)
     FROM PostHistory hl
     WHERE hl.PostId = rp.Id AND hl.PostHistoryTypeId = 16 /* Community Owned */) AS LastBeenCommunityOwned,
  -- Set operation: compare with a pseudo "benchmark" set using a UNION ALL member
  CASE
    WHEN rp.Id IN (SELECT PostId FROM Posts p2 WHERE p2.OwnerUserId = rp.OwnerUserId AND p2.PostTypeId = 1)
      THEN 1
    ELSE 0
  END AS IsQuestionByOwner
FROM Posts rp
LEFT JOIN PostTypes pt ON rp.PostTypeId = pt.Id
LEFT JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN TagPopularity tp ON tp.TagName LIKE '%' || rp.Tags || '%'
LEFT JOIN (SELECT DISTINCT UserId, DisplayName FROM Users) AS u2 ON u2.UserId = rp.OwnerUserId
ORDER BY rp.LastActivityDate DESC
LIMIT 100;