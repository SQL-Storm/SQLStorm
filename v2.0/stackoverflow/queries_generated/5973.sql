-- {"query": "5973.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 809} 
WITH recent_questions AS (
  SELECT 
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.CreationDate >= NOW() - INTERVAL '60 days'
),
tag_stats AS (
  SELECT
    UNNEST(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag,
    COUNT(*) AS question_count,
    AVG(p.Score) AS avg_score,
    SUM(p.ViewCount) AS total_views
  FROM recent_questions rq
  GROUP BY 1
),
user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT q.PostId) AS questions_created,
    SUM(q.ViewCount) AS total_question_views,
    AVG(q.Score) AS avg_question_score,
    MAX(q.LastActivityDate) AS last_question_activity
  FROM Users u
  LEFT JOIN recent_questions q ON q.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
complex_metrics AS (
  SELECT
    rq.PostId,
    rq.Title,
    rq.CreationDate,
    rq.LastActivityDate,
    rq.Score,
    rq.ViewCount,
    rq.Tags,
    EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = rq.PostId AND v.VoteTypeId = 2) AS has_upvote,
    EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = rq.PostId AND v.VoteTypeId = 3) AS has_downvote,
    rq.FavoriteCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.PostId) AS comment_count,
    COALESCE(rq.AnswerCount, 0) AS answer_count,
    COALESCE((SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = rq.PostId AND v.VoteTypeId = 8), 0) AS avg_bounty_at_start
  FROM recent_questions rq
),
outer_join_example AS (
  SELECT
    cq.PostId,
    cq.Title,
    qq.question_count AS related_questions_in_same_tag,
    ts.avg_score AS average_question_score_for_tag,
    uu.total_question_views
  FROM complex_metrics cq
  LEFT JOIN tag_stats ts
    ON ts.tag = ANY(string_to_array(substr(cq.Tags, 2, length(cq.Tags)-2), '><'))
  LEFT JOIN user_activity uu
    ON uu.UserId = cq.OwnerUserId
  LEFT JOIN (
    SELECT tag, COUNT(*) AS question_count
    FROM tag_stats
    GROUP BY tag
  ) qq ON qq.tag = ANY(string_to_array(substr(cq.Tags, 2, length(cq.Tags)-2), '><'))
)
SELECT
  oq.PostId,
  oq.Title,
  oq.LastActivityDate,
  oq.Score,
  oq.ViewCount,
  oq.Tags,
  oc.comment_count,
  oa.answer_count,
  oa.avg_bounty_at_start,
  ua.UserId,
  ua.DisplayName AS OwnerDisplayName,
  ua.Reputation,
  ua.questions_created,
  ua.total_question_views,
  aq.related_questions_in_same_tag,
  aq.average_question_score_for_tag,
  aq.total_question_views AS owner_total_views
FROM complex_metrics oq
JOIN outer_join_example aq ON aq.PostId = oq.PostId
LEFT JOIN user_activity ua ON ua.UserId = oq.OwnerUserId
ORDER BY oq.LastActivityDate DESC
LIMIT 100;