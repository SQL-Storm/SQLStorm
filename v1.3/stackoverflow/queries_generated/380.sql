-- {"query": "380.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 17831} 
WITH
q AS (
  SELECT p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.AcceptedAnswerId, p.Tags, p.Body
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '5 years'
),
tag_exploded AS (
  SELECT q.Id AS question_id,
         trim(t.tag) AS tag
  FROM q
  CROSS JOIN LATERAL unnest(string_to_array(COALESCE(substring(q.Tags, 2, length(q.Tags)-2), ''), '><')) AS t(tag)
),
tag_stats AS (
  SELECT tag, count(DISTINCT question_id) AS q_count, sum(p.ViewCount) AS total_views, avg(p.Score) AS avg_score
  FROM tag_exploded te
  JOIN Posts p ON p.Id = te.question_id
  GROUP BY tag
),
co_tags AS (
  SELECT t1.tag AS tag_a, t2.tag AS tag_b, COUNT(*) AS co_count
  FROM tag_exploded t1
  JOIN tag_exploded t2 ON t1.question_id = t2.question_id AND t1.tag < t2.tag
  GROUP BY t1.tag, t2.tag
),
answers AS (
  SELECT a.ParentId AS question_id, a.Id AS answer_id, a.OwnerUserId AS answerer_id, a.Score AS answer_score, a.CreationDate AS answer_creation,
         row_number() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC NULLS LAST) AS rn,
         count(*) OVER (PARTITION BY a.ParentId) AS total_answers
  FROM Posts a
  WHERE a.PostTypeId = 2
),
top_answers AS (
  SELECT * FROM answers WHERE rn <= 3
),
top_answer_1 AS (
  SELECT * FROM answers WHERE rn = 1
),
comments_agg AS (
  SELECT PostId, count(*) AS total_comments, max(Score) AS max_comment_score,
         (array_agg(Text ORDER BY Score DESC NULLS LAST))[1]::text AS top_comment_text
  FROM Comments
  GROUP BY PostId
),
votes_agg AS (
  SELECT PostId,
         sum(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
         sum(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
         sum(CASE WHEN VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted_flags,
         count(*) AS total_votes
  FROM Votes
  GROUP BY PostId
),
history_agg AS (
  SELECT PostId,
         sum(CASE WHEN PostHistoryTypeId IN (10,35,36) THEN 1 ELSE 0 END) AS close_votes,
         sum(CASE WHEN PostHistoryTypeId IN (11) THEN 1 ELSE 0 END) AS reopen_votes,
         max(CreationDate) AS last_history_date
  FROM PostHistory
  GROUP BY PostId
),
owner_badges AS (
  SELECT UserId,
         count(*) AS badge_count,
         sum(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold_count,
         sum(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS silver_count,
         sum(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS bronze_count
  FROM Badges
  GROUP BY UserId
),
acceptance_times AS (
  SELECT q.Id AS question_id, a.Id AS accepted_answer_id, a.OwnerUserId AS accepted_answerer_id,
         extract(epoch FROM (a.CreationDate - q.CreationDate))/3600.0 AS hours_to_accept
  FROM Posts q
  JOIN Posts a ON q.AcceptedAnswerId = a.Id
  WHERE q.AcceptedAnswerId IS NOT NULL
),
question_base AS (
  SELECT q.Id AS question_id, q.Title, q.OwnerUserId AS owner_id, u.DisplayName AS owner_display_name, u.Reputation AS owner_reputation,
         q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.AcceptedAnswerId,
         coalesce(ob.badge_count,0) AS owner_badge_count, coalesce(ob.gold_count,0) AS owner_gold_count,
         coalesce(v.upvotes,0) AS upvotes, coalesce(v.downvotes,0) AS downvotes, coalesce(v.total_votes,0) AS total_votes,
         coalesce(c.total_comments,0) AS comments, coalesce(h.close_votes,0) AS close_events,
         array_remove(array_agg(DISTINCT trim(te.tag)), NULL) AS tag_list
  FROM q
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  LEFT JOIN owner_badges ob ON ob.UserId = q.OwnerUserId
  LEFT JOIN votes_agg v ON v.PostId = q.Id
  LEFT JOIN comments_agg c ON c.PostId = q.Id
  LEFT JOIN history_agg h ON h.PostId = q.Id
  LEFT JOIN tag_exploded te ON te.question_id = q.Id
  GROUP BY q.Id, q.Title, q.OwnerUserId, u.DisplayName, u.Reputation, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.AcceptedAnswerId, ob.badge_count, ob.gold_count, v.upvotes, v.downvotes, v.total_votes, c.total_comments, h.close_votes
),
question_ranks AS (
  SELECT qb.*,
         row_number() OVER (ORDER BY qb.ViewCount DESC NULLS LAST, qb.Score DESC NULLS LAST) AS global_rank,
         dense_rank() OVER (PARTITION BY qb.owner_id ORDER BY qb.ViewCount DESC) AS rank_within_owner
  FROM question_base qb
),
correlated_metrics AS (
  SELECT qr.*,
         (SELECT count(*) FROM Posts p2 WHERE p2.OwnerUserId = qr.owner_id AND p2.CreationDate >= qr.CreationDate - INTERVAL '1 year') AS owner_posts_last_year,
         (SELECT count(*) FROM Posts p3 WHERE p3.OwnerUserId = qr.owner_id AND p3.Score > qr.Score) AS owner_posts_with_higher_score,
         (SELECT count(*) FROM PostLinks pl WHERE pl.RelatedPostId = qr.question_id AND pl.LinkTypeId = 3) AS duplicate_count,
         (SELECT count(*) FROM PostLinks pl WHERE pl.PostId = qr.question_id AND pl.LinkTypeId = 1) AS outbound_links_count
  FROM question_ranks qr
),
final_enriched AS (
  SELECT cm.*,
         at.hours_to_accept,
         ta.answer_id AS best_answer_id, ta.answerer_id AS best_answerer_id, ta.answer_score AS best_answer_score,
         array_to_string(cm.tag_list, ',') AS tag_csv
  FROM correlated_metrics cm
  LEFT JOIN acceptance_times at ON at.question_id = cm.question_id
  LEFT JOIN top_answer_1 ta ON ta.question_id = cm.question_id
)
(
  SELECT
    fe.question_id,
    left(fe.Title, 200) AS short_title,
    fe.owner_id,
    fe.owner_display_name,
    fe.owner_reputation,
    fe.owner_badge_count,
    fe.ViewCount AS view_count,
    fe.Score AS question_score,
    fe.upvotes,
    fe.downvotes,
    fe.comments,
    fe.close_events,
    fe.best_answer_id,
    fe.best_answerer_id,
    fe.best_answer_score,
    fe.hours_to_accept,
    fe.owner_posts_last_year,
    fe.owner_posts_with_higher_score,
    fe.duplicate_count,
    fe.outbound_links_count,
    fe.tag_csv,
    (coalesce(fe.ViewCount,0)::numeric * 0.2 + coalesce(fe.AnswerCount,0)::numeric * 10 + coalesce(fe.upvotes,0)::numeric * 5 - coalesce(fe.downvotes,0)::numeric * 5 + coalesce(fe.owner_reputation,0)::numeric * 0.01 - coalesce(fe.close_events,0)::numeric * 20) AS complexity_score,
    CASE
      WHEN fe.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
      WHEN fe.best_answer_id IS NOT NULL THEN 'HasTopAnswerNoAccept'
      WHEN fe.comments > 10 THEN 'Discussed'
      WHEN fe.ViewCount > 10000 THEN 'PopularNoAnswer'
      ELSE 'Other'
    END AS status_bucket
  FROM final_enriched fe
  WHERE (fe.ViewCount > 5000 OR fe.upvotes > 50 OR fe.owner_reputation > 10000)
  ORDER BY complexity_score DESC
  LIMIT 200
)
UNION ALL
(
  SELECT
    p.Id AS question_id,
    left(p.Title,200) AS short_title,
    p.OwnerUserId AS owner_id,
    u.DisplayName AS owner_display_name,
    u.Reputation AS owner_reputation,
    coalesce(ob.badge_count,0) AS owner_badge_count,
    p.ViewCount AS view_count,
    p.Score AS question_score,
    coalesce(v.upvotes,0) AS upvotes,
    coalesce(v.downvotes,0) AS downvotes,
    coalesce(c.total_comments,0) AS comments,
    coalesce(h.close_votes,0) AS close_events,
    ta.answer_id AS best_answer_id,
    ta.answerer_id AS best_answerer_id,
    ta.answer_score AS best_answer_score,
    at.hours_to_accept,
    (SELECT count(*) FROM Posts p2 WHERE p2.OwnerUserId = p.OwnerUserId AND p2.CreationDate >= p.CreationDate - INTERVAL '1 year') AS owner_posts_last_year,
    (SELECT count(*) FROM Posts p3 WHERE p3.OwnerUserId = p.OwnerUserId AND p3.Score > p.Score) AS owner_posts_with_higher_score,
    (SELECT count(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 3) AS duplicate_count,
    (SELECT count(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS outbound_links_count,
    COALESCE((SELECT string_agg(DISTINCT te.tag, ',') FROM tag_exploded te WHERE te.question_id = p.Id), 'no-tags') AS tag_csv,
    (coalesce(p.ViewCount,0)::numeric * 0.2 + coalesce(p.AnswerCount,0)::numeric * 10 + coalesce(v.upvotes,0)::numeric * 5 - coalesce(v.downvotes,0)::numeric * 5 + coalesce(u.Reputation,0)::numeric * 0.01 - coalesce(h.close_votes,0)::numeric * 20) AS complexity_score,
    CASE
      WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
      WHEN ta.answer_id IS NOT NULL THEN 'HasTopAnswerNoAccept'
      WHEN coalesce(c.total_comments,0) > 10 THEN 'Discussed'
      WHEN p.ViewCount > 10000 THEN 'PopularNoAnswer'
      ELSE 'Other'
    END AS status_bucket
  FROM Posts p
  LEFT JOIN votes_agg v ON v.PostId = p.Id
  LEFT JOIN comments_agg c ON c.PostId = p.Id
  LEFT JOIN history_agg h ON h.PostId = p.Id
  LEFT JOIN owner_badges ob ON ob.UserId = p.OwnerUserId
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN acceptance_times at ON at.question_id = p.Id
  LEFT JOIN top_answer_1 ta ON ta.question_id = p.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '10 years'
    AND coalesce(v.downvotes,0) > 10
    AND coalesce(v.downvotes,0) > coalesce(v.upvotes,0)
  ORDER BY (coalesce(v.downvotes,0)::numeric / NULLIF(GREATEST(coalesce(v.upvotes,0),1),0)) DESC
  LIMIT 100
);