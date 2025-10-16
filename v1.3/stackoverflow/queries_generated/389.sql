-- {"query": "389.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 25023} 
WITH votes_per_post AS (
  SELECT v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
    SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted_by_originator,
    SUM(CASE WHEN v.VoteTypeId NOT IN (1,2,3) THEN 1 ELSE 0 END) AS other_votes,
    COUNT(*) AS total_votes
  FROM Votes v
  GROUP BY v.PostId
),
comments_latest AS (
  SELECT DISTINCT ON (c.PostId) c.PostId, c.Id AS CommentId, c.Text AS CommentText, c.CreationDate AS CommentDate
  FROM Comments c
  ORDER BY c.PostId, c.CreationDate DESC, c.Id DESC
),
comments_counts AS (
  SELECT c.PostId, COUNT(*) AS CommentCount
  FROM Comments c
  GROUP BY c.PostId
),
answers AS (
  SELECT p.Id AS AnswerId, p.ParentId AS QuestionId, p.OwnerUserId AS AnswerOwner, p.Score AS AnswerScore, p.CreationDate AS AnswerCreated
  FROM Posts p
  WHERE p.PostTypeId = 2
),
answers_agg AS (
  SELECT a.QuestionId,
    COUNT(*) AS answer_count,
    AVG(a.AnswerScore::numeric) AS avg_answer_score,
    MAX(a.AnswerScore) AS top_answer_score,
    MIN(a.AnswerScore) AS bottom_answer_score
  FROM answers a
  GROUP BY a.QuestionId
),
tagged_questions AS (
  SELECT q.Id AS QuestionId, q.Title, q.OwnerUserId, q.CreationDate AS QCreation, t.tag AS Tag
  FROM Posts q
  LEFT JOIN LATERAL (
    SELECT regexp_split_to_table(substring(q.Tags FROM 2 FOR char_length(q.Tags)-2), '><') AS tag
  ) t ON true
  WHERE q.PostTypeId = 1
),
tag_stats AS (
  SELECT
    tq.Tag,
    COUNT(*) AS questions,
    AVG(p.ViewCount::bigint) AS avg_views,
    AVG(p.Score::numeric) AS avg_score,
    SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS closed_count,
    COUNT(DISTINCT tq.OwnerUserId) AS distinct_askers,
    MAX(p.CreationDate) AS newest_question_date
  FROM tagged_questions tq
  JOIN Posts p ON p.Id = tq.QuestionId
  GROUP BY tq.Tag
),
top_posts_per_tag AS (
  SELECT
    tq.Tag,
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    ROW_NUMBER() OVER (PARTITION BY tq.Tag ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) AS rn
  FROM tagged_questions tq
  JOIN Posts p ON p.Id = tq.QuestionId
),
tag_top3 AS (
  SELECT Tag, jsonb_agg(jsonb_build_object('PostId', PostId, 'Title', left(Title,120), 'Score', COALESCE(Score,0), 'Views', COALESCE(ViewCount,0)) ORDER BY PostId) FILTER (WHERE rn <= 3) AS top3
  FROM top_posts_per_tag
  GROUP BY Tag
),
duplicate_roots AS (
  SELECT pl.PostId, pl.RelatedPostId, ARRAY[pl.PostId, pl.RelatedPostId] AS path, 1 AS depth
  FROM PostLinks pl
  WHERE pl.LinkTypeId = 3
  UNION ALL
  SELECT dr.PostId, pl.RelatedPostId, dr.path || array[pl.RelatedPostId], dr.depth + 1
  FROM PostLinks pl
  JOIN duplicate_roots dr ON pl.PostId = dr.RelatedPostId
  WHERE pl.LinkTypeId = 3 AND NOT pl.RelatedPostId = ANY(dr.path)
),
duplicate_canonical AS (
  SELECT dr.PostId, dr.RelatedPostId, dr.depth, dr.path
  FROM duplicate_roots dr
  JOIN (
    SELECT PostId, MAX(depth) AS max_depth FROM duplicate_roots GROUP BY PostId
  ) md ON md.PostId = dr.PostId AND md.max_depth = dr.depth
),
post_duplicate_map AS (
  SELECT p.Id AS PostId,
    COALESCE(dc.RelatedPostId, p.Id) AS DuplicateRoot,
    CASE WHEN dc.RelatedPostId IS NULL THEN FALSE ELSE TRUE END AS IsDuplicate
  FROM Posts p
  LEFT JOIN duplicate_canonical dc ON dc.PostId = p.Id
),
user_posts AS (
  SELECT u.Id AS UserId, u.DisplayName,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers,
    COALESCE(SUM(p.Score),0) AS total_post_score,
    MAX(p.CreationDate) AS last_post_date,
    MIN(p.CreationDate) AS first_post_date
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
user_badges AS (
  SELECT b.UserId, COUNT(*) AS badge_count,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze,
    SUM(CASE WHEN b.TagBased::text = '1' THEN 1 ELSE 0 END) AS tag_based_count
  FROM Badges b
  GROUP BY b.UserId
),
user_votes AS (
  SELECT u.Id AS UserId,
    SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId IN (8,9) AND v.BountyAmount IS NOT NULL) AS total_bounty_given,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS given_upvotes,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS given_downvotes
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id
),
users_enriched AS (
  SELECT up.UserId, up.DisplayName, up.questions, up.answers, up.total_post_score, up.first_post_date, up.last_post_date,
    COALESCE(ub.badge_count,0) AS badge_count, COALESCE(ub.gold,0) AS gold, COALESCE(ub.silver,0) AS silver, COALESCE(ub.bronze,0) AS bronze, COALESCE(ub.tag_based_count,0) AS tag_based_count, COALESCE(uv.total_bounty_given,0) AS total_bounty_given,
    COALESCE(uv.given_upvotes,0) AS given_upvotes, COALESCE(uv.given_downvotes,0) AS given_downvotes
  FROM user_posts up
  LEFT JOIN user_badges ub ON up.UserId = ub.UserId
  LEFT JOIN user_votes uv ON up.UserId = uv.UserId
),
user_top_post AS (
  SELECT u.UserId, u.DisplayName, p.Id AS PostId, p.Title, p.Score, p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY u.UserId ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) AS rn
  FROM users_enriched u
  LEFT JOIN Posts p ON p.OwnerUserId = u.UserId
),
user_top_post_filtered AS (
  SELECT UserId, DisplayName, PostId, Title, Score, PostTypeId
  FROM user_top_post
  WHERE rn = 1
),
question_metrics AS (
  SELECT q.Id AS QuestionId,
    q.Title,
    COALESCE(v.upvotes,0) AS upvotes,
    COALESCE(v.downvotes,0) AS downvotes,
    COALESCE(v.total_votes,0) AS total_votes,
    CASE WHEN COALESCE(v.total_votes,0)>0 THEN ROUND((COALESCE(v.upvotes,0)::numeric / GREATEST(v.total_votes,1))::numeric,3) ELSE NULL END AS upvote_fraction,
    COALESCE(a.answer_count,0) AS computed_answer_count,
    COALESCE(cc.CommentCount,0) AS comment_count,
    COALESCE(pdm.DuplicateRoot, q.Id) AS duplicate_root,
    GREATEST(COALESCE(q.LastActivityDate,'1970-01-01'::timestamp), COALESCE(cl.CommentDate,'1970-01-01'::timestamp), COALESCE(ph.MaxHistoryDate,'1970-01-01'::timestamp)) AS last_known_activity,
    char_length(COALESCE(q.Body,'')) AS body_length,
    LEFT(regexp_replace(COALESCE(q.Body,''), '<[^>]*>', '', 'g'), 200) AS body_snippet,
    CASE WHEN q.Tags IS NULL OR char_length(q.Tags) <= 2 THEN 0 ELSE (SELECT COUNT(*) FROM regexp_split_to_table(substring(q.Tags FROM 2 FOR char_length(q.Tags)-2), '><')) END AS tag_count,
    EXTRACT(EPOCH FROM ( (SELECT MIN(a.CreationDate) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) - q.CreationDate)) AS secs_to_first_answer
  FROM Posts q
  LEFT JOIN votes_per_post v ON v.PostId = q.Id
  LEFT JOIN answers_agg a ON a.QuestionId = q.Id
  LEFT JOIN comments_latest cl ON cl.PostId = q.Id
  LEFT JOIN (
    SELECT ph.PostId, MAX(ph.CreationDate) AS MaxHistoryDate
    FROM PostHistory ph GROUP BY ph.PostId
  ) ph ON ph.PostId = q.Id
  LEFT JOIN post_duplicate_map pdm ON pdm.PostId = q.Id
  LEFT JOIN comments_counts cc ON cc.PostId = q.Id
  WHERE q.PostTypeId = 1
),
question_answerers AS (
  SELECT q.Id AS QuestionId,
    COUNT(DISTINCT a.OwnerUserId) AS distinct_answerers,
    SUM(CASE WHEN a.OwnerUserId IS NOT NULL AND (SELECT COALESCE(u.Reputation,0) FROM Users u WHERE u.Id = a.OwnerUserId) > 10000 THEN 1 ELSE 0 END) AS answers_by_highrep,
    SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS accepted_is_answer_present
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  WHERE q.PostTypeId = 1
  GROUP BY q.Id
),
tag_time_series AS (
  SELECT t.Tag,
    date_trunc('month', p.CreationDate) AS month,
    COUNT(*) AS qcount,
    AVG(p.Score::numeric) AS avg_score,
    SUM(p.ViewCount::bigint) AS total_views
  FROM tagged_questions t
  JOIN Posts p ON p.Id = t.QuestionId
  GROUP BY t.Tag, date_trunc('month', p.CreationDate)
),
tag_time_series_ma AS (
  SELECT Tag, month, qcount, avg_score, total_views,
    AVG(avg_score) OVER (PARTITION BY Tag ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS avg_score_ma3,
    SUM(qcount) OVER (PARTITION BY Tag ORDER BY month ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS qcount_6mo
  FROM tag_time_series
),
hot_tags AS (
  SELECT Tag FROM tag_stats WHERE questions > 100
  INTERSECT
  SELECT Tag FROM tag_time_series WHERE avg_score > 1
),
tag_summary AS (
  SELECT ts.Tag, ts.questions, ts.avg_views, ts.avg_score, ts.closed_count, ts.distinct_askers, tt.top3
  FROM tag_stats ts
  LEFT JOIN tag_top3 tt ON tt.Tag = ts.Tag
),
top_tags AS (
  SELECT 'TAG'::text AS kind, Tag::text AS identifier, questions::bigint AS metric1, avg_views::numeric AS metric2, avg_score::numeric AS metric3, closed_count::int AS metric4, distinct_askers::int AS metric5, top3::jsonb AS details
  FROM tag_summary
  ORDER BY questions DESC NULLS LAST
  LIMIT 50
),
top_users AS (
  SELECT 'USER'::text AS kind, CAST(u.UserId AS text) AS identifier, (u.questions + u.answers)::bigint AS metric1, u.total_post_score::numeric AS metric2, u.badge_count::numeric AS metric3, u.gold::int AS metric4, u.silver::int AS metric5, jsonb_build_object('TopPost', jsonb_build_object('Id', up.PostId, 'Title', left(up.Title,120), 'Score', up.Score))::jsonb AS details
  FROM users_enriched u
  LEFT JOIN user_top_post_filtered up ON up.UserId = u.UserId
  ORDER BY (u.questions + u.answers) DESC NULLS LAST, u.total_post_score DESC NULLS LAST
  LIMIT 50
),
combined_sample AS (
  SELECT kind, identifier, metric1, metric2, metric3, metric4, metric5, details
  FROM top_tags
  UNION ALL
  SELECT kind, identifier, metric1, metric2, metric3, metric4, metric5, details
  FROM top_users
),
final_rankings AS (
  SELECT cs.kind, cs.identifier, cs.metric1, cs.metric2, cs.metric3, cs.metric4, cs.metric5, cs.details,
    (COALESCE(cs.metric1,0)::numeric * 0.4 + COALESCE(cs.metric2,0)::numeric * 0.25 + COALESCE(cs.metric3,0)::numeric * 0.2 + COALESCE(cs.metric4,0)::numeric * 0.1 + COALESCE(cs.metric5,0)::numeric * 0.05) AS impact_score,
    ROW_NUMBER() OVER (PARTITION BY cs.kind ORDER BY (COALESCE(cs.metric1,0)::numeric * 0.4 + COALESCE(cs.metric2,0)::numeric * 0.25 + COALESCE(cs.metric3,0)::numeric * 0.2) DESC NULLS LAST) AS kind_rank
  FROM combined_sample cs
)
SELECT fr.kind, fr.identifier, fr.metric1, fr.metric2, fr.metric3, fr.metric4, fr.metric5, fr.details, fr.impact_score, fr.kind_rank,
  tma.avg_score_ma3, tma.qcount_6mo,
  CASE WHEN fr.kind = 'TAG' AND EXISTS (SELECT 1 FROM hot_tags ht WHERE ht.Tag = fr.identifier) THEN TRUE ELSE FALSE END AS is_hot
FROM final_rankings fr
LEFT JOIN LATERAL (
  SELECT avg_score_ma3, qcount_6mo FROM tag_time_series_ma tma WHERE fr.kind = 'TAG' AND tma.Tag = fr.identifier ORDER BY month DESC LIMIT 1
) tma ON true
ORDER BY fr.kind, fr.kind_rank, fr.impact_score DESC
LIMIT 200;