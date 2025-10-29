-- {"query": "5843.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1227} 
WITH
-- CTE to gather top users by reputation and activity window
TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
),
-- CTE to compute complex post activity metrics per user using window functions
UserActivity AS (
  SELECT
    u.UserId,
    u.DisplayName,
    -- total posts by user
    COUNT(p.Id) AS PostCount,
    -- sum of post scores for the user's posts
    SUM(COALESCE(p.Score,0)) AS ScoreSum,
    -- latest post activity per user
    MAX(p.LastActivityDate) AS LastActivity,
    -- number of questions by user
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    -- number of answers by user
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    -- average view count across user's posts
    AVG(COALESCE(p.ViewCount,0)) AS AvgViewCount,
    -- distinct tag keywords in titles (string expression + counts)
    STRING_AGG(DISTINCT CASE WHEN p.Title IS NOT NULL THEN p.Title ELSE '' END, ',') AS TitleTags
  FROM TopUsers u
  LEFT JOIN Posts p ON p.OwnerUserId = u.UserId
  GROUP BY u.UserId, u.DisplayName
),
-- Top 50 users by reputation who also have recent activity
SelectedUsers AS (
  SELECT
    ua.UserId,
    ua.DisplayName,
    ua.PostCount,
    ua.ScoreSum,
    ua.LastActivity,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.AvgViewCount,
    ua.TitleTags
  FROM UserActivity ua
  ORDER BY ua.ScoreSum DESC NULLS LAST, ua.LastActivity DESC
  LIMIT 50
),
-- Subquery: latest badges per user to create a correlated subquery flavor
UserBadges AS (
  SELECT
    b.UserId,
    b.Name AS BadgeName,
    b.Date
  FROM Badges b
  WHERE b.Class IN (1,2,3)
),
-- Complex join graph across posts, comments, and votes
PostEngagement AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    -- correlate with acceptance and related posts
    p.AcceptedAnswerId,
    p.ParentId,
    -- comment count with subquery
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    -- total upvotes/downvotes from Votes
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVotesForPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS DownVotesForPost
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.Title, p.Tags, p.CreationDate, p.LastActivityDate, p.ViewCount, p.Score, p.AcceptedAnswerId, p.ParentId
),
-- Build a rich, correlated subquery with tag extraction and NULL handling
TagRadar AS (
  SELECT
    t.TagName,
    t.Count,
    t.IsModeratorOnly,
    t.IsRequired,
    ARRAY_AGG(DISTINCT pv.PostId) FILTER (WHERE pv.PostId IS NOT NULL) AS PostsUsingTag
  FROM Tags t
  LEFT JOIN Posts pv ON pv.Tags LIKE '%' || t.TagName || '%'
  GROUP BY t.TagName, t.Count, t.IsModeratorOnly, t.IsRequired
)
SELECT
  s.UserId,
  s.DisplayName,
  s.PostCount,
  s.ScoreSum,
  s.LastActivity,
  s.QuestionCount,
  s.AnswerCount,
  s.AvgViewCount,
  s.TitleTags,
  -- Outer join to bring in a sample of recent posts by the user
  po.Id AS RecentPostId,
  po.Title AS RecentPostTitle,
  po.PostTypeId AS RecentPostType,
  po.LastActivityDate AS RecentPostActivity,
  -- Correlated subquery: count of TagRadar entries for tags in user's titles
  (SELECT COUNT(*) FROM TagRadar tr WHERE tr.TagName <> '' AND po.Title LIKE '%' || tr.TagName || '%') AS TagMatchCount,
  -- Compute a complex expression: weighted score combining activity and reputation proxy
  (COALESCE(s.PostCount,0) * 0.5 + COALESCE(s.ScoreSum,0) * 1.5 + COALESCE(s.AvgViewCount,0) * 0.2) AS CompositeMetric,
  -- NULL-aware string operation: coalesce to placeholder when TitleTags is empty
  COALESCE(s.TitleTags, 'No Titles') AS TitleTagSnapshot
FROM SelectedUsers s
LEFT JOIN LATERAL (
  SELECT p.Id, p.Title, p.PostTypeId, p.LastActivityDate
  FROM Posts p
  WHERE p.OwnerUserId = s.UserId
  ORDER BY p.LastActivityDate DESC NULLS LAST
  LIMIT 1
) po ON true
ORDER BY CompositeMetric DESC NULLS LAST, s.LastActivity DESC
LIMIT 100;