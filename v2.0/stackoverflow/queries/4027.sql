-- {"query": "4027.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1153}
WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.Score,
      p.CommentCount,
      p.FavoriteCount,
      p.AnswerCount,
      p.CreationDate,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.FavoriteCount DESC) AS rn_score,
      DENSE_RANK() OVER (ORDER BY p.CreationDate) AS dr_creation,
      SUM(p.ViewCount) OVER (ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_views
    FROM
      Posts p
      JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.Score > 0 AND p.CommentCount > 0 AND p.FavoriteCount IS NOT NULL
  ),
  UserPostStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(p.Score) AS TotalScore,
      AVG(CAST(p.ViewCount AS DECIMAL(18, 2))) AS AvgViewCount,
      MAX(p.CreationDate) AS LastPostDate
    FROM
      Users u
      LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    WHERE
      u.Reputation > 1000
    GROUP BY
      u.Id,
      u.DisplayName
    HAVING
      COUNT(p.Id) > 5
  ),
  AggregatedComments AS (
    SELECT
      c.PostId,
      COUNT(c.Id) AS CommentCountByPost,
      AVG(CAST(c.Score AS DECIMAL(18, 2))) AS AvgCommentScore,
      MAX(c.CreationDate) AS LastCommentDate
    FROM
      Comments c
    WHERE
      c.Score > 0
    GROUP BY
      c.PostId
    HAVING
      COUNT(c.Id) >= 3
  ),
  RecentEdits AS (
    SELECT
      ph.PostId,
      COUNT(ph.Id) AS EditCount,
      MAX(ph.CreationDate) AS LastEditDate
    FROM
      PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) /* Edit Title, Edit Body, Edit Tags */
    GROUP BY
      ph.PostId
    HAVING
      COUNT(ph.Id) BETWEEN 2 AND 10
  )
SELECT
  rp.PostId,
  rp.PostTypeName,
  rp.Score,
  rp.CommentCount,
  rp.FavoriteCount,
  rp.AnswerCount,
  rp.rn_score,
  rp.dr_creation,
  rp.cumulative_views,
  ups.DisplayName AS OwnerDisplayName,
  ups.TotalPosts AS OwnerTotalPosts,
  ups.TotalScore AS OwnerTotalScore,
  ups.AvgViewCount AS OwnerAvgViewCount,
  ac.CommentCountByPost AS AggregatedCommentCount,
  ac.AvgCommentScore AS AggregatedAvgCommentScore,
  re.EditCount AS RecentEditCount,
  CASE
    WHEN rp.Score > 100 THEN 'High Score'
    WHEN rp.Score BETWEEN 50 AND 100 THEN 'Medium Score'
    ELSE 'Low Score'
  END AS ScoreCategory,
  COALESCE(u.Location, 'Unknown Location') AS UserLocation,
  CASE
    WHEN ac.LastCommentDate > rp.CreationDate THEN 'Comments after Post Creation'
    ELSE 'Comments before or on Post Creation'
  END AS CommentTiming,
  ('Post ID: ' || rp.PostId || ', Type: ' || rp.PostTypeName || ', Owner: ' || ups.DisplayName) AS PostSummaryString,
  rp.CreationDate
FROM
  RankedPosts rp
  INNER JOIN UserPostStats ups
  ON rp.OwnerUserId = ups.UserId
  LEFT JOIN AggregatedComments ac
  ON rp.PostId = ac.PostId
  LEFT JOIN RecentEdits re
  ON rp.PostId = re.PostId
  LEFT JOIN Users u
  ON rp.OwnerUserId = u.Id
WHERE
  rp.rn_score <= 100
  AND rp.cumulative_views > 1000000
  AND (
    ups.LastPostDate > (cast('2024-10-01' as date) - INTERVAL '1 year')
    OR ups.LastPostDate IS NULL
  )
  AND (
    rp.Score + rp.FavoriteCount * 5 > rp.CommentCount * 2
  )
  AND u.CreationDate < (cast('2024-10-01' as date) - INTERVAL '5 years')
GROUP BY
  rp.PostId,
  rp.PostTypeName,
  rp.Score,
  rp.CommentCount,
  rp.FavoriteCount,
  rp.AnswerCount,
  rp.rn_score,
  rp.dr_creation,
  rp.cumulative_views,
  ups.DisplayName,
  ups.TotalPosts,
  ups.TotalScore,
  ups.AvgViewCount,
  ac.CommentCountByPost,
  ac.AvgCommentScore,
  re.EditCount,
  rp.CreationDate,
  COALESCE(u.Location, 'Unknown Location'),
  ac.LastCommentDate,
  ups.UserId,
  ups.LastPostDate,
  u.Location,
  u.CreationDate
ORDER BY
  rp.rn_score,
  rp.cumulative_views DESC;