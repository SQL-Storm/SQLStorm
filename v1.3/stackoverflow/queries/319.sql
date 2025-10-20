WITH
params AS (
  SELECT CAST('2024-10-01 12:34:56' AS timestamp) AS ts,
         CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365 days' AS since_1y,
         CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days' AS since_90d,
         CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days' AS since_30d
),
users_base AS (
  SELECT u.Id AS user_id,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         u.Views,
         u.UpVotes,
         u.DownVotes
  FROM Users u
),
posts_base AS (
  SELECT p.* FROM Posts p WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
),
user_posts AS (
  SELECT p.OwnerUserId AS user_id,
         SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS q_count,
         SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS a_count,
         COUNT(*) FILTER (WHERE p.PostTypeId IN (1,2)) AS qa_count,
         SUM(CASE WHEN p.PostTypeId IN (1,2) THEN COALESCE(p.Score,0) ELSE 0 END) AS total_post_score,
         AVG(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score ELSE NULL END) AS avg_post_score,
         SUM(COALESCE(p.ViewCount,0)) AS total_views,
         MAX(p.CreationDate) AS recent_post_date
  FROM posts_base p
  GROUP BY p.OwnerUserId
),
user_votes AS (
  SELECT p.OwnerUserId AS user_id,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS net_vote_score,
         SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted_vote_count,
         COUNT(*) AS votes_received
  FROM Votes v
  JOIN Posts p ON v.PostId = p.Id
  WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
  GROUP BY p.OwnerUserId
),
user_badges AS (
  SELECT b.UserId AS user_id,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
         SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver,
         SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze,
         SUM(CASE WHEN COALESCE(b.TagBased, FALSE) = TRUE THEN 1 ELSE 0 END) AS tagbadges
  FROM Badges b
  GROUP BY b.UserId
),
user_history AS (
  SELECT ph.UserId AS user_id,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (5,24,66,4,6)) AS edit_actions,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS close_votes_recorded,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS reopen_votes_recorded,
         COUNT(DISTINCT ph.PostId) AS distinct_posts_touched,
         MAX(ph.CreationDate) AS recent_edit
  FROM PostHistory ph
  WHERE ph.UserId IS NOT NULL
  GROUP BY ph.UserId
),
tag_posts AS (
  SELECT p.Id AS post_id,
         p.OwnerUserId AS user_id,
         lower(trim(t.tag)) AS tag,
         p.Score, p.ViewCount, p.CreationDate
  FROM Posts p,
       LATERAL (
         SELECT unnest(
           string_to_array(
             substring(COALESCE(p.Tags,'') , 2, CASE WHEN length(COALESCE(p.Tags,'')) > 2 THEN length(COALESCE(p.Tags,'')) - 2 ELSE 0 END),
             '><'
           )
         ) AS tag
       ) t
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
tag_user_group AS (
  SELECT tp.user_id, tp.tag, COUNT(*) AS cnt, SUM(COALESCE(tp.Score,0)) AS sum_score
  FROM tag_posts tp
  WHERE tp.user_id IS NOT NULL AND tp.user_id > 0
  GROUP BY tp.user_id, tp.tag
),
user_tag_counts AS (
  SELECT tug.*,
         ROW_NUMBER() OVER (PARTITION BY tug.user_id ORDER BY tug.cnt DESC, tug.sum_score DESC) AS rn
  FROM tag_user_group tug
),
top_tags_per_user AS (
  SELECT utc.user_id,
         array_to_string(array_agg(utc.tag || ':' || CAST(utc.cnt AS text) || COALESCE('('||CAST(utc.sum_score AS text)||')','') ORDER BY utc.cnt DESC, utc.sum_score DESC), ',') AS top_tags
  FROM user_tag_counts utc
  WHERE utc.rn <= 5
  GROUP BY utc.user_id
),
tag_agg AS (
  SELECT t.tag,
         COUNT(*) AS question_count,
         COUNT(DISTINCT t.user_id) AS distinct_askers,
         AVG(t.Score) AS avg_question_score,
         SUM(COALESCE(t.ViewCount,0)) AS total_views
  FROM tag_posts t
  GROUP BY t.tag
),
global_stats AS (
  SELECT SUM(COALESCE(up.qa_count,0)) AS total_qa_posts,
         AVG(COALESCE(up.avg_post_score,0)) AS avg_user_post_score,
         STDDEV_POP(COALESCE(up.avg_post_score,0)) AS sd_user_post_score,
         MAX(COALESCE(up.recent_post_date, TIMESTAMP '1970-01-01')) AS latest_post_ts
  FROM user_posts up
),
recent_contributors AS (
  SELECT DISTINCT OwnerUserId AS user_id FROM Posts WHERE CreationDate >= (SELECT since_90d FROM params) AND OwnerUserId IS NOT NULL AND OwnerUserId > 0
  UNION
  SELECT DISTINCT UserId FROM Comments WHERE CreationDate >= (SELECT since_90d FROM params) AND UserId IS NOT NULL
),
high_reputation_users AS (
  SELECT Id AS user_id FROM Users WHERE Reputation >= 10000
),
active_and_high AS (
  SELECT user_id FROM recent_contributors
  INTERSECT
  SELECT user_id FROM high_reputation_users
),
active_not_high AS (
  SELECT user_id FROM recent_contributors
  EXCEPT
  SELECT user_id FROM high_reputation_users
),
user_composite AS (
  SELECT ub.user_id,
         ub.DisplayName,
         COALESCE(ub.Reputation,0) AS reputation,
         COALESCE(up.q_count,0) AS questions,
         COALESCE(up.a_count,0) AS answers,
         COALESCE(up.qa_count,0) AS qa_posts,
         COALESCE(up.total_views,0) AS post_views,
         COALESCE(uv.net_vote_score,0) AS net_votes,
         COALESCE(ubd.gold,0) AS gold,
         COALESCE(ubd.silver,0) AS silver,
         COALESCE(ubd.bronze,0) AS bronze,
         COALESCE(uh.edit_actions,0) AS edits,
         COALESCE(tt.top_tags,'') AS top_tags,
         COALESCE(g.avg_user_post_score,0) AS global_avg_post_score,
         COALESCE(g.sd_user_post_score,1) AS global_sd_user_post_score,
         COALESCE(up.avg_post_score,0) AS avg_post_score,
         CASE WHEN COALESCE(g.sd_user_post_score,0) > 0 THEN (COALESCE(up.avg_post_score,0) - COALESCE(g.avg_user_post_score,0)) / COALESCE(g.sd_user_post_score,1) ELSE 0 END AS avg_score_z,
         COALESCE(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - GREATEST(COALESCE(up.recent_post_date,TIMESTAMP '1970-01-01'), COALESCE(uh.recent_edit,TIMESTAMP '1970-01-01')))) / 86400.0, 365000.0) AS days_since_activity,
         (1.0 / (1.0 + POWER(LEAST(COALESCE(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - GREATEST(COALESCE(up.recent_post_date,TIMESTAMP '1970-01-01'), COALESCE(uh.recent_edit,TIMESTAMP '1970-01-01')))) / 86400.0, 365.0), 365.0), 0.5))) AS recency_boost,
         (SELECT COUNT(*) FROM PostLinks pl JOIN Posts p2 ON pl.PostId = p2.Id JOIN Posts rp ON pl.RelatedPostId = rp.Id WHERE pl.LinkTypeId = 3 AND p2.OwnerUserId = ub.user_id AND rp.OwnerUserId IS DISTINCT FROM ub.user_id) AS duplicates_pointing_elsewhere,
         (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY COALESCE(p.Score,0)) FROM Posts p WHERE p.OwnerUserId = ub.user_id AND p.PostTypeId IN (1,2)) AS median_post_score,
         (SELECT COUNT(DISTINCT tag) FROM tag_posts tp WHERE tp.user_id = ub.user_id) AS distinct_tags,
         CASE WHEN ub.user_id IN (SELECT user_id FROM active_and_high) THEN 1 ELSE 0 END AS in_active_and_high,
         CASE WHEN ub.user_id IN (SELECT user_id FROM active_not_high) THEN 1 ELSE 0 END AS in_active_not_high,
         (
           CASE WHEN ub.Reputation > 0 THEN LN(ub.Reputation) ELSE 0 END * 1.2
           + COALESCE(up.qa_count,0) * 0.8
           + COALESCE(uv.net_vote_score,0) * 0.6
           + (COALESCE(ubd.gold,0) * 5 + COALESCE(ubd.silver,0) * 2 + COALESCE(ubd.bronze,0) * 1) * 0.5
           + COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.UserId = ub.user_id AND c.CreationDate >= (SELECT since_30d FROM params)),0) * 0.2
           + COALESCE((SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = ub.user_id AND p3.AcceptedAnswerId IS NOT NULL),0) * 0.7
           + CASE WHEN COALESCE((SELECT COUNT(*) FROM Votes v2 JOIN Posts p4 ON v2.PostId = p4.Id WHERE v2.VoteTypeId = 15 AND v2.UserId = ub.user_id),0) > 0 THEN 1 ELSE 0 END * 0.9
           + (CASE WHEN COALESCE(up.avg_post_score,0) > 0 THEN COALESCE(up.avg_post_score,0) ELSE 0 END) * 0.3
           + (CASE WHEN COALESCE((SELECT percentile_cont(0.75) WITHIN GROUP (ORDER BY COALESCE(p.Score,0)) FROM Posts p WHERE p.OwnerUserId = ub.user_id),0) > COALESCE(g.avg_user_post_score,0) THEN 2 ELSE 0 END)
         ) * (1 + LEAST(COALESCE(CAST(ub.Views AS numeric) / NULLIF(GREATEST(ub.Views,1),0),0) / 10000.0, 0.5)) AS raw_composite_score
  FROM users_base ub
  LEFT JOIN user_posts up ON up.user_id = ub.user_id
  LEFT JOIN user_votes uv ON uv.user_id = ub.user_id
  LEFT JOIN user_badges ubd ON ubd.user_id = ub.user_id
  LEFT JOIN user_history uh ON uh.user_id = ub.user_id
  LEFT JOIN top_tags_per_user tt ON tt.user_id = ub.user_id
  CROSS JOIN global_stats g
),
ranked_users AS (
  SELECT uc.user_id,
         uc.DisplayName,
         uc.reputation,
         uc.questions,
         uc.answers,
         uc.qa_posts,
         uc.post_views,
         uc.net_votes,
         uc.gold,
         uc.silver,
         uc.bronze,
         uc.edits,
         uc.top_tags,
         uc.global_avg_post_score,
         uc.global_sd_user_post_score,
         uc.avg_post_score,
         uc.avg_score_z,
         uc.days_since_activity,
         uc.recency_boost,
         uc.duplicates_pointing_elsewhere,
         uc.median_post_score,
         uc.distinct_tags,
         uc.in_active_and_high,
         uc.in_active_not_high,
         uc.raw_composite_score,
         uc.top_tags AS top_tags_dup,
         ROW_NUMBER() OVER (ORDER BY uc.raw_composite_score DESC) AS rk,
         RANK() OVER (ORDER BY uc.raw_composite_score DESC) AS rnk,
         PERCENT_RANK() OVER (ORDER BY uc.raw_composite_score DESC) AS pct_rank,
         NTILE(100) OVER (ORDER BY uc.raw_composite_score DESC) AS percentile_bucket,
         SUM(uc.raw_composite_score) OVER (ORDER BY uc.raw_composite_score DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_score_total
  FROM user_composite uc
),
top_by_score AS (
  SELECT user_id, DisplayName, reputation, questions, answers, qa_posts, net_votes, gold, silver, bronze, edits, top_tags, raw_composite_score, rk, pct_rank, percentile_bucket
  FROM ranked_users
  WHERE rk <= 100
  ORDER BY raw_composite_score DESC
),
top_by_influence AS (
  SELECT uc.user_id, uc.DisplayName, COALESCE(uc.net_votes,0) AS influence_score, uc.gold, uc.silver, uc.bronze
  FROM user_composite uc
  ORDER BY influence_score DESC
  LIMIT 100
),
combined_top AS (
  SELECT user_id, DisplayName, CAST('score_list' AS text) AS list_type FROM top_by_score
  UNION
  SELECT user_id, DisplayName, CAST('influence_list' AS text) AS list_type FROM top_by_influence
)
SELECT ct.user_id,
       u.DisplayName,
       u.Reputation,
       u.Views AS profile_views,
       COALESCE(ru.questions,0) AS questions,
       COALESCE(ru.answers,0) AS answers,
       COALESCE(ru.qa_posts,0) AS total_posts,
       COALESCE(ru.net_votes,0) AS net_votes,
       COALESCE(ru.gold,0) AS gold,
       COALESCE(ru.silver,0) AS silver,
       COALESCE(ru.bronze,0) AS bronze,
       COALESCE(ru.top_tags,'') AS top_tags,
       COALESCE(ru.raw_composite_score,0) AS composite_score,
       ru.rk,
       ru.pct_rank,
       CASE WHEN ru.in_active_and_high = 1 THEN 'active_high' WHEN ru.in_active_not_high = 1 THEN 'active_non_high' ELSE 'other' END AS activity_segment,
       (SELECT (CAST(ph.Text AS json) ->> 'OriginalQuestionIds') FROM PostHistory ph WHERE ph.PostHistoryTypeId = 10 AND ph.UserId = ct.user_id AND ph.Text IS NOT NULL LIMIT 1) AS sample_duplicate_json,
       (SELECT COUNT(*) FROM PostHistory ph2 WHERE ph2.UserId = ct.user_id AND ph2.PostHistoryTypeId IN (17,35,36)) AS migrations_count,
       LEAST(u.CreationDate, COALESCE((SELECT MIN(CreationDate) FROM Posts p WHERE p.OwnerUserId = ct.user_id), u.CreationDate)) AS earliest_activity,
       GREATEST(u.LastAccessDate, COALESCE((SELECT MAX(CreationDate) FROM Posts p WHERE p.OwnerUserId = ct.user_id), u.LastAccessDate)) AS latest_activity,
       COALESCE( CASE WHEN COALESCE(ru.qa_posts,0) > 0 THEN ROUND( (COALESCE(ru.net_votes,0) / NULLIF(ru.qa_posts,0)), 3) ELSE NULL END, 0 ) AS avg_votes_per_post,
       NULLIF( regexp_replace(COALESCE(u.DisplayName,''), '[\s]{2,}', ' ', 'g'), '' ) AS normalized_displayname,
       CASE WHEN ct.user_id IN (SELECT user_id FROM combined_top EXCEPT SELECT user_id FROM top_by_score) THEN 'in_influence_only' WHEN ct.user_id IN (SELECT user_id FROM combined_top INTERSECT SELECT user_id FROM top_by_score) THEN 'in_both' ELSE 'in_score_only' END AS combined_membership,
       (SELECT array_to_string(array_agg(b2.Name || '(' || CAST(b2.Date AS date) || ')' ORDER BY b2.Date DESC), '; ') FROM Badges b2 WHERE b2.UserId = ct.user_id) AS recent_badges,
       (COALESCE(ru.distinct_tags,0) * sqrt(GREATEST(COALESCE(ru.qa_posts,0),1)) / NULLIF(GREATEST(ru.reputation,1),1)) AS tag_diversity_score
FROM combined_top ct
JOIN Users u ON u.Id = ct.user_id
LEFT JOIN ranked_users ru ON ru.user_id = ct.user_id
ORDER BY ru.raw_composite_score DESC NULLS LAST, ct.user_id
LIMIT 200;