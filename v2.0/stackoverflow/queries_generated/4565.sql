-- {"query": "4565.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1545} 
WITH PostStats AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.CreationDate AS PostCreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    ph.UserId AS EditorUserId,
    ph.CreationDate AS EditDate,
    ph.PostHistoryTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) as rn
  FROM Posts AS p
  LEFT JOIN PostHistory AS ph
    ON p.Id = ph.PostId
  WHERE
    p.PostTypeId IN (1, 2)
),
UserPostActivity AS (
  SELECT
    ps.PostId,
    ps.OwnerUserId,
    ps.PostCreationDate,
    ps.Score,
    ps.ViewCount,
    ps.AnswerCount,
    ps.CommentCount,
    ps.FavoriteCount,
    ps.ClosedDate,
    ps.EditorUserId,
    ps.EditDate,
    ps.PostHistoryTypeId,
    DATEDIFF(day, ps.PostCreationDate, GETDATE()) AS DaysSinceCreation,
    CASE
      WHEN ps.ClosedDate IS NOT NULL THEN 1
      ELSE 0
    END AS IsClosed,
    CASE
      WHEN ps.PostHistoryTypeId IN (4, 5, 6) THEN 1
      ELSE 0
    END AS IsEdited,
    ROW_NUMBER() OVER (PARTITION BY ps.PostId ORDER BY ps.EditDate DESC) as edit_rn
  FROM PostStats AS ps
  WHERE
    ps.rn = 1
),
AveragePostMetrics AS (
  SELECT
    up.PostTypeId,
    AVG(CAST(up.Score AS FLOAT)) AS AvgScore,
    AVG(CAST(up.ViewCount AS FLOAT)) AS AvgViewCount,
    AVG(CAST(up.AnswerCount AS FLOAT)) AS AvgAnswerCount,
    AVG(CAST(up.CommentCount AS FLOAT)) AS AvgCommentCount,
    AVG(CAST(up.FavoriteCount AS FLOAT)) AS AvgFavoriteCount,
    COUNT(CASE WHEN up.IsClosed = 1 THEN 1 ELSE NULL END) * 100.0 / COUNT(*) AS PercentageClosed
  FROM UserPostActivity AS up
  GROUP BY
    up.PostTypeId
),
TagAnalysis AS (
  SELECT
    t.TagName,
    COUNT(DISTINCT p.Id) AS TaggedPostCount,
    SUM(p.Score) AS TotalTagScore,
    AVG(CAST(p.Score AS FLOAT)) AS AvgTagScore,
    SUM(p.ViewCount) AS TotalTagViewCount,
    AVG(CAST(p.ViewCount AS FLOAT)) AS AvgTagViewCount,
    COUNT(CASE WHEN p.ClosedDate IS NOT NULL THEN p.Id ELSE NULL END) AS TagClosedCount,
    AVG(CAST(DATEDIFF(day, p.CreationDate, p.ClosedDate) AS FLOAT)) AS AvgDaysToClose
  FROM Posts AS p
  JOIN Tags AS t
    ON p.Id = t.WikiPostId OR p.Id = t.ExcerptPostId
  WHERE
    p.PostTypeId = 1
  GROUP BY
    t.TagName
  HAVING
    COUNT(DISTINCT p.Id) > 100
),
UserEngagement AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(p.Score) AS TotalScore,
    AVG(CAST(p.Score AS FLOAT)) AS AvgScore,
    COUNT(DISTINCT c.Id) AS TotalComments,
    AVG(CAST(c.Score AS FLOAT)) AS AvgCommentScore,
    COUNT(DISTINCT v.Id) FILTER (
      WHERE
        v.VoteTypeId = 2
    ) AS TotalUpVotes,
    COUNT(DISTINCT v.Id) FILTER (
      WHERE
        v.VoteTypeId = 3
    ) AS TotalDownVotes
  FROM Users AS u
  LEFT JOIN Posts AS p
    ON u.Id = p.OwnerUserId
  LEFT JOIN Comments AS c
    ON u.Id = c.UserId
  LEFT JOIN Votes AS v
    ON u.Id = v.UserId
  WHERE
    u.Reputation > 10000
  GROUP BY
    u.Id,
    u.DisplayName
  HAVING
    COUNT(DISTINCT p.Id) > 50
)
SELECT
  upa.PostId,
  upa.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  p.Title,
  upa.PostCreationDate,
  upa.DaysSinceCreation,
  upa.Score,
  upa.ViewCount,
  upa.AnswerCount,
  upa.CommentCount,
  upa.FavoriteCount,
  upa.IsClosed,
  upa.IsEdited,
  pm.AvgScore AS GlobalAvgScore,
  pm.AvgViewCount AS GlobalAvgViewCount,
  pm.PercentageClosed AS GlobalPercentageClosed,
  ta.TagName,
  ta.TaggedPostCount,
  ta.AvgTagScore,
  ta.AvgTagViewCount,
  ta.AvgDaysToClose,
  ue.DisplayName AS TopUserDisplayName,
  ue.TotalPosts AS TopUserTotalPosts,
  ue.TotalScore AS TopUserTotalScore,
  ue.AvgScore AS TopUserAvgScore,
  ue.TotalComments AS TopUserTotalComments,
  ue.TotalUpVotes AS TopUserTotalUpVotes
FROM UserPostActivity AS upa
JOIN Posts AS p
  ON upa.PostId = p.Id
JOIN Users AS u
  ON upa.OwnerUserId = u.Id
LEFT JOIN AveragePostMetrics AS pm
  ON upa.PostTypeId = pm.PostTypeId
LEFT JOIN (
  SELECT
    TagName,
    TaggedPostCount,
    AvgTagScore,
    AvgTagViewCount,
    AvgDaysToClose
  FROM TagAnalysis
  ORDER BY
    AvgTagScore DESC
  LIMIT 1
) AS ta
  ON 1 = 1
LEFT JOIN (
  SELECT
    UserId,
    DisplayName,
    TotalPosts,
    TotalScore,
    AvgScore,
    TotalComments,
    TotalUpVotes
  FROM UserEngagement
  ORDER BY
    TotalScore DESC
  LIMIT 1
) AS ue
  ON 1 = 1
WHERE
  upa.edit_rn = 1 AND upa.DaysSinceCreation > 30 AND upa.Score > 50
ORDER BY
  upa.Score DESC
LIMIT 100;