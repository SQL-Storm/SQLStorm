-- {"query": "4755.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1567} 

WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      p.Score,
      p.FavoriteCount,
      p.AnswerCount,
      p.ViewCount,
      pt.Name AS PostType,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.PostTypeId
        ORDER BY
          p.CreationDate DESC
      ) AS rn,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.CreationDate >= DATE_SUB(NOW(), INTERVAL 1 YEAR)
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(p.Score) AS TotalScore,
      AVG(p.ViewCount) AS AvgViews,
      SUM(CASE WHEN p.IsClosed = 1 THEN 1 ELSE 0 END) AS ClosedPostsCount
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId <> -1
      AND p.CreationDate >= DATE_SUB(NOW(), INTERVAL 1 YEAR)
    GROUP BY
      p.OwnerUserId
  ),
  RecentComments AS (
    SELECT
      c.PostId,
      COUNT(c.Id) AS RecentCommentCount,
      MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments AS c
    WHERE
      c.CreationDate >= DATE_SUB(NOW(), INTERVAL 3 MONTH)
    GROUP BY
      c.PostId
  ),
  TagEngagement AS (
    SELECT
      p.Id AS PostId,
      COUNT(DISTINCT ph.UserId) AS DistinctEditors,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1 ELSE 0 END) AS BodyEdits,
      MAX(ph.CreationDate) AS LastEditDate
    FROM Posts AS p
    LEFT JOIN PostHistory AS ph
      ON p.Id = ph.PostId
    WHERE
      p.CreationDate >= DATE_SUB(NOW(), INTERVAL 1 YEAR)
    GROUP BY
      p.Id
  )
SELECT
  rp.PostId,
  rp.Title,
  rp.PostType,
  rp.Score,
  rp.FavoriteCount,
  rp.AnswerCount,
  rp.ViewCount,
  rp.PostCreationDate,
  COALESCE(u.DisplayName, 'Unknown User') AS OwnerDisplayName,
  COALESCE(upa.TotalPosts, 0) AS OwnerTotalPosts,
  COALESCE(upa.TotalScore, 0) AS OwnerTotalScore,
  COALESCE(upa.AvgViews, 0) AS OwnerAvgViews,
  upa.ClosedPostsCount AS OwnerClosedPosts,
  rc.RecentCommentCount,
  te.DistinctEditors,
  te.BodyEdits,
  CASE
    WHEN rp.rn <= 10 THEN 'Top 10 Most Recent'
    WHEN rp.Score > 1000 THEN 'High Score'
    WHEN rp.FavoriteCount > 50 THEN 'Highly Favorited'
    WHEN rp.AnswerCount > 20 THEN 'Popular Question'
    WHEN rp.ViewCount > 100000 THEN 'High View Count'
    ELSE 'Standard'
  END AS PostCategory,
  CASE
    WHEN rp.IsClosed = 1 THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  CASE
    WHEN rc.LatestCommentDate IS NOT NULL AND rc.LatestCommentDate > DATE_SUB(rp.PostCreationDate, INTERVAL 1 DAY) THEN 'Active Recently'
    ELSE 'Inactive Recently'
  END AS CommentActivity,
  -- Example of a complex string expression
  CONCAT(
    'Owner: ',
    COALESCE(u.DisplayName, 'N/A'),
    ' | Created: ',
    DATE_FORMAT(rp.PostCreationDate, '%Y-%m-%d %H:%i:%s'),
    ' | Score: ',
    rp.Score
  ) AS PostSummary,
  -- Example of a correlated subquery for user's last post score
  (
    SELECT
      p2.Score
    FROM Posts AS p2
    WHERE
      p2.OwnerUserId = rp.OwnerUserId
      AND p2.CreationDate < rp.PostCreationDate
    ORDER BY
      p2.CreationDate DESC
    LIMIT 1
  ) AS PreviousPostScore
FROM RankedPosts AS rp
LEFT JOIN Users AS u
  ON rp.OwnerUserId = u.Id
LEFT JOIN UserPostActivity AS upa
  ON rp.OwnerUserId = upa.OwnerUserId
LEFT JOIN RecentComments AS rc
  ON rp.PostId = rc.PostId
LEFT JOIN TagEngagement AS te
  ON rp.PostId = te.PostId
WHERE
  rp.rn <= 50 OR rp.Score > 500 -- Include top 50 recent posts or posts with score > 500
UNION ALL
SELECT
  NULL,
  '--- Summary Statistics ---',
  NULL,
  NULL,
  NULL,
  NULL,
  COUNT(*),
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL
FROM RankedPosts
WHERE
  rn <= 50 OR Score > 500
UNION ALL
SELECT
  NULL,
  'Total Posts Analyzed:',
  NULL,
  NULL,
  NULL,
  NULL,
  COUNT(*),
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL
FROM RankedPosts
WHERE
  rn <= 50 OR Score > 500
UNION ALL
SELECT
  NULL,
  'Average Score:',
  NULL,
  AVG(Score),
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL
FROM RankedPosts
WHERE
  rn <= 50 OR Score > 500
ORDER BY
  PostId DESC NULLS FIRST;
