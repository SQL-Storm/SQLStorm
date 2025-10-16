-- {"query": "130.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2094} 
WITH
-- recent posts within last year with tag exploded
recent_posts AS (
  SELECT p.*, 
         COALESCE(p.OwnerUserId, -1) AS owner_id,
         regexp_split_to_table(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), '><') AS tag
  FROM Posts p
  WHERE p.CreationDate >= (now() - interval '1 year')
),
-- aggregate per user: counts, avg score, views, answer/question split
user_activity AS (
  SELECT
    u.Id AS user_id,
    u.DisplayName,
    COUNT(rp.Id) FILTER (WHERE rp.PostTypeId = 1) AS questions_last_year,
    COUNT(rp.Id) FILTER (WHERE rp.PostTypeId = 2) AS answers_last_year,
    COUNT(rp.Id) AS posts_last_year,
    COALESCE(AVG(rp.Score),0)::numeric(10,4) AS avg_score_last_year,
    COALESCE(SUM(rp.ViewCount),0) AS views_last_year,
    MAX(rp.CreationDate) AS last_post_date,
    COUNT(DISTINCT rp.tag) AS distinct_tags_last_year
  FROM Users u
  LEFT JOIN recent_posts rp ON rp.owner_id = u.Id
  GROUP BY u.Id, u.DisplayName
),
-- top tag per user by occurrences (uses window)
user_top_tags AS (
  SELECT user_id, tag, tag_count FROM (
    SELECT ua.user_id,
           rt.tag,
           COUNT(*) AS tag_count,
           ROW_NUMBER() OVER (PARTITION BY ua.user_id ORDER BY COUNT(*) DESC, rt.tag) rn
    FROM recent_posts rt
    JOIN Users u ON rt.owner_id = u.Id
    JOIN user_activity ua ON ua.user_id = u.Id
    GROUP BY ua.user_id, rt.tag
  ) t
  WHERE rn = 1
),
-- badge counts and latest badge
user_badges AS (
  SELECT b.UserId AS user_id,
         COUNT(*) AS badge_count,
         COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badges,
         COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badges,
         COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_badges,
         MAX(b.Date) AS last_badge_date
  FROM Badges b
  GROUP BY b.UserId
),
-- last comment (correlated subquery style)
user_last_comment AS (
  SELECT u.Id AS user_id,
         (
           SELECT c.Text
           FROM Comments c
           WHERE c.UserId = u.Id
           ORDER BY c.CreationDate DESC, c.Id DESC
           LIMIT 1
         ) AS last_comment_text,
         (
           SELECT c.CreationDate
           FROM Comments c
           WHERE c.UserId = u.Id
           ORDER BY c.CreationDate DESC, c.Id DESC
           LIMIT 1
         ) AS last_comment_date
  FROM Users u
),
-- compute accepted answer rate and median answer score per user using window
answers_stats AS (
  SELECT a.OwnerUserId AS user_id,
         COUNT(a.Id) AS total_answers,
         SUM(CASE WHEN EXISTS (SELECT 1 FROM Posts q WHERE q.AcceptedAnswerId = a.Id) THEN 1 ELSE 0 END) AS accepted_answers,
         COALESCE(AVG(a.Score),0)::numeric(10,4) AS avg_answer_score,
         PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) OVER (PARTITION BY a.OwnerUserId) AS median_answer_score
  FROM Posts a
  WHERE a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
  GROUP BY a.OwnerUserId
),
-- heavy calculation: reputation velocity (linear regression slope approximation using window first/last)
rep_velocity AS (
  SELECT u.Id AS user_id,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate,
         CASE 
           WHEN extract(epoch FROM (u.LastAccessDate - u.CreationDate)) > 0 
           THEN (u.Reputation::numeric / (extract(epoch FROM (u.LastAccessDate - u.CreationDate)) / 86400.0)) -- rep per day
           ELSE NULL
         END AS rep_per_day
  FROM Users u
),
-- combine everything
combined AS (
  SELECT
    ua.user_id,
    COALESCE(ua.DisplayName, '<<anonymous>>') AS display_name,
    ua.posts_last_year,
    ua.questions_last_year,
    ua.answers_last_year,
    ua.avg_score_last_year,
    ua.views_last_year,
    ua.distinct_tags_last_year,
    utt.tag AS top_tag_last_year,
    COALESCE(ub.badge_count,0) AS badge_count,
    COALESCE(ub.gold_badges,0) AS gold_badges,
    COALESCE(ub.silver_badges,0) AS silver_badges,
    COALESCE(ub.bronze_badges,0) AS bronze_badges,
    COALESCE(us.last_comment_text, '') AS last_comment_text,
    us.last_comment_date,
    COALESCE(ans.total_answers,0) AS total_answers,
    COALESCE(ans.accepted_answers,0) AS accepted_answers,
    CASE WHEN COALESCE(ans.total_answers,0) = 0 THEN NULL
         ELSE ROUND((COALESCE(ans.accepted_answers,0)::numeric / ans.total_answers) * 100,2)
    END AS accepted_rate_pct,
    COALESCE(ans.avg_answer_score,0) AS avg_answer_score,
    ans.median_answer_score,
    rv.rep_per_day,
    -- funky expression mixing NULL logic and strings
    CONCAT(
      substring(COALESCE(ua.DisplayName, 'User#'||ua.user_id::text), 1, 20),
      ' | tags:',
      COALESCE(utt.tag, 'none'),
      ' | badges:',
      COALESCE(ub.badge_count,0)::text
    ) AS summary_label
  FROM user_activity ua
  LEFT JOIN user_top_tags utt ON utt.user_id = ua.user_id
  LEFT JOIN user_badges ub ON ub.user_id = ua.user_id
  LEFT JOIN user_last_comment us ON us.user_id = ua.user_id
  LEFT JOIN answers_stats ans ON ans.user_id = ua.user_id
  LEFT JOIN rep_velocity rv ON rv.user_id = ua.user_id
)
-- final selection: rank users by composite score, show percentile windows, include correlated filter and a set operator to exclude zero-post users
SELECT *
FROM (
  SELECT
    c.*,
    -- composite benchmarking score: weighted combination with NULL-safe handling
    (COALESCE(c.posts_last_year,0) * 1.5
     + COALESCE(c.avg_score_last_year,0) * 5
     + COALESCE(c.views_last_year,0) / GREATEST(NULLIF(c.posts_last_year,0),1) * 0.2
     + COALESCE(c.badge_count,0) * 2
     + COALESCE(c.rep_per_day,0) * 10
     + COALESCE(c.accepted_rate_pct,0) * 0.1
    ) AS perf_score,
    ROW_NUMBER() OVER (ORDER BY 
        (COALESCE(c.posts_last_year,0) * 1.5
         + COALESCE(c.avg_score_last_year,0) * 5
         + COALESCE(c.badge_count,0) * 2
         + COALESCE(c.rep_per_day,0) * 10
        ) DESC,
        COALESCE(c.last_comment_date, to_timestamp(0)) DESC
    ) AS rn,
    RANK() OVER (ORDER BY COALESCE(c.posts_last_year,0) DESC) AS post_rank,
    NTILE(100) OVER (ORDER BY COALESCE(c.posts_last_year,0) DESC) AS post_percentile
  FROM combined c
) ranked
WHERE rn <= 500
EXCEPT
-- exclude users who have zero posts across the entire site (not just last year) by set operator
SELECT
  u.Id AS user_id,
  u.DisplayName,
  0,0,0,0,0,0,NULL,NULL,0,0,'',NULL,0,0,NULL,NULL,NULL,NULL,'' ,  -- dummy placeholders to match column count
  0,0,0
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
WHERE p.Id IS NULL
ORDER BY perf_score DESC NULLS LAST, posts_last_year DESC, avg_score_last_year DESC;