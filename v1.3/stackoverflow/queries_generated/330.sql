-- {"query": "330.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 15232} 
WITH
votes_per_post AS (
  SELECT v.PostId,
         COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS upvotes,
         COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS downvotes,
         COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS favorites,
         SUM(CASE WHEN v.VoteTypeId IN (8,9) THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS bounties,
         COUNT(*) AS total_votes
  FROM Votes v
  GROUP BY v.PostId
),
comments_per_post AS (
  SELECT c.PostId,
         COUNT(*) AS comment_count,
         MAX(c.CreationDate) AS last_comment_date
  FROM Comments c
  GROUP BY c.PostId
),
history_edits AS (
  SELECT ph.PostId,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS edit_count,
         MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS last_edit_date,
         STRING_AGG(DISTINCT COALESCE(ph.UserDisplayName,'<anon>'), ', ') AS editors
  FROM PostHistory ph
  GROUP BY ph.PostId
),
answer_stats AS (
  SELECT q.Id AS question_id,
         COUNT(a.Id) AS answer_count,
         COUNT(DISTINCT a.OwnerUserId) AS distinct_answerers,
         MIN(a.CreationDate) AS first_answer_date,
         MAX(a.CreationDate) AS last_answer_date,
         SUM(COALESCE(vp.upvotes,0) - COALESCE(vp.downvotes,0)) AS answer_net_votes,
         SUM(COALESCE(vp.total_votes,0)) AS answer_total_votes
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  LEFT JOIN votes_per_post vp ON vp.PostId = a.Id
  WHERE q.PostTypeId = 1
  GROUP BY q.Id
),
question_impact AS (
  SELECT q.Id,
         q.Title,
         q.CreationDate,
         q.Score,
         q.ViewCount,
         q.AnswerCount,
         COALESCE(vp.upvotes,0) AS q_upvotes,
         COALESCE(vp.downvotes,0) AS q_downvotes,
         COALESCE(cp.comment_count,0) AS q_comments,
         COALESCE(h.edit_count,0) AS q_edits,
         COALESCE(a_stats.answer_count,0) AS answer_count_calculated,
         a_stats.first_answer_date,
         q.Tags,
         CASE WHEN q.Tags IS NULL OR q.Tags = '' THEN ARRAY[]::text[] ELSE string_to_array(substring(q.Tags,2, length(q.Tags)-2), '><') END AS tag_array,
         (q.Score::numeric * 1.5 + COALESCE(vp.upvotes,0) * 2.0 - COALESCE(vp.downvotes,0) * 1.5
          + sqrt(GREATEST(q.ViewCount::numeric,0) + 1) * 1.2
          + sqrt(GREATEST(COALESCE(a_stats.answer_count,0),0) + 1) * 3
          + COALESCE(q.FavoriteCount,0) * 2.5
          + COALESCE(a_stats.answer_net_votes,0) * 0.8
         ) AS impact_score,
         (SELECT a.Id
          FROM Posts a
          LEFT JOIN Votes v2 ON v2.PostId = a.Id
          WHERE a.ParentId = q.Id
          GROUP BY a.Id, a.Score
          ORDER BY SUM(CASE WHEN v2.VoteTypeId = 2 THEN 1 WHEN v2.VoteTypeId = 3 THEN -1 ELSE 0 END) DESC NULLS LAST, a.Score DESC NULLS LAST
          LIMIT 1
         ) AS top_answer_id,
         (SELECT a.OwnerUserId
          FROM Posts a
          LEFT JOIN Votes v2 ON v2.PostId = a.Id
          WHERE a.ParentId = q.Id
          GROUP BY a.OwnerUserId
          ORDER BY SUM(CASE WHEN v2.VoteTypeId = 2 THEN 1 WHEN v2.VoteTypeId = 3 THEN -1 ELSE 0 END) DESC NULLS LAST
          LIMIT 1
         ) AS top_answerer_user_id,
         CASE WHEN a_stats.first_answer_date IS NOT NULL THEN EXTRACT(EPOCH FROM (a_stats.first_answer_date - q.CreationDate)) ELSE NULL END AS seconds_to_first_answer
  FROM Posts q
  LEFT JOIN votes_per_post vp ON vp.PostId = q.Id
  LEFT JOIN comments_per_post cp ON cp.PostId = q.Id
  LEFT JOIN history_edits h ON h.PostId = q.Id
  LEFT JOIN answer_stats a_stats ON a_stats.question_id = q.Id
  WHERE q.PostTypeId = 1
),
tag_exploded AS (
  SELECT qi.*,
         TRIM(t) AS tag
  FROM question_impact qi
  CROSS JOIN LATERAL (
    SELECT unnest(COALESCE(qi.tag_array, ARRAY[]::text[])) AS t
  ) x
),
tag_aggregates AS (
  SELECT te.tag,
         COUNT(*) AS questions_with_tag,
         SUM(te.impact_score) AS total_impact,
         AVG(te.impact_score) AS avg_impact,
         MAX(te.impact_score) AS max_impact,
         MIN(te.impact_score) AS min_impact,
         SUM(te.answer_count_calculated) AS total_answers,
         SUM(te.q_comments) AS total_comments,
         AVG(te.ViewCount) AS avg_views,
         MAX(te.Score) AS top_score,
         MAX(te.seconds_to_first_answer) AS max_seconds_to_first_answer
  FROM tag_exploded te
  GROUP BY te.tag
),
top_questions_per_tag AS (
  SELECT te.tag,
         te.Id AS question_id,
         te.Title,
         te.impact_score,
         te.Score,
         te.ViewCount,
         ROW_NUMBER() OVER (PARTITION BY te.tag ORDER BY te.impact_score DESC, te.ViewCount DESC, te.Score DESC) AS rk
  FROM tag_exploded te
),
shortlisted_questions AS (
  SELECT tag,
         STRING_AGG(substring(Title,1,120) || ' (id=' || question_id::text || ', impact=' || to_char(impact_score,'FM99999999990.00') || ', views=' || ViewCount::text || ')', ' || ' ORDER BY impact_score DESC) AS top_questions,
         STRING_AGG(question_id::text, ',' ORDER BY impact_score DESC) AS top_question_ids
  FROM top_questions_per_tag
  WHERE rk <= 3
  GROUP BY tag
),
promising_tags AS (
  SELECT lower(tag) AS tag_name FROM tag_aggregates WHERE total_impact > (SELECT COALESCE(AVG(total_impact),0) FROM tag_aggregates)
  INTERSECT
  SELECT lower("TagName") FROM Tags WHERE "Count" > 10
),
recent_active_users AS (
  SELECT Id AS user_id, DisplayName, Reputation, CreationDate, LastAccessDate
  FROM Users
  WHERE LastAccessDate > NOW() - INTERVAL '60 days'
),
high_reputation_users AS (
  SELECT Id AS user_id, DisplayName, Reputation, CreationDate, LastAccessDate
  FROM Users
  WHERE Reputation >= (SELECT COALESCE(AVG(Reputation),0) FROM Users) * 2
),
users_union AS (
  SELECT * FROM recent_active_users
  UNION
  SELECT * FROM high_reputation_users
),
users_with_badges AS (
  SELECT u.Id AS user_id,
         COUNT(b.Id) AS badge_count,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
         SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
         SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
         MAX(b.Date) AS last_badge_date
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id
),
candidate_users AS (
  SELECT uu.user_id, uu.DisplayName, uu.Reputation, uu.CreationDate, COALESCE(uwb.badge_count,0) AS badge_count
  FROM users_union uu
  LEFT JOIN users_with_badges uwb ON uwb.user_id = uu.user_id
),
engaged_users_per_tag AS (
  SELECT te.tag,
         cu.user_id,
         cu.DisplayName,
         cu.Reputation,
         cu.badge_count,
         COUNT(DISTINCT CASE WHEN q.OwnerUserId = cu.user_id THEN q.Id END) AS questions_authored,
         COUNT(DISTINCT CASE WHEN a.OwnerUserId = cu.user_id THEN a.Id END) AS answers_authored,
         COUNT(DISTINCT CASE WHEN cq.UserId = cu.user_id THEN cq.Id END) + COUNT(DISTINCT CASE WHEN ca.UserId = cu.user_id THEN ca.Id END) AS comments_made,
         COALESCE(SUM(COALESCE(vpq.upvotes,0) - COALESCE(vpq.downvotes,0)),0) + COALESCE(SUM(COALESCE(vpa.upvotes,0) - COALESCE(vpa.downvotes,0)),0) AS net_votes_on_user_posts,
         (COUNT(DISTINCT CASE WHEN q.OwnerUserId = cu.user_id THEN q.Id END) * 2.0
          + COUNT(DISTINCT CASE WHEN a.OwnerUserId = cu.user_id THEN a.Id END) * 3.0
          + (COUNT(DISTINCT CASE WHEN cq.UserId = cu.user_id THEN cq.Id END) + COUNT(DISTINCT CASE WHEN ca.UserId = cu.user_id THEN ca.Id END)) * 0.5
          + COALESCE(cu.badge_count,0) * 1.0
          + (COALESCE(SUM(COALESCE(vpq.upvotes,0) - COALESCE(vpq.downvotes,0)),0) + COALESCE(SUM(COALESCE(vpa.upvotes,0) - COALESCE(vpa.downvotes,0)),0)) * 0.2
         ) AS engagement_score
  FROM tag_exploded te
  CROSS JOIN candidate_users cu
  LEFT JOIN Posts q ON q.PostTypeId = 1 AND q.Id = te.Id AND q.OwnerUserId = cu.user_id
  LEFT JOIN Posts a ON a.PostTypeId = 2 AND a.ParentId = te.Id AND a.OwnerUserId = cu.user_id
  LEFT JOIN Comments cq ON cq.PostId = q.Id AND cq.UserId = cu.user_id
  LEFT JOIN Comments ca ON ca.PostId = a.Id AND ca.UserId = cu.user_id
  LEFT JOIN votes_per_post vpq ON vpq.PostId = q.Id
  LEFT JOIN votes_per_post vpa ON vpa.PostId = a.Id
  GROUP BY te.tag, cu.user_id, cu.DisplayName, cu.Reputation, cu.badge_count
),
top_engaged_users_per_tag AS (
  SELECT tag, user_id, DisplayName, engagement_score, ROW_NUMBER() OVER (PARTITION BY tag ORDER BY engagement_score DESC, Reputation DESC) AS rk
  FROM engaged_users_per_tag
),
top3_engaged_by_tag AS (
  SELECT tag,
         STRING_AGG(DisplayName || ' (id=' || user_id::text || ', score=' || to_char(engagement_score,'FM999999990.00') || ')', ' | ' ORDER BY engagement_score DESC) AS top_engaged_users
  FROM top_engaged_users_per_tag
  WHERE rk <= 3
  GROUP BY tag
)
SELECT COALESCE(t."TagName", ta.tag) AS tag,
       COALESCE(ta.questions_with_tag,0) AS questions_count,
       COALESCE(ta.total_impact,0)::numeric(18,2) AS total_impact,
       COALESCE(ta.avg_impact,0)::numeric(18,2) AS avg_impact,
       COALESCE(ta.max_impact,0)::numeric(18,2) AS max_impact,
       COALESCE(ta.total_answers,0) AS total_answers,
       COALESCE(ta.total_comments,0) AS total_comments,
       COALESCE(ta.avg_views,0)::bigint AS avg_views,
       COALESCE(sq.top_questions, '') AS top_questions,
       COALESCE(t3.top_engaged_users, '') AS top_engaged_users,
       CASE WHEN pt.tag_name IS NOT NULL THEN true ELSE false END AS is_promising,
       COALESCE(t."Count",0) AS tag_popularity_count,
       COALESCE(ta.max_seconds_to_first_answer,NULL) AS max_seconds_to_first_answer
FROM tag_aggregates ta
FULL OUTER JOIN Tags t ON lower(t."TagName") = lower(ta.tag)
LEFT JOIN shortlisted_questions sq ON lower(ta.tag) = lower(sq.tag)
LEFT JOIN top3_engaged_by_tag t3 ON lower(ta.tag) = lower(t3.tag)
LEFT JOIN promising_tags pt ON lower(ta.tag) = pt.tag_name
ORDER BY COALESCE(ta.total_impact,0) DESC NULLS LAST
LIMIT 200;