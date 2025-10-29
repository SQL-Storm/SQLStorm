-- {"query": "3112.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2347} 

/*  Benchmarking query – combines CTEs, window functions, outer joins, 
    correlated subqueries, set operators, complex predicates, string ops & NULL logic   */
WITH RECURSIVE
-- 1️⃣ User basic activity aggregates
user_stats AS (
    SELECT
        u.id                                   AS user_id,
        u.displayname                          AS display_name,
        u.reputation,
        COUNT(DISTINCT p.id) FILTER (WHERE p.posttypeid = 1)  AS questions_asked,
        COUNT(DISTINCT p.id) FILTER (WHERE p.posttypeid = 2)  AS answers_given,
        COALESCE(SUM(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END),0) AS upvotes_given,
        COALESCE(SUM(CASE WHEN v.votetypeid = 3 THEN 1 ELSE 0 END),0) AS downvotes_given,
        COALESCE(SUM(b.class),0)               AS badge_points
    FROM users u
    LEFT JOIN posts      p ON p.owneruserid = u.id
    LEFT JOIN votes      v ON v.userid = u.id
    LEFT JOIN badges     b ON b.userid = u.id
    GROUP BY u.id, u.displayname, u.reputation
),

-- 2️⃣ Most recent activity per user (question, answer, comment)
recent_activity AS (
    SELECT
        u.id                                                  AS user_id,
        GREATEST(
            MAX(p.creationdate)      FILTER (WHERE p.posttypeid = 1),
            MAX(a.creationdate)      FILTER (WHERE a.posttypeid = 2),
            MAX(c.creationdate)      FILTER (WHERE c.userid IS NOT NULL)
        )                                                     AS most_recent_ts
    FROM users u
    LEFT JOIN posts   p ON p.owneruserid = u.id AND p.posttypeid = 1
    LEFT JOIN posts   a ON a.owneruserid = u.id AND a.posttypeid = 2
    LEFT JOIN comments c ON c.userid = u.id
    GROUP BY u.id
),

-- 3️⃣ Tag usage derived from question posts (using LATERAL split)
tag_usage AS (
    SELECT
        u.id                                          AS user_id,
        COUNT(DISTINCT t.tagname)                     AS distinct_tags,
        STRING_AGG(DISTINCT t.tagname, ',') 
            FILTER (WHERE t.tagname IS NOT NULL)      AS tag_list
    FROM users u
    JOIN posts p ON p.owneruserid = u.id AND p.posttypeid = 1
    LEFT JOIN LATERAL (
        SELECT regexp_split_to_table(p.tags, '[><]') AS tag
    ) AS split_tags ON true
    LEFT JOIN tags t ON t.tagname = split_tags.tag
    GROUP BY u.id
),

-- 4️⃣ Combine everything, rank by reputation + badge points
combined AS (
    SELECT
        us.user_id,
        us.display_name,
        us.reputation,
        us.questions_asked,
        us.answers_given,
        us.upvotes_given,
        us.downvotes_given,
        us.badge_points,
        ra.most_recent_ts,
        tu.distinct_tags,
        tu.tag_list,
        ROW_NUMBER() OVER (
            ORDER BY us.reputation DESC, us.badge_points DESC
        ) AS rep_rank
    FROM user_stats      us
    LEFT JOIN recent_activity ra ON ra.user_id = us.user_id
    LEFT JOIN tag_usage       tu ON tu.user_id = us.user_id
    WHERE us.questions_asked > 0                     -- must have asked
      AND us.answers_given   > 0                     -- must have answered
      AND us.reputation IS NOT NULL
),

-- 5️⃣ Top‑100 users according to the ranking
top_users AS (
    SELECT *
    FROM combined
    WHERE rep_rank <= 100
),

-- 6️⃣ Correlated sub‑query to fetch the most up‑voted answer per user (for benchmarking joins)
user_best_answer AS (
    SELECT
        a.owneruserid                     AS user_id,
        a.id                               AS answer_id,
        a.score                            AS answer_score,
        ROW_NUMBER() OVER (PARTITION BY a.owneruserid 
                           ORDER BY a.score DESC, a.creationdate) AS rn
    FROM posts a
    WHERE a.posttypeid = 2
),

-- 7️⃣ Final set: detailed rows + an aggregated summary (UNION ALL)
detailed AS (
    SELECT
        tu.user_id,
        tu.display_name,
        tu.reputation,
        tu.rep_rank,
        tu.questions_asked,
        tu.answers_given,
        tu.upvotes_given,
        tu.downvotes_given,
        tu.badge_points,
        tu.most_recent_ts,
        tu.distinct_tags,
        CASE
            WHEN tu.distinct_tags >= 10 THEN 'Power User'
            WHEN tu.distinct_tags >= 5  THEN 'Active Tagger'
            ELSE 'Niche Contributor'
        END                             AS tagger_level,
        COALESCE(NULLIF(tu.tag_list, ''), 'No Tags') AS tags_used,
        uba.answer_id,
        uba.answer_score
    FROM top_users tu
    LEFT JOIN user_best_answer uba 
        ON uba.user_id = tu.user_id AND uba.rn = 1
),

summary AS (
    SELECT
        -1                                       AS user_id,
        'Aggregated Summary'                     AS display_name,
        NULL                                     AS reputation,
        NULL                                     AS rep_rank,
        SUM(questions_asked)                     AS questions_asked,
        SUM(answers_given)                       AS answers_given,
        SUM(upvotes_given)                       AS upvotes_given,
        SUM(downvotes_given)                     AS downvotes_given,
        SUM(badge_points)                        AS badge_points,
        MAX(most_recent_ts)                      AS most_recent_ts,
        COUNT(DISTINCT tags_used)                AS distinct_tags,
        NULL                                     AS tagger_level,
        NULL                                     AS tags_used,
        NULL                                     AS answer_id,
        NULL                                     AS answer_score
    FROM detailed
)

SELECT *
FROM detailed
UNION ALL
SELECT *
FROM summary
ORDER BY rep_rank NULLS LAST, user_id;
