WITH RankedPostEdits AS (
  SELECT
    ph.PostId,
    ph.UserId,
    ph.CreationDate,
    ph.PostHistoryTypeId,
    ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPostsCreated,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCount,
    AVG(p.Score) AS AveragePostScore,
    COUNT(DISTINCT c.Id) AS TotalCommentsMade,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven,
    MAX(p.CreationDate) AS LastPostCreationDate
  FROM Users u
  LEFT JOIN Posts p
    ON u.Id = p.OwnerUserId
  LEFT JOIN Comments c
    ON u.Id = c.UserId
  LEFT JOIN Votes v
    ON u.Id = v.UserId
  WHERE u.CreationDate >= DATE '2010-01-01'
  GROUP BY
    u.Id,
    u.DisplayName
),
PostEditQuality AS (
  SELECT
    rpe.PostId,
    rpe.UserId,
    rpe.CreationDate,
    CASE
      WHEN rpe.PostHistoryTypeId = 4 THEN 'Title Edit'
      WHEN rpe.PostHistoryTypeId = 5 THEN 'Body Edit'
      WHEN rpe.PostHistoryTypeId = 6 THEN 'Tags Edit'
      ELSE 'Unknown Edit Type'
    END AS EditType,
    p.Score AS PostScoreBeforeEdit,
    CASE
      WHEN p.Score > 0 THEN 'Positive Score'
      WHEN p.Score < 0 THEN 'Negative Score'
      ELSE 'Zero Score'
    END AS PostScoreCategory,
    rpe.rn
  FROM RankedPostEdits rpe
  JOIN Posts p
    ON rpe.PostId = p.Id
  WHERE rpe.rn = 1
),
CommunityFlagging AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId AS OwnerUserId,
    COUNT(DISTINCT pf.Id) AS NumberOfFlags
  FROM Posts p
  JOIN Votes pf
    ON p.Id = pf.PostId
  WHERE
    pf.VoteTypeId IN (4, 10, 12)
    AND pf.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
  GROUP BY
    p.Id,
    p.OwnerUserId
  HAVING
    COUNT(DISTINCT pf.Id) > 5
)
SELECT
  ua.DisplayName,
  ua.TotalPostsCreated,
  ua.QuestionsCount,
  ua.AnswersCount,
  ua.AveragePostScore,
  ua.TotalCommentsMade,
  ua.TotalUpvotesGiven,
  ua.TotalDownvotesGiven,
  CASE
    WHEN ua.LastPostCreationDate < (cast('2024-10-01' as date) - INTERVAL '3 month') THEN 'Inactive'
    WHEN ua.LastPostCreationDate < (cast('2024-10-01' as date) - INTERVAL '1 month') THEN 'Moderately Active'
    ELSE 'Very Active'
  END AS UserActivityLevel,
  COALESCE(peq.EditType, 'No Recent Edits') AS LatestEditType,
  peq.PostScoreCategory AS ScoreCategoryOfLastEditedPost,
  CASE
    WHEN cf.NumberOfFlags IS NOT NULL THEN 'Flagged'
    ELSE 'Not Flagged'
  END AS CommunityFlaggingStatus,
  CASE
    WHEN POSITION('SQL' IN COALESCE(u.AboutMe, '')) > 0 THEN 'SQL Enthusiast'
    WHEN POSITION('performance' IN COALESCE(u.AboutMe, '')) > 0 THEN 'Performance Focused'
    ELSE 'General User'
  END AS UserInterestCategory,
  LENGTH(COALESCE(u.AboutMe, '')) AS AboutMeLength,
  (EXTRACT(YEAR FROM u.CreationDate) - EXTRACT(YEAR FROM u.LastAccessDate)) AS YearsSinceLastAccess,
  CASE
    WHEN p_count.TotalPosts IS NULL THEN 0
    ELSE ROUND(CAST(p_count.TotalPosts AS DECIMAL) / NULLIF(ua.TotalPostsCreated, 0), 2)
  END AS RatioOfPostsWithMoreThan100Score,
  COALESCE(p_count.TotalPosts, 0) AS PostsWithMoreThan100Score
FROM UserActivity ua
LEFT JOIN Users u
  ON ua.UserId = u.Id
LEFT JOIN PostEditQuality peq
  ON ua.UserId = peq.UserId AND peq.rn = 1
LEFT JOIN CommunityFlagging cf
  ON ua.UserId = cf.OwnerUserId
LEFT JOIN (
  SELECT
    OwnerUserId,
    COUNT(*) AS TotalPosts
  FROM Posts
  WHERE
    Score > 100
  GROUP BY
    OwnerUserId
) p_count
  ON ua.UserId = p_count.OwnerUserId
WHERE
  ua.TotalPostsCreated > 50
  AND ua.AveragePostScore > 5
GROUP BY
  ua.DisplayName,
  ua.TotalPostsCreated,
  ua.QuestionsCount,
  ua.AnswersCount,
  ua.AveragePostScore,
  ua.TotalCommentsMade,
  ua.TotalUpvotesGiven,
  ua.TotalDownvotesGiven,
  ua.LastPostCreationDate,
  peq.EditType,
  peq.PostScoreCategory,
  cf.NumberOfFlags,
  u.AboutMe,
  u.CreationDate,
  u.LastAccessDate,
  p_count.TotalPosts
ORDER BY
  ua.AveragePostScore DESC,
  ua.TotalPostsCreated DESC
LIMIT 100;