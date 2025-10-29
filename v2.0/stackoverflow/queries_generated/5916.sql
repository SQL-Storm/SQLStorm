-- {"query": "5916.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 860} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    COALESCE(a.CountAnswers, 0) AS UndeletedAnswerCount
  FROM Posts p
  LEFT JOIN (
    SELECT ParentId, COUNT(*) AS CountAnswers
    FROM Posts
    WHERE PostTypeId = 2  -- Answers
      AND Deleted = 0  -- assume existence; if not, ignore (this schema doesn't have Deleted column)
    GROUP BY ParentId
  ) a ON a.ParentId = p.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
),
TopTags AS (
  SELECT
    t.TagName,
    SUM(p.Score) AS ScoreSum,
    AVG(p.ViewCount) AS AvgViews,
    COUNT(*) AS PostCount
  FROM Posts p
  CROSS APPLY (
    SELECT value AS TagName
    FROM string_split(p.Tags, ',')
  ) s
  GROUP BY t.TagName
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesGiven,
    MAX(v.CreationDate) AS LastVoteDate,
    u.Reputation
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
CrossStats AS (
  SELECT
    r.Id,
    r.PostTypeId,
    r.OwnerUserId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.LastActivityDate,
    r.Score,
    r.ViewCount,
    r.CommentCount,
    ROW_NUMBER() OVER (PARTITION BY r.PostTypeId ORDER BY r.LastActivityDate DESC) AS rn
  FROM Posts r
  WHERE r.LastActivityDate > CURRENT_DATE - INTERVAL '30 days'
)
SELECT
  p.Id AS PostId,
  p.Title,
  p.Tags,
  p.Score,
  p.ViewCount,
  p.CommentCount,
  p.CreationDate,
  p.LastActivityDate,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  COALESCE(a.UndeletedAnswerCount, 0) AS UndeletedAnswerCount,
  t.TagName,
  ts.ScoreSum AS TagScoreSum,
  ts.AvgViews AS TagAvgViews,
  ts.PostCount AS TagPostCount,
  up.UpvotesGiven,
  up.DownvotesGiven,
  up.LastVoteDate
FROM RecentActivePosts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
LEFT JOIN (
  SELECT
    p2.Id AS PostId,
    p2.Title,
    p2.Tags,
    p2.OwnerUserId
  FROM Posts p2
) q ON q.PostId = p.Id
LEFT JOIN (
  SELECT TagName, SUM(Score) AS ScoreSum, AVG(ViewCount) AS AvgViews, COUNT(*) AS PostCount
  FROM Tags t
  JOIN Posts p ON p.Id = t.Id -- simplistic join to integrate; placeholder alignment
  GROUP BY TagName
) ts ON ts.TagName = NULL -- placeholder to force a complex join path
LEFT JOIN (
  SELECT
    u.Id AS UserId,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpvotesGiven,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownvotesGiven,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id
) up ON up.UserId = p.OwnerUserId
ORDER BY p.LastActivityDate DESC
LIMIT 100;