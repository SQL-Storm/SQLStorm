-- {"query": "323.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 13919} 
WITH
recent_questions AS (
  SELECT p.Id,
         p.Title,
         p.Tags,
         p.OwnerUserId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.AnswerCount,
         p.ClosedDate,
         string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS tag_arr,
         COALESCE(u.DisplayName, '(deleted)') AS OwnerName,
         ROW_NUMBER() OVER (PARTITION BY COALESCE(u.Id, -1) ORDER BY p.CreationDate DESC) as rn_by_user
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '2 years'
),
exploded_tags AS (
  SELECT rq.*,
         CASE WHEN rq.tag_arr IS NULL THEN NULL ELSE rq.tag_arr[gs.i] END AS tag,
         gs.i AS ord
  FROM recent_questions rq
  LEFT JOIN LATERAL generate_subscripts(rq.tag_arr, 1) AS gs(i) ON TRUE
),
answer_aggregates AS (
  SELECT p.ParentId AS QuestionId,
         COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS total_answers,
         SUM(CASE WHEN p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS accepted_present,
         AVG(p.Score) AS avg_answer_score,
         MAX(p.CreationDate) AS last_answer_date
  FROM Posts p
  LEFT JOIN Posts q ON p.ParentId = q.Id AND q.PostTypeId = 1
  WHERE p.PostTypeId = 2
  GROUP BY p.ParentId
),
vote_summaries AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
         SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS favorites,
         COUNT(*) AS total_votes
  FROM Votes v
  GROUP BY v.PostId
),
comment_counts AS (
  SELECT c.PostId,
         COUNT(*) FILTER (WHERE c.CreationDate >= NOW() - INTERVAL '30 days') AS recent_comments_30d,
         COUNT(*) AS total_comments,
         MAX(c.CreationDate) AS last_comment_date
  FROM Comments c
  GROUP BY c.PostId
),
post_history_closures AS (
  SELECT ph.PostId,
         MAX(CASE WHEN ph.PostHistoryTypeId IN (10, 35) THEN ph.CreationDate END) AS last_closed_date,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS close_votes_records
  FROM PostHistory ph
  GROUP BY ph.PostId
),
link_metrics AS (
  SELECT pl.RelatedPostId AS QuestionId,
         SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS inbound_links,
         SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS marked_duplicates_incoming,
         COUNT(*) AS total_links
  FROM PostLinks pl
  GROUP BY pl.RelatedPostId
),
tag_popularity AS (
  SELECT et.tag,
         COUNT(*) AS questions_with_tag,
         AVG(q.ViewCount) AS avg_views,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY q.Score) AS median_score,
         MAX(q.Score) AS max_score
  FROM exploded_tags et
  JOIN Posts q ON et.Id = q.Id
  WHERE et.tag IS NOT NULL
  GROUP BY et.tag
),
trending_tags AS (
  (SELECT tag FROM tag_popularity WHERE questions_with_tag >= 50)
  INTERSECT
  (SELECT tag FROM tag_popularity WHERE avg_views > 1000)
),
user_activity AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId IN (1,2)) AS posts_count,
         COUNT(DISTINCT bad.Id) AS badges_count,
         MAX(u.Reputation) AS max_reputation,
         MIN(u.CreationDate) AS first_seen,
         MAX(u.LastAccessDate) AS last_seen,
         SUM(COALESCE(v.upvotes,0)) AS total_upvotes_received,
         ROW_NUMBER() OVER (ORDER BY SUM(COALESCE(v.upvotes,0)) DESC NULLS LAST) AS rank_by_upvotes
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Badges bad ON bad.UserId = u.Id
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes
    FROM Votes
    GROUP BY PostId
  ) v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName
),
scoring AS (
  SELECT rq.*,
         COALESCE(a.total_answers,0) AS total_answers,
         COALESCE(a.avg_answer_score,0) AS avg_answer_score,
         COALESCE(vs.upvotes,0) AS upvotes,
         COALESCE(vs.downvotes,0) AS downvotes,
         COALESCE(cc.total_comments,0) AS total_comments,
         phc.last_closed_date AS last_closed_date,
         COALESCE(lm.inbound_links,0) AS inbound_links,
         CASE
           WHEN rq.ViewCount IS NULL THEN 0
           ELSE ROUND(
             (rq.Score::numeric) * (1 + LN(GREATEST(1, rq.ViewCount::numeric)))
             + (COALESCE(vs.upvotes,0) - COALESCE(vs.downvotes,0)) * 2
             + LEAST(50, COALESCE(cc.total_comments,0)) * 0.5
             + GREATEST(0, COALESCE(a.avg_answer_score,0)) * 1.5
             - (CASE WHEN phc.last_closed_date IS NOT NULL THEN 100 ELSE 0 END)
             + LN(LEAST(10000, GREATEST(1, COALESCE(lm.inbound_links,0) + 1)))
           ,2)
         END AS computed_popularity
  FROM recent_questions rq
  LEFT JOIN answer_aggregates a ON a.QuestionId = rq.Id
  LEFT JOIN vote_summaries vs ON vs.PostId = rq.Id
  LEFT JOIN comment_counts cc ON cc.PostId = rq.Id
  LEFT JOIN post_history_closures phc ON phc.PostId = rq.Id
  LEFT JOIN link_metrics lm ON lm.QuestionId = rq.Id
),
tag_rankings AS (
  SELECT et.tag,
         et.Id AS QuestionId,
         et.Title,
         et.OwnerName,
         et.CreationDate,
         s.computed_popularity,
         RANK() OVER (PARTITION BY et.tag ORDER BY s.computed_popularity DESC NULLS LAST) AS rank_within_tag,
         ROW_NUMBER() OVER (PARTITION BY et.tag ORDER BY s.computed_popularity DESC, et.Score DESC) AS rn_within_tag
  FROM exploded_tags et
  JOIN scoring s ON s.Id = et.Id
  WHERE et.tag IS NOT NULL
),
top_per_tag AS (
  SELECT tag, QuestionId, Title, OwnerName, CreationDate, computed_popularity
  FROM tag_rankings
  WHERE rn_within_tag <= 3
),
recent_activity_union AS (
  (SELECT p.Id AS ItemId, 'question' AS ItemType, p.Title AS summary, p.CreationDate AS when_happened
   FROM Posts p
   WHERE p.PostTypeId = 1 AND p.CreationDate >= NOW() - INTERVAL '7 days')
  UNION ALL
  (SELECT c.PostId AS ItemId, 'comment' AS ItemType, LEFT(c.Text, 200) AS summary, c.CreationDate AS when_happened
   FROM Comments c
   WHERE c.CreationDate >= NOW() - INTERVAL '7 days')
),
complex_correlated AS (
  SELECT q.Id,
         (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = q.Id AND a.Score > COALESCE((SELECT AVG(x.Score) FROM Posts x WHERE x.ParentId = q.Id),0) + 2) AS high_scoring_answer_count,
         (SELECT STRING_AGG(u2.DisplayName || ':' || COALESCE(u2.Reputation::text,'0'), ', ' ORDER BY u2.Reputation DESC)
          FROM Users u2
          WHERE u2.Id IN (SELECT p.OwnerUserId FROM Posts p WHERE p.ParentId = q.Id AND p.OwnerUserId IS NOT NULL)
         ) AS answer_authors_summary,
         EXISTS(SELECT 1 FROM PostLinks pl WHERE pl.RelatedPostId = q.Id AND pl.LinkTypeId = 3) AS has_duplicates_marked,
         (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId IN (24,5,4)) AS edit_events_count
  FROM Posts q
  WHERE q.PostTypeId = 1
    AND q.CreationDate >= NOW() - INTERVAL '2 years'
),
final AS (
  SELECT s.Id AS QuestionId,
         s.Title,
         s.OwnerName,
         s.OwnerUserId,
         s.CreationDate,
         s.Score AS question_score,
         s.ViewCount,
         s.computed_popularity,
         COALESCE(et.tag, '(untagged)') AS primary_tag,
         tp.questions_with_tag,
         ua.DisplayName AS top_contributor,
         ua.posts_count AS top_contributor_posts,
         ua.rank_by_upvotes,
         cc.recent_comments_30d,
         vs.upvotes, vs.downvotes,
         phc.close_votes_records,
         lm.total_links,
         hc.high_scoring_answer_count,
         hc.answer_authors_summary,
         ta.max_score AS tag_max_score,
         CASE
           WHEN s.CreationDate >= NOW() - INTERVAL '30 days' THEN 'fresh'
           WHEN s.computed_popularity > 100 THEN 'hot'
           WHEN s.computed_popularity < -50 THEN 'cold'
           ELSE 'steady'
         END AS status_bucket,
         ROW_NUMBER() OVER (ORDER BY s.computed_popularity DESC NULLS LAST) AS global_popularity_rank,
         (tt.tag IS NOT NULL) AS is_trending_tag
  FROM scoring s
  LEFT JOIN exploded_tags et ON et.Id = s.Id AND et.ord = 1
  LEFT JOIN tag_popularity tp ON tp.tag = et.tag
  LEFT JOIN LATERAL (
    SELECT ua.DisplayName, ua.posts_count, ua.rank_by_upvotes
    FROM user_activity ua
    WHERE ua.UserId = s.OwnerUserId
    ORDER BY ua.rank_by_upvotes ASC
    LIMIT 1
  ) ua ON TRUE
  LEFT JOIN comment_counts cc ON cc.PostId = s.Id
  LEFT JOIN vote_summaries vs ON vs.PostId = s.Id
  LEFT JOIN post_history_closures phc ON phc.PostId = s.Id
  LEFT JOIN link_metrics lm ON lm.QuestionId = s.Id
  LEFT JOIN complex_correlated hc ON hc.Id = s.Id
  LEFT JOIN tag_popularity ta ON ta.tag = et.tag
  LEFT JOIN trending_tags tt ON tt.tag = et.tag
)
SELECT f.*,
       (SELECT COUNT(*) FROM final ff WHERE ff.computed_popularity > f.computed_popularity) AS count_more_popular,
       (SELECT STRING_AGG(sub.tag_snapshot, ' | ')
        FROM (
          SELECT t.tag || '(' || t.questions_with_tag || ')' AS tag_snapshot
          FROM tag_popularity t
          WHERE t.questions_with_tag > 10
          ORDER BY t.questions_with_tag DESC
          LIMIT 5
        ) sub
       ) AS popular_tags_snapshot
FROM final f
WHERE f.computed_popularity IS NOT NULL
ORDER BY f.computed_popularity DESC
LIMIT 100;