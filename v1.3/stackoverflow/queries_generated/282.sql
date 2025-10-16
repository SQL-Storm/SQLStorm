-- {"query": "282.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 5586} 
WITH
recent_posts AS (
  SELECT p.*, v.vote_up, v.vote_down
  FROM Posts p
  LEFT JOIN (
    SELECT PostId,
      SUM(CASE WHEN VoteTypeId=2 THEN 1 ELSE 0 END) as vote_up,
      SUM(CASE WHEN VoteTypeId=3 THEN 1 ELSE 0 END) as vote_down,
      SUM(1) as total_votes
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  WHERE p.CreationDate >= now() - interval '365 days'
),
tag_expanded AS (
  SELECT p.Id as PostId, lower(trim(t.tag)) as tag, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags,2, length(p.Tags)-2), '><')) as tag
  ) t
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
tag_stats AS (
  SELECT tag,
    count(*) as questions,
    sum(coalesce(ViewCount,0)) as total_views,
    avg(coalesce(Score,0))::numeric(10,3) as avg_score,
    max(Score) as max_score,
    (array_agg(PostId ORDER BY Score DESC, ViewCount DESC))[1] as top_question_id
  FROM tag_expanded
  GROUP BY tag
),
user_posts AS (
  SELECT u.Id as UserId,
    u.DisplayName,
    count(p.Id) FILTER (WHERE p.PostTypeId = 1) as question_count,
    count(p.Id) FILTER (WHERE p.PostTypeId = 2) as answer_count,
    sum(coalesce(p.Score,0)) as total_score,
    avg(coalesce(p.Score,0))::numeric(10,3) as avg_score,
    max(p.CreationDate) as last_post,
    min(p.CreationDate) as first_post,
    (case when count(p.Id) > 0 then (max(p.CreationDate) - min(p.CreationDate)) else null end) as active_span
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
badge_summary AS (
  SELECT b.UserId,
    count(*) as badges,
    sum(case when b.Class=1 then 1 else 0 end) as gold,
    sum(case when b.Class=2 then 1 else 0 end) as silver,
    sum(case when b.Class=3 then 1 else 0 end) as bronze,
    count(distinct case when b.TagBased = B'1' then b.Name end) as tag_badge_count
  FROM Badges b
  GROUP BY b.UserId
),
votes_agg AS (
  SELECT PostId,
    sum(case when VoteTypeId=2 then 1 else 0 end) as upvotes,
    sum(case when VoteTypeId=3 then 1 else 0 end) as downvotes,
    sum(case when VoteTypeId=5 then 1 else 0 end) as favorites,
    count(*) as total_votes
  FROM Votes
  GROUP BY PostId
),
answers_agg AS (
  SELECT ParentId as QuestionId,
    count(*) as answer_count,
    avg(coalesce(Score,0))::numeric(10,3) as avg_answer_score,
    max(Score) as max_answer_score
  FROM Posts
  WHERE ParentId IS NOT NULL
  GROUP BY ParentId
),
duplicate_links AS (
  SELECT pl.PostId, pl.RelatedPostId, pl.CreationDate
  FROM PostLinks pl
  WHERE pl.LinkTypeId = 3
),
top_users_per_tag AS (
  SELECT tag, OwnerUserId,
    sum(coalesce(Score,0)) as tag_user_score,
    count(*) as posts_in_tag,
    row_number() OVER (PARTITION BY tag ORDER BY sum(coalesce(Score,0)) DESC, count(*) DESC) as rn
  FROM tag_expanded
  GROUP BY tag, OwnerUserId
),
top_user_tag AS (
  SELECT tag, OwnerUserId, tag_user_score, posts_in_tag
  FROM top_users_per_tag
  WHERE rn = 1
),
post_edit_activity AS (
  SELECT ph.PostId,
    count(*) as edits,
    sum(case when ph.PostHistoryTypeId in (4,5,6) then 1 else 0 end) as content_edits,
    max(ph.CreationDate) as last_edit
  FROM PostHistory ph
  GROUP BY ph.PostId
),
recent_comments_snippet AS (
  SELECT DISTINCT ON (c.PostId) c.PostId,
    substring(c.Text from 1 for 120) as snippet,
    c.CreationDate
  FROM Comments c
  ORDER BY c.PostId, c.CreationDate DESC
),
active_users AS (
  SELECT Id FROM Users WHERE LastAccessDate >= now() - interval '90 days'
  UNION
  SELECT u.Id FROM Users u JOIN Posts p ON p.OwnerUserId = u.Id WHERE p.CreationDate >= now() - interval '180 days'
),
inactive_users AS (
  SELECT Id FROM Users WHERE LastAccessDate < now() - interval '365 days'
  EXCEPT
  SELECT Id FROM active_users
),
user_summary AS (
  SELECT u.Id as user_id,
    u.DisplayName,
    coalesce(up.question_count,0) as questions,
    coalesce(up.answer_count,0) as answers,
    coalesce(bs.badges,0) as badges,
    coalesce(bs.gold,0) as gold,
    coalesce(bs.silver,0) as silver,
    coalesce(bs.bronze,0) as bronze,
    coalesce(up.total_score,0) as total_post_score,
    up.last_post,
    CASE
      WHEN u.LastAccessDate IS NULL THEN 'never'
      WHEN u.LastAccessDate < now() - interval '365 days' THEN 'dormant'
      WHEN u.LastAccessDate >= now() - interval '30 days' THEN 'active'
      ELSE 'idle'
    END as activity_label,
    (SELECT count(*) FROM Votes v WHERE v.UserId = u.Id) as votes_cast,
    (SELECT sum(coalesce(Score,0)) FROM Posts p WHERE p.OwnerUserId = u.Id) as sum_scores,
    CASE WHEN u.Views IS NULL THEN 0 ELSE u.Views END as profile_views
  FROM Users u
  LEFT JOIN user_posts up ON up.UserId = u.Id
  LEFT JOIN badge_summary bs ON bs.UserId = u.Id
)
SELECT
  us.user_id,
  us.DisplayName,
  us.questions,
  us.answers,
  us.badges,
  us.gold,
  us.silver,
  us.bronze,
  us.total_post_score,
  us.last_post,
  us.activity_label,
  us.votes_cast,
  coalesce(us.sum_scores,0) as sum_scores,
  us.profile_views,
  coalesce(ts.questions,0) as top_tag_questions,
  ts.tag as tag,
  tu.OwnerUserId as top_user_in_tag,
  tu.tag_user_score,
  coalesce(a.answer_count,0) as answers_for_top_question,
  coalesce(v.upvotes,0) as upvotes_on_top_question,
  coalesce(pe.edits,0) as post_edit_count,
  coalesce(rc.snippet, '') as last_comment_snippet,
  concat(coalesce(us.DisplayName,'<deleted>'), ' | ', us.activity_label, ' | rep=', (SELECT Reputation FROM Users WHERE Id = us.user_id)) as display_summary,
  length(coalesce(rc.snippet,'')) as last_comment_length,
  CASE WHEN ts.avg_score IS NULL THEN -999 ELSE ts.avg_score END as tag_avg_score,
  rank() OVER (ORDER BY us.total_post_score DESC NULLS LAST) as user_rank_by_score
FROM user_summary us
LEFT JOIN (
  SELECT te.OwnerUserId, te.tag, count(*) as cnt
  FROM tag_expanded te
  GROUP BY te.OwnerUserId, te.tag
  HAVING count(*) > 0
  ORDER BY te.OwnerUserId, cnt DESC
) te ON te.OwnerUserId = us.user_id
LEFT JOIN LATERAL (
  SELECT ts.tag, ts.questions, ts.avg_score, ts.top_question_id
  FROM tag_stats ts
  WHERE ts.tag = te.tag
  ORDER BY ts.questions DESC
  LIMIT 1
) ts ON true
LEFT JOIN top_user_tag tu ON tu.tag = ts.tag
LEFT JOIN Posts p ON p.Id = tu.tag_user_score::int
LEFT JOIN answers_agg a ON a.QuestionId = ts.top_question_id
LEFT JOIN votes_agg v ON v.PostId = ts.top_question_id
LEFT JOIN post_edit_activity pe ON pe.PostId = ts.top_question_id
LEFT JOIN recent_comments_snippet rc ON rc.PostId = ts.top_question_id
WHERE us.user_id IS NOT NULL
ORDER BY user_rank_by_score NULLS LAST
LIMIT 250;