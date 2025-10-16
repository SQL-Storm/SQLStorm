-- {"query": "393.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 18651} 
WITH vote_counts AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
         SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted_votes,
         COUNT(*) AS total_votes
  FROM Votes v
  GROUP BY v.PostId
),
tag_exploded AS (
  SELECT p.Id AS PostId,
         TRIM(tag) AS Tag
  FROM Posts p
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(COALESCE(p.Tags,''), 2, GREATEST(char_length(COALESCE(p.Tags,'')) - 2, 0)), '><')) AS tag
  ) t ON true
  WHERE p.PostTypeId = 1
),
post_metrics AS (
  SELECT p.Id,
         p.OwnerUserId,
         p.PostTypeId,
         p.ParentId,
         p.AcceptedAnswerId,
         COALESCE(vc.upvotes,0) AS upvotes,
         COALESCE(vc.downvotes,0) AS downvotes,
         COALESCE(vc.accepted_votes,0) AS accepted_votes,
         COALESCE(p.Score,0) AS Score,
         COALESCE(p.ViewCount,0) AS ViewCount,
         p.CreationDate,
         EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.CreationDate))/86400.0 AS age_days,
         (COALESCE(p.Score,0) * (1 + COALESCE(p.ViewCount,0) / GREATEST(1.0, (10 + EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.CreationDate))/86400.0)))) AS score_age_factor,
         CASE WHEN (COALESCE(vc.upvotes,0) + COALESCE(vc.downvotes,0)) = 0 THEN 0
              ELSE ABS(COALESCE(vc.upvotes,0) - COALESCE(vc.downvotes,0))::numeric / NULLIF((COALESCE(vc.upvotes,0) + COALESCE(vc.downvotes,0)),0)
         END AS controversy_ratio,
         COALESCE(p.Title,'') AS Title,
         COALESCE(p.Tags,'') AS Tags,
         p.LastActivityDate
  FROM Posts p
  LEFT JOIN vote_counts vc ON vc.PostId = p.Id
),
posts_by_user AS (
  SELECT OwnerUserId,
         COUNT(*) AS total_posts,
         SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS questions,
         SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS answers,
         SUM(CASE WHEN PostTypeId = 1 THEN COALESCE(ViewCount,0) ELSE 0 END) AS question_views,
         SUM(CASE WHEN PostTypeId = 2 THEN COALESCE(Score,0) ELSE 0 END) AS answer_score_sum,
         MIN(COALESCE(CreationDate, '1970-01-01'::timestamp)) AS first_post_date,
         MAX(COALESCE(LastActivityDate, CreationDate)) AS last_post_activity
  FROM Posts
  GROUP BY OwnerUserId
),
post_metrics_by_user AS (
  SELECT OwnerUserId,
         SUM(score_age_factor) AS total_weighted_score,
         SUM(controversy_ratio) AS controversy_sum
  FROM post_metrics
  GROUP BY OwnerUserId
),
badges_by_user AS (
  SELECT UserId, COUNT(*) AS badge_count, SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold_badges
  FROM Badges
  GROUP BY UserId
),
comments_by_user AS (
  SELECT UserId, COUNT(*) AS comment_count, AVG(char_length(Text))::numeric AS avg_comment_len
  FROM Comments
  WHERE UserId IS NOT NULL
  GROUP BY UserId
),
per_user_aggregates AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         COALESCE(pbu.total_posts,0) AS total_posts,
         COALESCE(pbu.questions,0) AS questions,
         COALESCE(pbu.answers,0) AS answers,
         COALESCE(pbu.question_views,0) AS question_views,
         COALESCE(pbu.answer_score_sum,0) AS answer_score_sum,
         COALESCE(pmu.total_weighted_score,0) AS total_weighted_score,
         COALESCE(pmu.controversy_sum,0) AS controversy_sum,
         COALESCE(bu.badge_count,0) AS badge_count,
         COALESCE(cb.comment_count,0) AS comment_count,
         (SELECT COUNT(*) FROM Votes v JOIN Posts ans ON v.PostId = ans.Id WHERE v.VoteTypeId = 1 AND ans.OwnerUserId = u.Id) AS accepted_by_votes,
         (SELECT COUNT(*) FROM Posts q JOIN Posts ans ON q.AcceptedAnswerId = ans.Id WHERE ans.OwnerUserId = u.Id AND q.AcceptedAnswerId IS NOT NULL) AS accepted_by_questions,
         COALESCE(pbu.first_post_date, u.CreationDate) AS earliest_activity,
         COALESCE(pbu.last_post_activity, u.LastAccessDate) AS latest_activity
  FROM Users u
  LEFT JOIN posts_by_user pbu ON pbu.OwnerUserId = u.Id
  LEFT JOIN post_metrics_by_user pmu ON pmu.OwnerUserId = u.Id
  LEFT JOIN badges_by_user bu ON bu.UserId = u.Id
  LEFT JOIN comments_by_user cb ON cb.UserId = u.Id
),
top_posts_per_user AS (
  SELECT pm.OwnerUserId AS UserId,
         pm.Id AS PostId,
         pm.PostTypeId,
         pm.Title,
         pm.Score,
         pm.upvotes,
         pm.downvotes,
         pm.controversy_ratio,
         ROW_NUMBER() OVER (PARTITION BY pm.OwnerUserId ORDER BY pm.score_age_factor DESC NULLS LAST, pm.controversy_ratio DESC NULLS LAST) AS rn
  FROM post_metrics pm
  WHERE pm.OwnerUserId IS NOT NULL
),
user_tag_popularity AS (
  SELECT p.OwnerUserId AS UserId,
         TRIM(tag) AS Tag,
         COUNT(*) AS tag_count,
         SUM(COALESCE(p.ViewCount,0)) AS tag_views,
         AVG(COALESCE(p.Score,0)) AS avg_score
  FROM Posts p
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substring(COALESCE(p.Tags,''), 2, GREATEST(char_length(COALESCE(p.Tags,'')) - 2, 0)), '><')) AS tag
  ) t ON true
  WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId, TRIM(tag)
),
answer_dominant AS (
  SELECT u.Id AS UserId, 'answers' AS dominance, u.Reputation, COALESCE(pu.answers,0) AS answers, COALESCE(pu.questions,0) AS questions
  FROM Users u
  LEFT JOIN posts_by_user pu ON pu.OwnerUserId = u.Id
  WHERE COALESCE(pu.answers,0) > COALESCE(pu.questions,0)
),
question_dominant AS (
  SELECT u.Id AS UserId, 'questions' AS dominance, u.Reputation, COALESCE(pu.answers,0) AS answers, COALESCE(pu.questions,0) AS questions
  FROM Users u
  LEFT JOIN posts_by_user pu ON pu.OwnerUserId = u.Id
  WHERE COALESCE(pu.questions,0) >= COALESCE(pu.answers,0)
),
dominance_union AS (
  SELECT * FROM answer_dominant
  UNION
  SELECT * FROM question_dominant
),
duplicate_link_counts AS (
  SELECT p.OwnerUserId AS UserId,
         COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS duplicate_outgoing,
         COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS linked_outgoing
  FROM Posts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  GROUP BY p.OwnerUserId
),
controversial_posts AS (
  SELECT pm.*, te.Tag
  FROM post_metrics pm
  LEFT JOIN tag_exploded te ON te.PostId = pm.Id
  WHERE (pm.upvotes + pm.downvotes) >= 5
  ORDER BY pm.controversy_ratio DESC NULLS LAST
  LIMIT 100
),
user_ranks AS (
  SELECT pua.UserId,
         RANK() OVER (ORDER BY COALESCE(pua.total_weighted_score,0) DESC, COALESCE(pua.questions,0) DESC) AS score_rank,
         ROW_NUMBER() OVER (ORDER BY COALESCE(pua.Reputation,0) DESC) AS rep_rank
  FROM per_user_aggregates pua
),
median_answers AS (
  SELECT OwnerUserId AS UserId,
         AVG(Score)::numeric(10,3) AS median_answer_score
  FROM (
    SELECT p2.OwnerUserId, p2.Score,
           row_number() OVER (PARTITION BY p2.OwnerUserId ORDER BY p2.Score) AS rn,
           count(*) OVER (PARTITION BY p2.OwnerUserId) AS cnt
    FROM Posts p2
    WHERE p2.PostTypeId = 2 AND p2.OwnerUserId IS NOT NULL
  ) s
  WHERE rn IN ( (cnt+1)/2, (cnt+2)/2 )
  GROUP BY OwnerUserId
),
final AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         COALESCE(pua.total_posts,0) AS total_posts,
         COALESCE(pua.questions,0) AS questions,
         COALESCE(pua.answers,0) AS answers,
         COALESCE(pua.total_weighted_score,0) AS total_weighted_score,
         COALESCE(pua.accepted_by_votes,0) + COALESCE(pua.accepted_by_questions,0) AS accepted_total,
         COALESCE(pua.badge_count,0) AS badge_count,
         COALESCE(dl.duplicate_outgoing,0) AS duplicate_outgoing,
         COALESCE(dl.linked_outgoing,0) AS linked_outgoing,
         COALESCE(du.dominance,'unknown') AS dominance,
         COALESCE(pua.comment_count,0) AS comment_count,
         pua.earliest_activity,
         pua.latest_activity,
         ur.score_rank,
         ur.rep_rank,
         tp.PostId AS top_post_id,
         tp.Title AS top_post_title,
         tp.Score AS top_post_score,
         tp.controversy_ratio AS top_post_controversy,
         tag.Tag AS favorite_tag,
         tag.tag_count AS favorite_tag_count,
         tag.tag_views AS favorite_tag_views
  FROM Users u
  LEFT JOIN per_user_aggregates pua ON pua.UserId = u.Id
  LEFT JOIN duplicate_link_counts dl ON dl.UserId = u.Id
  LEFT JOIN dominance_union du ON du.UserId = u.Id
  LEFT JOIN user_ranks ur ON ur.UserId = u.Id
  LEFT JOIN LATERAL (
    SELECT tp.PostId, tp.Title, tp.Score, tp.controversy_ratio
    FROM top_posts_per_user tp
    WHERE tp.UserId = u.Id AND tp.rn = 1
    LIMIT 1
  ) tp ON true
  LEFT JOIN LATERAL (
    SELECT Tag, tag_count, tag_views
    FROM user_tag_popularity utp
    WHERE utp.UserId = u.Id
    ORDER BY utp.tag_count DESC NULLS LAST, utp.tag_views DESC NULLS LAST
    LIMIT 1
  ) tag ON true
)
SELECT f.*,
       COALESCE(m.median_answer_score, 0) AS median_answer_score,
       CASE WHEN f.answers = 0 THEN NULL ELSE ROUND(1.0 * f.accepted_total / NULLIF(f.answers,0)::numeric,4) END AS accepted_answer_ratio,
       COALESCE(f.DisplayName,'<deleted>') || ' | rep=' || f.Reputation::text || ' | top_tag=' || COALESCE(f.favorite_tag,'-') || ' | dup_links=' || f.duplicate_outgoing::text AS display_summary
FROM final f
LEFT JOIN median_answers m ON m.UserId = f.UserId
WHERE f.Reputation > 500
ORDER BY f.total_weighted_score DESC NULLS LAST, f.Reputation DESC
LIMIT 50;