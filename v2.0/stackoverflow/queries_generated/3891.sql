-- {"query": "3891.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1384} 

/*  Benchmark Query – heavy use of CTEs, window functions, joins, sub‑queries,
    set operators, string manipulation and NULL handling                                  */
WITH 
-- Base user metrics
user_base AS (
    SELECT 
        u.Id                                    AS user_id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS net_votes,
        u.CreationDate,
        EXTRACT(YEAR FROM AGE(CURRENT_TIMESTAMP, u.CreationDate)) AS years_on_site
    FROM Users u
),
-- Badge aggregation (including tag‑based badges)
badge_agg AS (
    SELECT 
        b.UserId                               AS user_id,
        COUNT(*)                               AS total_badges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_badges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_badges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_badges,
        STRING_AGG(DISTINCT b.Name, ';' ORDER BY b.Name) AS badge_list
    FROM Badges b
    GROUP BY b.UserId
),
-- Recent activity per user (last post, last comment, last vote)
activity AS (
    SELECT 
        p.OwnerUserId                         AS user_id,
        MAX(p.CreationDate)                  AS last_post_date,
        MAX(c.CreationDate)                  AS last_comment_date,
        MAX(v.CreationDate)                  AS last_vote_date
    FROM Posts p
    LEFT JOIN Comments c   ON c.UserId = p.OwnerUserId
    LEFT JOIN Votes v      ON v.UserId = p.OwnerUserId
    GROUP BY p.OwnerUserId
),
-- Tag usage derived from questions asked by the user
user_tags AS (
    SELECT 
        p.OwnerUserId                         AS user_id,
        UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId, 
                       UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><'))) AS tag_usage
    FROM Posts p
    WHERE p.PostTypeId = 1                     -- only questions
      AND p.Tags IS NOT NULL
),
-- Top tags overall (used for ranking)
top_tags AS (
    SELECT 
        t.TagName,
        t.Count,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS tag_rank
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
),
-- Correlated subquery to compute a “reputation velocity” per user
reputation_velocity AS (
    SELECT 
        ub.user_id,
        ub.reputation / NULLIF(ub.years_on_site,0) AS rep_per_year,
        (SELECT COUNT(*) 
         FROM Posts p2 
         WHERE p2.OwnerUserId = ub.user_id 
           AND p2.CreationDate >= CURRENT_DATE - INTERVAL '30 days') 
         AS recent_posts_30d
    FROM user_base ub
),
-- Union of “highly active” users and “gold badge holders”
high_activity_or_gold AS (
    SELECT user_id FROM activity
    WHERE GREATEST(
            COALESCE(last_post_date, '1970-01-01')::epoch,
            COALESCE(last_comment_date, '1970-01-01')::epoch,
            COALESCE(last_vote_date, '1970-01-01')::epoch) 
          > EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - INTERVAL '7 days'))
    UNION
    SELECT user_id FROM badge_agg
    WHERE gold_badges > 0
)
SELECT 
    ub.user_id,
    ub.DisplayName,
    ub.reputation,
    ub.net_votes,
    ub.years_on_site,
    rv.rep_per_year,
    rv.recent_posts_30d,
    ba.total_badges,
    ba.gold_badges,
    ba.silver_badges,
    ba.bronze_badges,
    ba.badge_list,
    COALESCE(a.last_post_date, a.last_comment_date, a.last_vote_date) AS most_recent_activity,
    STRING_AGG(DISTINCT ut.tag, ', ' ORDER BY ut.tag_usage DESC) AS top_user_tags,
    STRING_AGG(DISTINCT tt.TagName, ', ' ORDER BY tt.tag_rank)   AS global_top_tags
FROM user_base ub
LEFT JOIN badge_agg ba          ON ba.user_id = ub.user_id
LEFT JOIN activity a           ON a.user_id = ub.user_id
LEFT JOIN reputation_velocity rv ON rv.user_id = ub.user_id
LEFT JOIN user_tags ut         ON ut.user_id = ub.user_id
LEFT JOIN top_tags tt          ON tt.tag_rank <= 5
WHERE ub.user_id IN (SELECT user_id FROM high_activity_or_gold)
GROUP BY 
    ub.user_id, ub.DisplayName, ub.reputation, ub.net_votes,
    ub.years_on_site, rv.rep_per_year, rv.recent_posts_30d,
    ba.total_badges, ba.gold_badges, ba.silver_badges, ba.bronze_badges,
    ba.badge_list, a.last_post_date, a.last_comment_date, a.last_vote_date
ORDER BY rv.rep_per_year DESC NULLS LAST
LIMIT 100;
