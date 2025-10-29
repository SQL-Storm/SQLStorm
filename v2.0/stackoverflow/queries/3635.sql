WITH
    user_stats AS (
        SELECT
            u.id                         AS user_id,
            u.displayname                AS display_name,
            u.reputation,
            COALESCE(SUM(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END), 0) AS up_votes_given,
            COALESCE(SUM(CASE WHEN v.votetypeid = 3 THEN 1 ELSE 0 END), 0) AS down_votes_given,
            (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 1) AS gold_badges,
            (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 2) AS silver_badges,
            (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 3) AS bronze_badges
        FROM users u
        LEFT JOIN votes v ON v.userid = u.id
        GROUP BY u.id, u.displayname, u.reputation
    ),
    question_metrics AS (
        SELECT
            p.id                                 AS q_id,
            p.owneruserid                        AS owner_user_id,
            p.creationdate,
            p.score,
            p.viewcount,
            p.answercount,
            p.favoritecount,
            COALESCE(p.tags, '')                 AS tags_raw,
            ROW_NUMBER() OVER (PARTITION BY p.owneruserid ORDER BY p.score DESC) AS rank_by_score,
            COUNT(*) OVER (PARTITION BY p.owneruserid)                         AS total_questions,
            LAG(p.score) OVER (PARTITION BY p.owneruserid ORDER BY p.creationdate) AS prev_score,
            LEAD(p.score) OVER (PARTITION BY p.owneruserid ORDER BY p.creationdate) AS next_score
        FROM posts p
        WHERE p.posttypeid = 1
          AND p.creationdate >= DATE '2020-01-01'
    ),
    tag_explode AS (
        SELECT
            qm.q_id,
            UNNEST(string_to_array(TRIM(BOTH '<>' FROM qm.tags_raw), '><')) AS tag
        FROM question_metrics qm
        WHERE qm.tags_raw <> ''
    ),
    tag_stats AS (
        SELECT
            te.tag,
            COUNT(DISTINCT te.q_id)                           AS questions_with_tag,
            SUM(qm.score)                                     AS total_tag_score,
            ROUND(AVG(qm.viewcount::numeric), 2)               AS avg_tag_views
        FROM tag_explode te
        JOIN question_metrics qm ON qm.q_id = te.q_id
        GROUP BY te.tag
        HAVING COUNT(DISTINCT te.q_id) > 10
    ),
    top_tag_pairs AS (
        SELECT
            t1.tag AS tag_a,
            t2.tag AS tag_b,
            COUNT(*) AS pair_cnt
        FROM tag_explode t1
        JOIN tag_explode t2
          ON t1.q_id = t2.q_id
         AND t1.tag < t2.tag
        GROUP BY t1.tag, t2.tag
        ORDER BY pair_cnt DESC
        LIMIT 20
    )
SELECT
    us.user_id,
    us.display_name,
    us.reputation,
    us.up_votes_given,
    us.down_votes_given,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    q.q_id,
    q.score,
    q.viewcount,
    q.answercount,
    q.favoritecount,
    q.rank_by_score,
    q.total_questions,
    COALESCE(q.prev_score, 0)            AS prev_score,
    COALESCE(q.next_score, 0)            AS next_score,
    CASE
        WHEN q.tags_raw ILIKE '%<java>%'
            THEN 'Java'
        WHEN q.tags_raw ILIKE '%<c%>%'
            THEN 'C-family'
        ELSE 'Other'
    END                                 AS primary_tag_category,
    COALESCE(ts.questions_with_tag, 0)  AS tag_popularity,
    COALESCE(ts.total_tag_score, 0)     AS tag_total_score,
    COALESCE(ts.avg_tag_views, 0)       AS tag_avg_views
FROM users u
LEFT JOIN user_stats us ON us.user_id = u.id
LEFT JOIN LATERAL (
    SELECT qm.q_id, qm.owner_user_id, qm.creationdate, qm.score, qm.viewcount, qm.answercount, qm.favoritecount, qm.tags_raw, qm.rank_by_score, qm.total_questions, qm.prev_score, qm.next_score
    FROM question_metrics qm
    WHERE qm.owner_user_id = u.id
    ORDER BY qm.score DESC
    LIMIT 5
) q ON TRUE
LEFT JOIN LATERAL (
    SELECT ts.questions_with_tag, ts.total_tag_score, ts.avg_tag_views
    FROM tag_stats ts
    WHERE ts.tag = (
        (string_to_array(TRIM(BOTH '<>' FROM q.tags_raw), '><'))[1]
    )
) ts ON TRUE
WHERE u.reputation > 5000
  AND (us.gold_badges + us.silver_badges) > 10
  AND EXISTS (
        SELECT 1
        FROM badges b
        WHERE b.userid = u.id
          AND b.name = 'Great Question'
          AND b.class = 1
      )
UNION ALL
SELECT
    CAST(NULL AS bigint), -- user_id
    CAST(NULL AS text),  -- display_name
    CAST(NULL AS integer), -- reputation
    CAST(NULL AS integer), -- up_votes_given
    CAST(NULL AS integer), -- down_votes_given
    CAST(NULL AS integer), -- gold_badges
    CAST(NULL AS integer), -- silver_badges
    CAST(NULL AS integer), -- bronze_badges
    CAST(NULL AS bigint), -- q_id
    CAST(NULL AS integer), -- score
    CAST(NULL AS integer), -- viewcount
    CAST(NULL AS integer), -- answercount
    CAST(NULL AS integer), -- favoritecount
    CAST(NULL AS integer), -- rank_by_score
    CAST(NULL AS integer), -- total_questions
    CAST(NULL AS integer), -- prev_score
    CAST(NULL AS integer), -- next_score
    CAST(NULL AS text), -- primary_tag_category
    CAST(NULL AS integer), -- tag_popularity
    CAST(NULL AS integer), -- tag_total_score
    CAST(NULL AS numeric)  -- tag_avg_views
FROM (SELECT 1) gs;