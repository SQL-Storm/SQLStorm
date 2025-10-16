-- {"query": "97.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2098} 
WITH
-- Recent active users with aggregated badge and post stats
recent_users AS (
  SELECT
    u.Id AS user_id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(u.Location,'<none>') AS location,
    COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS gold_badges,
    COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS silver_badges,
    COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS bronze_badges,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions_count,
    COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers_count,
    SUM(COALESCE(p.Score,0)) AS total_post_score,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST, u.LastAccessDate DESC) AS rn
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE u.LastAccessDate >= (CURRENT_TIMESTAMP - INTERVAL '365 days')
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
  HAVING COUNT(DISTINCT p.Id) >= 1
),
-- Top posts per user (complex: string ops, tag parsing, null handling)
user_top_posts AS (
  SELECT
    ru.user_id,
    p.Id AS post_id,
    p.PostTypeId,
    p.Title,
    COALESCE(NULLIF(trim(both ' ' from p.Tags), ''), '<no-tags>') AS raw_tags,
    -- emulate tag array: extract tags between angle brackets
    regexp_split_to_array(substring(COALESCE(p.Tags,''), 2, greatest(length(p.Tags)-2,0)), '><') AS tag_array,
    COALESCE(p.Score,0) AS score,
    COALESCE(p.ViewCount,0) AS views,
    p.CreationDate,
    p.AnswerCount,
    -- computed hotness: nonlinear combination, include null-aware math
    (COALESCE(p.Score,0) * 3.0 + ln(1 + COALESCE(p.ViewCount,0)) * 2.0
      + COALESCE(p.AnswerCount,0) * 1.5
      - EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.CreationDate))/86400.0 * 0.1) AS hotness,
    ROW_NUMBER() OVER (PARTITION BY ru.user_id ORDER BY (COALESCE(p.Score,0)*3 + COALESCE(p.ViewCount,0)) DESC NULLS LAST, p.CreationDate DESC) AS post_rank
  FROM recent_users ru
  JOIN Posts p ON p.OwnerUserId = ru.user_id
  WHERE p.PostTypeId IN (1,2)
),
-- Aggregate per-tag statistics across selected posts using UNNEST (set operator flavor)
tag_stats AS (
  SELECT
    tag,
    COUNT(*) AS posts_with_tag,
    SUM(score) AS sum_score,
    AVG(hotness) AS avg_hotness,
    MAX(views) AS max_views,
    MIN(CreationDate) AS oldest_post
  FROM (
    SELECT utp.*, unnest(tag_array) AS tag FROM user_top_posts utp
  ) t
  GROUP BY tag
),
-- correlated subquery example: recent duplicate link activity per user's questions
dup_link_activity AS (
  SELECT
    q.OwnerUserId AS user_id,
    COUNT(pl.Id) AS duplicate_links_to,
    MAX(pl.CreationDate) AS last_duplicate_link_date,
    SUM(CASE WHEN EXISTS (
        SELECT 1 FROM Posts p2
        WHERE p2.Id = pl.RelatedPostId AND p2.Score > 0
      ) THEN 1 ELSE 0 END) AS related_positive_score_count
  FROM Posts q
  LEFT JOIN PostLinks pl ON pl.PostId = q.Id AND pl.LinkTypeId = 3
  WHERE q.PostTypeId = 1 AND q.OwnerUserId IS NOT NULL
    AND q.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '730 days')
  GROUP BY q.OwnerUserId
),
-- windowed user ranking with mixed metrics and NULL logic
user_rankings AS (
  SELECT
    ru.*,
    COALESCE(dua.duplicate_links_to,0) AS duplicate_links_to,
    COALESCE(dua.related_positive_score_count,0) AS related_positive_score_count,
    COALESCE(ts_top.posts_with_tag,0) AS top_tag_post_count,
    -- composite score mixing reputation, posts, badges, hotness and tag influence
    (ru.Reputation * 0.25
     + GREATEST(ru.total_post_score,0) * 0.35
     + (ru.gold_badges * 10 + ru.silver_badges * 3 + ru.bronze_badges * 1) * 2
     + COALESCE(ts_top.avg_hotness,0) * 5
     - COALESCE(duplicate_links_to,0) * 1.5
     + LEAST(related_positive_score_count,10) * 0.5) AS composite_score,
    RANK() OVER (ORDER BY
      (ru.Reputation * 0.25 + COALESCE(ru.total_post_score,0) * 0.35) DESC,
      COALESCE(ts_top.avg_hotness,0) DESC
    ) AS reputation_rank
  FROM recent_users ru
  LEFT JOIN dup_link_activity dua ON dua.user_id = ru.user_id
  LEFT JOIN (
    -- per-user aggregated tag stats: choose their top tag by posts_with_tag
    SELECT
      u_id,
      MAX(posts_with_tag) AS posts_with_tag,
      AVG(avg_hotness) AS avg_hotness
    FROM (
      SELECT
        utp.user_id AS u_id,
        tag,
        COUNT(*) OVER (PARTITION BY utp.user_id, tag) AS posts_with_tag,
        AVG(hotness) OVER (PARTITION BY utp.user_id, tag) AS avg_hotness,
        ROW_NUMBER() OVER (PARTITION BY utp.user_id, tag ORDER BY AVG(hotness) DESC) rn
      FROM (
        SELECT user_id, hotness, unnest(tag_array) AS tag
        FROM user_top_posts
      ) utp
    ) s
    GROUP BY u_id
  ) ts_top ON ts_top.u_id = ru.user_id
),
-- final selection: combine many constructs, correlated scalar subqueries, set operators, and NULL logic
final_selection AS (
  SELECT
    ur.user_id,
    ur.DisplayName,
    ur.Reputation,
    ur.reputation_rank,
    ur.composite_score,
    ur.questions_count,
    ur.answers_count,
    ur.gold_badges, ur.silver_badges, ur.bronze_badges,
    ur.duplicate_links_to,
    ur.related_positive_score_count,
    COALESCE(ts.tag, '<none>') AS top_tag,
    COALESCE(ts.avg_hotness,0) AS top_tag_avg_hotness,
    -- scalar correlated subquery: count of distinct answerers to this user's questions in last year
    (SELECT COUNT(DISTINCT a.OwnerUserId)
     FROM Posts q
     JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
     WHERE q.OwnerUserId = ur.user_id
       AND q.PostTypeId = 1
       AND a.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '365 days')
       AND a.OwnerUserId IS NOT NULL) AS distinct_answerers_last_year,
    -- another correlated subquery: existence of any high-score accepted answers
    CASE WHEN EXISTS (
      SELECT 1 FROM Posts q2
      JOIN Posts a2 ON a2.Id = q2.AcceptedAnswerId
      WHERE q2.OwnerUserId = ur.user_id AND a2.Score >= 100
    ) THEN 1 ELSE 0 END AS has_high_score_accepted,
    -- string expression combining display name and location, handling NULLs and embedded commas
    (COALESCE(ur.DisplayName,'<anon>') || ' @ ' || REPLACE(COALESCE(NULLIF(ur.location,'<none>'),'<unknown>'), ',', ';')) AS display_location,
    -- percentile over composite_score within window
    PERCENT_RANK() OVER (ORDER BY ur.composite_score) AS composite_percentile
  FROM user_rankings ur
  LEFT JOIN (
    SELECT tag, avg_hotness
    FROM tag_stats ts
    WHERE ts.posts_with_tag > 2
    ORDER BY ts.avg_hotness DESC NULLS LAST
    LIMIT 1
  ) ts ON true
  WHERE ur.rn <= 500
)
-- final output: combine with UNION to create set operators, plus an anti-join for users without tags
SELECT * FROM final_selection
UNION
SELECT
  fs.user_id,
  fs.DisplayName || ' (no-tag)',
  fs.Reputation,
  fs.reputation_rank,
  fs.composite_score,
  fs.questions_count,
  fs.answers_count,
  fs.gold_badges, fs.silver_badges, fs.bronze_badges,
  fs.duplicate_links_to,
  fs.related_positive_score_count,
  '<none>' AS top_tag,
  0.0 AS top_tag_avg_hotness,
  fs.distinct_answerers_last_year,
  fs.has_high_score_accepted,
  fs.display_location,
  fs.composite_percentile
FROM final_selection fs
WHERE fs.top_tag = '<none>'
ORDER BY composite_score DESC, Reputation DESC, user_id
LIMIT 200;