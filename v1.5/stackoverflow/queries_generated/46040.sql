-- {"query": "46040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1861}

WITH RECURSIVE user_influence AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COUNT(DISTINCT p.Id) as total_posts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as question_count,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answer_count,
    AVG(p.Score) as avg_post_score,
    SUM(p.ViewCount) as total_views
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE u.CreationDate >= '2020-01-01' 
    AND u.Reputation > 1000
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
  HAVING COUNT(DISTINCT p.Id) > 5
),
tag_expertise AS (
  SELECT 
    p.OwnerUserId,
    UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag_name,
    COUNT(*) as tag_post_count,
    AVG(p.Score) as tag_avg_score,
    SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) as questions_with_accepted_answers
  FROM Posts p
  WHERE p.PostTypeId = 1 
    AND p.Tags IS NOT NULL
    AND p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId, tag_name
),
top_tag_experts AS (
  SELECT 
    te.OwnerUserId,
    te.tag_name,
    te.tag_post_count,
    te.tag_avg_score,
    ROW_NUMBER() OVER (PARTITION BY te.tag_name ORDER BY te.tag_avg_score DESC, te.tag_post_count DESC) as expert_rank
  FROM tag_expertise te
  INNER JOIN Tags t ON t.TagName = te.tag_name
  WHERE t.Count > 100
),
answer_network AS (
  SELECT 
    q.OwnerUserId as question_owner,
    a.OwnerUserId as answer_owner,
    COUNT(*) as interaction_count,
    AVG(a.Score) as avg_answer_score,
    SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) as accepted_count
  FROM Posts q
  INNER JOIN Posts a ON q.Id = a.ParentId
  WHERE q.PostTypeId = 1 
    AND a.PostTypeId = 2
    AND q.OwnerUserId IS NOT NULL 
    AND a.OwnerUserId IS NOT NULL
    AND q.OwnerUserId != a.OwnerUserId
  GROUP BY q.OwnerUserId, a.OwnerUserId
),
engagement_metrics AS (
  SELECT 
    p.Id as post_id,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    COUNT(DISTINCT v.Id) as vote_count,
    COUNT(DISTINCT c.Id) as actual_comment_count,
    COUNT(DISTINCT pl.Id) as link_count,
    COUNT(DISTINCT ph.Id) as edit_count,
    EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate))/86400.0 as activity_duration_days
  FROM Posts p
  LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3, 5)
  LEFT JOIN Comments c ON p.Id = c.PostId
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
  WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= '2019-01-01'
  GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.CommentCount, p.LastActivityDate, p.CreationDate
)
SELECT 
  ui.DisplayName,
  ui.Reputation,
  ui.total_posts,
  ui.question_count,
  ui.answer_count,
  ROUND(ui.avg_post_score::numeric, 2) as avg_score,
  ui.total_views,
  COUNT(DISTINCT tte.tag_name) FILTER (WHERE tte.expert_rank <= 10) as top_10_tags_count,
  STRING_AGG(DISTINCT tte.tag_name, ', ') FILTER (WHERE tte.expert_rank <= 3) as top_expertise_tags,
  COUNT(DISTINCT an_giving.answer_owner) as unique_answerers_helped,
  COUNT(DISTINCT an_receiving.question_owner) as unique_questioners_helped,
  COALESCE(SUM(an_receiving.accepted_count), 0) as total_accepted_answers_given,
  ROUND(AVG(em.vote_count)::numeric, 2) as avg_votes_per_post,
  ROUND(AVG(em.actual_comment_count)::numeric, 2) as avg_comments_per_post,
  ROUND(AVG(em.activity_duration_days)::numeric, 2) as avg_post_activity_days,
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY em.Score)::numeric, 2) as median_post_score,
  MAX(em.ViewCount) as max_post_views,
  COUNT(DISTINCT b.Id) as total_badges,
  COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) as gold_badges,
  COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) as silver_badges,
  COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) as bronze_badges,
  ROUND(
    (ui.total_posts * 10 + 
     COALESCE(SUM(an_receiving.accepted_count), 0) * 50 + 
     ui.total_views / 100.0 + 
     COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) * 100)::numeric, 
    2
  ) as influence_score
FROM user_influence ui
LEFT JOIN top_tag_experts tte ON ui.Id = tte.OwnerUserId
LEFT JOIN answer_network an_giving ON ui.Id = an_giving.question_owner
LEFT JOIN answer_network an_receiving ON ui.Id = an_receiving.answer_owner
LEFT JOIN engagement_metrics em ON ui.Id = em.OwnerUserId
LEFT JOIN Badges b ON ui.Id = b.UserId
GROUP BY 
  ui.Id, ui.DisplayName, ui.Reputation, ui.total_posts, ui.question_count, 
  ui.answer_count, ui.avg_post_score, ui.total_views
HAVING COUNT(DISTINCT tte.tag_name) FILTER (WHERE tte.expert_rank <= 10) >= 2
ORDER BY influence_score DESC, ui.Reputation DESC
LIMIT 100;
