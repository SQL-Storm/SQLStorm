WITH
-- recent activity windows per post and user
recent_posts AS (
  SELECT p.*,
         (CAST(p.Score AS FLOAT) / NULLIF(GREATEST(p.ViewCount,1),0)) AS score_per_view,
         regexp_split_to_array(substring(coalesce(p.Tags,''), 2, greatest(length(coalesce(p.Tags,'')) - 2,0)), '><') AS tag_array,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC NULLS LAST, p.Score DESC) AS rn_by_user
  FROM Posts p
  WHERE p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years'
),
-- aggregate post statistics per user (questions and answers)
user_post_stats AS (
  SELECT u.Id AS user_id,
         u.DisplayName,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS question_count,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answer_count,
         COALESCE(SUM(p.Score),0) AS total_score,
         AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS avg_score,
         MAX(p.CreationDate) AS last_post_date,
         SUM(CASE WHEN p.Tags IS NOT NULL THEN array_length(regexp_split_to_array(substring(p.Tags,2,length(p.Tags)-2),'><'),1) ELSE 0 END) AS total_tag_tokens
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
-- top tags by popularity across recent posts (exploding tag arrays)
tag_exploded AS (
  SELECT ttag, COUNT(*) AS tag_count, SUM(p.Score) AS tag_score_sum
  FROM recent_posts p,
       LATERAL unnest(p.tag_array) AS ttag
  WHERE ttag IS NOT NULL AND ttag <> ''
  GROUP BY ttag
),
tag_popularity AS (
  SELECT ttag AS tag_name,
         tag_count,
         tag_score_sum,
         RANK() OVER (ORDER BY tag_count DESC, tag_score_sum DESC) AS popularity_rank
  FROM tag_exploded
),
-- identify duplicate link pairs and how many times a post was marked duplicate
duplicate_links AS (
  SELECT pl.PostId AS duplicate_post, pl.RelatedPostId AS original_post, COUNT(*) AS times_linked
  FROM PostLinks pl
  WHERE pl.LinkTypeId = 3
  GROUP BY pl.PostId, pl.RelatedPostId
),
-- user badges summary with last badge via correlated subquery and windowed medal counts
badge_summary AS (
  SELECT b.UserId AS user_id,
         COUNT(*) AS badge_count,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
         SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver,
         SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze,
         (SELECT Name FROM Badges b2 WHERE b2.UserId = b.UserId ORDER BY b2.Date DESC LIMIT 1) AS last_badge_name,
         MAX(b.Date) AS last_badge_date
  FROM Badges b
  GROUP BY b.UserId
),
-- recent moderation-like events per post from PostHistory (closures, deletes, etc.)
moderation_events AS (
  SELECT ph.PostId,
         ph.PostHistoryTypeId,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (10,11,12,13,14,15)) AS mod_event_count,
         MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (10,11,12,13,14,15)) AS last_mod_event
  FROM PostHistory ph
  GROUP BY ph.PostId, ph.PostHistoryTypeId
),
-- users with no posts (for set operator demo)
users_with_posts AS (
  SELECT DISTINCT OwnerUserId AS user_id FROM Posts WHERE OwnerUserId IS NOT NULL
),
all_users AS (
  SELECT Id AS user_id FROM Users
),
users_without_posts AS (
  SELECT * FROM all_users
  EXCEPT
  SELECT * FROM users_with_posts
),
-- computed heavy expression for benchmarking: nested correlated subquery that computes decay-weighted score per user
decay_scores AS (
  SELECT u.Id AS user_id,
         CAST((
           SELECT SUM(p.Score * POWER(0.85, EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate))/86400.0))
           FROM Posts p
           WHERE p.OwnerUserId = u.Id
         ) AS numeric(18,6)) AS decay_weighted_score
  FROM Users u
),
-- final ranking of active users by mixed metric using window functions and various NULL logic
user_rank AS (
  SELECT ups.user_id,
         ups.DisplayName,
         COALESCE(ups.question_count,0) AS q_count,
         COALESCE(ups.answer_count,0) AS a_count,
         COALESCE(ups.total_score,0) AS total_score,
         COALESCE(bs.badge_count,0) AS badge_count,
         COALESCE(ds.decay_weighted_score,0) AS decay_score,
         tp.tag_name AS top_tag,
         tp.popularity_rank AS tag_rank,
         ROW_NUMBER() OVER (ORDER BY (COALESCE(ups.total_score,0) * 0.6 + COALESCE(ds.decay_weighted_score,0) * 0.4 + COALESCE(bs.badge_count,0) * 2) DESC, ups.last_post_date DESC NULLS LAST) AS overall_rank
  FROM user_post_stats ups
  LEFT JOIN badge_summary bs ON bs.user_id = ups.user_id
  LEFT JOIN decay_scores ds ON ds.user_id = ups.user_id
  LEFT JOIN LATERAL (
    SELECT tag_name, popularity_rank FROM tag_popularity tp
    WHERE tp.tag_name IS NOT NULL
    ORDER BY tp.tag_count DESC NULLS LAST
    LIMIT 1
  ) tp ON true
)
SELECT
  ur.overall_rank,
  ur.user_id,
  COALESCE(ur.DisplayName, '<anonymous>') AS display_name,
  ur.q_count,
  ur.a_count,
  ur.total_score,
  ROUND(CAST(ur.decay_score AS numeric),6) AS decay_weighted_score,
  ur.badge_count,
  COALESCE(ur.top_tag,'<none>') AS top_tag,
  ur.tag_rank,
  CASE
    WHEN ur.q_count = 0 AND ur.a_count = 0 THEN 'no-contributions'
    WHEN ur.q_count > ur.a_count THEN 'questioner'
    WHEN ur.a_count > ur.q_count THEN 'answerer'
    ELSE 'balanced'
  END AS contribution_profile,
  -- correlated existence check for duplicates authored by user's questions
  EXISTS (
    SELECT 1 FROM duplicate_links dl
    JOIN Posts p2 ON p2.Id = dl.duplicate_post
    WHERE p2.OwnerUserId = ur.user_id
  ) AS has_duplicates,
  -- scalar correlated subquery returning aggregated recent post titles
  (SELECT string_agg(
            LEFT(COALESCE(NULLIF(p.Title,''), '<<no title>>') || ' [' || COALESCE(CAST(p.Score AS text),'0') || ']', 120),
            ' || '
          )
   FROM (
     SELECT p.Title, p.Score
     FROM Posts p
     WHERE p.OwnerUserId = ur.user_id
     ORDER BY p.LastActivityDate DESC NULLS LAST
     LIMIT 3
   ) p
  ) AS recent_titles,
  -- join to show if user is in users_without_posts
  CASE WHEN uwp.user_id IS NOT NULL THEN true ELSE false END AS has_no_posts
FROM user_rank ur
LEFT JOIN users_without_posts uwp ON uwp.user_id = ur.user_id
WHERE (ur.total_score > 0 OR ur.decay_score > 0 OR ur.badge_count > 0)
  AND ur.overall_rank <= 200
ORDER BY ur.overall_rank ASC;