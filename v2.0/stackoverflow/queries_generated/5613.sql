-- {"query": "5613.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 937} 
WITH filtered_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.Tags,
    p.LastActivityDate,
    p.ParentId,
    p.PostTypeId,
    COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.Score > 0
    AND p.ViewCount > 50
),
recent_activity AS (
  SELECT
    f.PostId,
    f.Title,
    f.OwnerUserId,
    f.CreationDate,
    f.LastActivityDate,
    f.ViewCount,
    f.Score,
    f.CommentCount,
    f.AnswerCount,
    f.Tags,
    ROW_NUMBER() OVER (
      PARTITION BY f.OwnerUserId
      ORDER BY f.LastActivityDate DESC
    ) AS rn_by_owner
  FROM filtered_posts f
),
owner_summary AS (
  SELECT
    ra.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    COUNT(*) AS total_questions,
    SUM(ra.ViewCount) AS total_views,
    SUM(ra.Score) AS total_score,
    MAX(ra.LastActivityDate) AS last_activity
  FROM recent_activity ra
  JOIN Users u ON ra.OwnerUserId = u.Id
  WHERE ra.rn_by_owner = 1
  GROUP BY ra.OwnerUserId, u.DisplayName
),
top_tags AS (
  SELECT
    t.TagName,
    SUM(p.Score) AS score_sum,
    COUNT(*) AS post_count
  FROM (
    SELECT
      unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
      p.Id
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) s
  JOIN Tags t ON LOWER(s.TagName) = LOWER(t.TagName)
  GROUP BY t.TagName
  ORDER BY score_sum DESC
  LIMIT 10
),
complex_metrics AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    COUNT(*) AS posted_questions,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes_given,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes_given,
    MAX(p.LastActivityDate) AS last_post_date
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName
  HAVING COUNT(*) > 0
)
SELECT
  o.UserId,
  o.UserName,
  o.total_questions,
  o.total_views,
  o.total_score,
  o.last_activity,
  ARRAY_AGG(DISTINCT tg.TagName) FILTER (WHERE tg.TagName IS NOT NULL) AS top_tags_for_user,
  cm.posted_questions,
  cm.upvotes_given,
  cm.downvotes_given,
  cm.last_post_date,
  tt.score_sum AS top_tag_score,
  tt.post_count AS top_tag_count
FROM owner_summary o
LEFT JOIN top_tags tt ON TRUE
LEFT JOIN (
  SELECT
    u.Id AS UserId,
    COUNT(*) AS posted_questions
  FROM Users u
  JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
  GROUP BY u.Id
) cm ON cm.UserId = o.UserId
LEFT JOIN (
  SELECT
    p.OwnerUserId,
    t.TagName
  FROM Posts p
  JOIN Tags t ON LOWER(t.TagName) = LOWER(unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')))
  WHERE p.PostTypeId = 1
) tg ON tg.OwnerUserId = o.UserId
GROUP BY
  o.UserId,
  o.UserName,
  o.total_questions,
  o.total_views,
  o.total_score,
  o.last_activity,
  cm.posted_questions,
  cm.upvotes_given,
  cm.downvotes_given,
  cm.last_post_date,
  tt.score_sum,
  tt.post_count
ORDER BY o.total_views DESC
LIMIT 100;