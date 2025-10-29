-- {"query": "5479.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 813} 
WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
),
top_tags AS (
  SELECT
    t.TagName,
    COUNT(*) AS QCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS Views
  FROM Posts p
  JOIN LATERAL (
    SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) AS t ON TRUE
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
  ORDER BY QCount DESC
  LIMIT 10
),
recent_comments AS (
  SELECT
    c.Id AS CommentId,
    c.PostId,
    c.UserId,
    c.Text,
    c.CreationDate,
    c.Score
  FROM Comments c
  WHERE c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '7 days'
),
post_hist AS (
  SELECT
    ph.Id,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate,
    ph.UserId,
    ph.Comment
  FROM PostHistory ph
  WHERE ph.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),
popular_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.LastActivityDate
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
  ORDER BY p.ViewCount DESC
  LIMIT 50
)
SELECT
  rq.PostId,
  rq.Title AS QuestionTitle,
  rq.CreationDate AS QuestionCreated,
  rq.Score AS QuestionScore,
  rq.ViewCount AS QuestionViews,
  rq.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  rq.LastActivityDate AS LastActivity,
  rq.AnswerCount,
  rq.CommentCount,
  rq.FavoriteCount,
  ARRAY_AGG(DISTINCT t.TagName) AS TopTags,
  tc.CommentId AS RecentCommentId,
  tc.Text AS RecentCommentText,
  tc.CreationDate AS RecentCommentDate,
  ph.Id AS HistId,
  ph.PostHistoryTypeId,
  ph.CreationDate AS HistDate,
  ph.UserId AS HistUserId,
  ph.Comment AS HistComment,
  hp.Id AS RelatedPopularPostId,
  hp.Title AS RelatedPopularPostTitle,
  hp.ViewCount AS RelatedPopularPostViews
FROM recent_questions rq
LEFT JOIN LATERAL (
  SELECT unnest(string_to_array(substr(rq.Tags, 2, length(rq.Tags)-2), '><')) AS TagName
) AS t ON TRUE
LEFT JOIN Users u ON rq.OwnerUserId = u.Id
LEFT JOIN recent_comments tc ON tc.PostId = rq.PostId
LEFT JOIN post_hist ph ON ph.PostId = rq.PostId
LEFT JOIN popular_posts hp ON TRUE
GROUP BY
  rq.PostId, rq.Title, rq.CreationDate, rq.Score, rq.ViewCount, rq.OwnerUserId, u.DisplayName,
  rq.LastActivityDate, rq.AnswerCount, rq.CommentCount, rq.FavoriteCount,
  tc.CommentId, tc.Text, tc.CreationDate,
  ph.Id, ph.PostHistoryTypeId, ph.CreationDate, ph.UserId, ph.Comment,
  hp.Id, hp.Title, hp.ViewCount
ORDER BY rq.LastActivityDate DESC
LIMIT 100;