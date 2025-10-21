-- {"query": "20004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1347} 

WITH UserActivitySummary AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Location,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    SUM(p.Score) AS TotalPostScore,
    SUM(p.FavoriteCount) AS TotalFavorites,
    (
      SELECT COUNT(*)
      FROM Comments c
      WHERE c.UserId = u.Id
    ) AS CommentCount,
    (
      SELECT MAX(ph.CreationDate)
      FROM PostHistory ph
      WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (5, 8) -- Edit Body, Rollback Body
    ) AS LastBodyEditDate
  FROM
    Users u
  LEFT JOIN
    Posts p ON u.Id = p.OwnerUserId
  WHERE
    u.Reputation > 1000 AND u.AboutMe IS NOT NULL
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
RankedPostsByUser AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Score,
    p.CreationDate,
    p.Tags,
    -- Rank user's posts by score
    ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) as PostRank,
    -- Time difference between a user's consecutive posts
    EXTRACT(EPOCH FROM (p.CreationDate - LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ASC))) / 3600.0 AS HoursSinceLastPost,
    -- Average score of all posts by this user
    AVG(p.Score) OVER(PARTITION BY p.OwnerUserId) AS UserAvgPostScore
  FROM
    Posts p
  WHERE
    p.OwnerUserId IS NOT NULL AND p.CommunityOwnedDate IS NULL
)
-- Main Query: Find influential users and analyze their top-performing content and activity patterns
SELECT
  uas.UserId,
  uas.DisplayName,
  uas.Reputation,
  uas.Location,
  uas.QuestionCount,
  uas.AnswerCount,
  uas.CommentCount,
  -- Calculate a custom "Influence Score"
  (uas.Reputation * 0.4 + uas.TotalPostScore * 0.3 + uas.TotalFavorites * 0.2 + uas.CommentCount * 0.1) / (EXTRACT(EPOCH FROM (NOW() - uas.CreationDate))/(3600*24*30) + 1) AS MonthlyInfluenceScore,
  rpu.PostId AS TopPostId,
  rpu.Score AS TopPostScore,
  rpu.Tags AS TopPostTags,
  rpu.HoursSinceLastPost AS TopPostHoursSincePrevious,
  -- Check if the user's top post is an answer to a question with a linked duplicate
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM PostLinks pl
      JOIN Posts q ON rpu.PostId = q.AcceptedAnswerId OR rpu.PostId = q.ParentId
      WHERE (pl.PostId = q.Id OR pl.RelatedPostId = q.Id) AND pl.LinkTypeId = 3 -- Duplicate
    ) THEN 'Yes'
    ELSE 'No'
  END AS TopPostAnswersDuplicateQuestion,
  -- Categorize user based on their primary activity (asking vs answering)
  CASE
    WHEN uas.AnswerCount > uas.QuestionCount * 1.5 THEN 'Primary Answerer'
    WHEN uas.QuestionCount > uas.AnswerCount * 1.5 THEN 'Primary Questioner'
    ELSE 'Balanced Contributor'
  END AS UserProfile,
  -- Analyze their location string
  REVERSE(SUBSTRING(REVERSE(COALESCE(uas.Location, 'Unknown')), 1, 15)) AS LocationFragment
FROM
  UserActivitySummary uas
JOIN
  RankedPostsByUser rpu ON uas.UserId = rpu.OwnerUserId AND rpu.PostRank = 1 -- Join on the user's highest-scored post
LEFT JOIN
  Badges b ON uas.UserId = b.UserId AND b.Name = 'Fanatic' -- Check for a specific difficult badge
WHERE
  uas.LastBodyEditDate > (uas.CreationDate + INTERVAL '1 year') -- User was still editing posts at least a year after joining
  AND uas.AnswerCount > 10
  AND b.Id IS NULL -- Filter for influential users who are NOT "Fanatics"
UNION ALL
-- Combine with a different set of users: those with moderator-only tags in their posts
SELECT
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.Location,
  NULL, NULL, NULL,
  u.Reputation * 0.8 AS MonthlyInfluenceScore, -- Different scoring for this group
  p.Id,
  p.Score,
  p.Tags,
  NULL,
  'N/A',
  'Moderator-Tag User',
  'N/A'
FROM
  Users u
JOIN
  Posts p ON u.Id = p.OwnerUserId
JOIN
  Tags t ON p.Tags LIKE '%' || t.TagName || '%'
WHERE
  t.IsModeratorOnly = '1'
  AND u.Reputation > 50000
ORDER BY
  MonthlyInfluenceScore DESC, Reputation DESC
LIMIT 100;

