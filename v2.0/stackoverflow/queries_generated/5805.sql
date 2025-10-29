-- {"query": "5805.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 867} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.LastActivityDate >= NOW() - INTERVAL '30 days'
),
TagStats AS (
  SELECT
    t.TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews,
    MAX(p.LastActivityDate) AS MostRecentActivity
  FROM Tags t
  JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
UserInfluence AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
    SUM(CASE WHEN v.VoteTypeId IN (2) THEN 1 ELSE 0 END) AS UpvotesGiven,
    SUM(CASE WHEN v.VoteTypeId IN (3) THEN 1 ELSE 0 END) AS DownvotesGiven
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id
),
ActivityMetrics AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    COUNT(CASE WHEN c.Id IS NOT NULL THEN 1 END) AS CommentCountPost,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesPost,
    MAX(p.LastActivityDate) AS LastAct
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id, p.OwnerUserId
),
Composite AS (
  SELECT
    r.PostId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.LastActivityDate,
    r.CommentCount,
    r.FavoriteCount,
    r.PostTypeId,
    COALESCE(am.CommentCountPost, 0) AS CommentCountPost,
    COALESCE(am.UpvotesPost, 0) AS UpvotesPost,
    COALESCE(am.DownvotesPost, 0) AS DownvotesPost,
    ui.Reputation,
    ui.BadgeCount,
    ui.UpvotesGiven,
    ui.DownvotesGiven,
    ts.MostRecentActivity,
    ts.QuestionCount
  FROM RecentHot r
  LEFT JOIN ActivityMetrics am ON am.PostId = r.PostId
  LEFT JOIN UserInfluence ui ON ui.UserId = r.OwnerUserId
  LEFT JOIN TagStats ts ON ts.TagName LIKE '%' -- placeholder join to pull tag stats (will be cross applied below)
)
SELECT
  c.PostId,
  c.Title,
  c.Tags,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.OwnerUserId,
  c.LastActivityDate,
  c.CommentCountPost AS Comments,
  c.FavoriteCount,
  c.PostTypeId,
  c.Reputation,
  c.BadgeCount,
  c.UpvotesGiven,
  c.DownvotesGiven,
  c.MostRecentActivity,
  c.QuestionCount AS RelatedQuestionCount
FROM Composite c
ORDER BY c.LastActivityDate DESC
LIMIT 100;