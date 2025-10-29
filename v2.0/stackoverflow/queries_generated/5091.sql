-- {"query": "5091.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 763} 
WITH
-- A) recent activity per post with weighted score
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    -- composite activity score using multiple signals
    (COALESCE(p.Score,0) * 2
     + COALESCE(p.ViewCount,0) / 2
     + COALESCE(uv.UpvoteCount,0)
     - COALESCE(vd.DownvoteCount,0)) AS ActivityScore
  FROM Posts p
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS UpvoteCount
    FROM Votes
    WHERE VoteTypeId = 2
    GROUP BY PostId
  ) uv ON uv.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS DownvoteCount
    FROM Votes
    WHERE VoteTypeId = 3
    GROUP BY PostId
  ) vd ON vd.PostId = p.Id
  WHERE p.LastActivityDate IS NOT NULL
),
-- B) posts with heavy referencing by tags for a profiling angle
TagAffinity AS (
  SELECT
    tl.PostId,
    STRING_AGG(t.TagName, ',') AS TagsLinked
  FROM PostLinks tl
  JOIN Posts lp ON tl.RelatedPostId = lp.Id
  LEFT JOIN Tags t ON t.Id = lp.OwnerUserId -- placeholder join to gather tag-like data
  GROUP BY tl.PostId
),
-- C) a correlated subquery: for each post, last commenter details
LastCommentperPost AS (
  SELECT
    c.PostId,
    c.Text AS LatestCommentText,
    c.UserDisplayName AS Commenter,
    c.CreationDate AS CommentDate
  FROM Comments c
  JOIN (
    SELECT PostId, MAX(CreationDate) AS MaxDate
    FROM Comments
    GROUP BY PostId
  ) m ON m.PostId = c.PostId AND m.MaxDate = c.CreationDate
),
-- D) window function: rank posts by ActivityScore within each PostType
Ranked AS (
  SELECT
    ra.*,
    ROW_NUMBER() OVER (PARTITION BY PostTypeId ORDER BY ActivityScore DESC, CreationDate DESC) AS RN
  FROM RecentActivity ra
)
SELECT
  r.PostId,
  r.Title,
  r.PostTypeId,
  r.CreationDate,
  r.LastActivityDate,
  r.Score,
  r.ViewCount,
  r.OwnerUserId,
  r.ActivityScore,
  rt.Name AS PostTypeName,
  COALESCE(lc.LatestCommentText, '') AS LatestComment,
  COALESCE(lc.Commenter, '') AS LatestCommenter,
  COALESCE(lc.CommentDate, NULL) AS LatestCommentDate,
  CASE
    WHEN r.ActivityScore > 1000 THEN 'HOT'
    WHEN r.ActivityScore > 500 THEN 'WARM'
    ELSE 'NEW'
  END AS PerformanceBand,
  (CASE
     WHEN p.OwnerUserId IS NOT NULL THEN
       (SELECT Reputation FROM Users u WHERE u.Id = p.OwnerUserId)
     ELSE NULL
   END) AS OwnerReputation
FROM Ranked r
JOIN PostTypes rt ON rt.Id = r.PostTypeId
LEFT JOIN LastCommentperPost lc ON lc.PostId = r.PostId
LEFT JOIN Posts p ON p.Id = r.PostId
WHERE r.RN <= 100
ORDER BY r.ActivityScore DESC, r.LastActivityDate DESC;