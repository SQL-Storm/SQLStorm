-- {"query": "3423.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2570} 

/* Performance‑benchmarking query */
WITH
    /* 1️⃣ User activity aggregates */
    user_stats AS (
        SELECT
            u.Id                                   AS user_id,
            u.DisplayName,
            u.Reputation,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1)               AS question_cnt,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2)               AS answer_cnt,
            SUM(COALESCE(p.Score,0))                              AS total_score,
            MAX(p.CreationDate)                                   AS last_post_dt
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    /* 2️⃣ Badge breakdown per user */
    badge_stats AS (
        SELECT
            b.UserId                                   AS user_id,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)   AS gold_cnt,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)   AS silver_cnt,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)   AS bronze_cnt,
            COUNT(*)                                      AS total_badges,
            STRING_AGG(DISTINCT b.Name, ',')
                FILTER (WHERE b.Class = 1)               AS gold_names
        FROM Badges b
        GROUP BY b.UserId
    ),

    /* 3️⃣ Tag usage per user (questions only) */
    tag_activity AS (
        SELECT
            p.OwnerUserId                               AS user_id,
            UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2),
                                   '><'))                AS tag,
            COUNT(*)                                    AS posts_per_tag,
            SUM(p.Score)                                AS score_per_tag
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, tag
    ),

    /* 4️⃣ Rank tags per user */
    top_tags AS (
        SELECT
            ta.user_id,
            ta.tag,
            ta.posts_per_tag,
            ta.score_per_tag,
            RANK() OVER (PARTITION BY ta.user_id
                         ORDER BY ta.score_per_tag DESC)   AS tag_rank
        FROM tag_activity ta
    ),

    /* 5️⃣ Overall user ranking */
    user_rankings AS (
        SELECT
            us.user_id,
            us.DisplayName,
            us.Reputation,
            us.question_cnt,
            us.answer_cnt,
            us.total_score,
            bs.gold_cnt,
            bs.silver_cnt,
            bs.bronze_cnt,
            ROW_NUMBER() OVER (ORDER BY us.total_score DESC) AS overall_rank,
            ROW_NUMBER() OVER (ORDER BY us.Reputation DESC)  AS rep_rank
        FROM user_stats us
        LEFT JOIN badge_stats bs ON bs.user_id = us.user_id
    ),

    /* 6️⃣ Recent month activity (votes, comments, links) */
    recent_month AS (
        SELECT
            u.Id                                          AS user_id,
            COALESCE(vc.vote_delta,0)                     AS vote_delta_30d,
            COALESCE(cm.comment_cnt,0)                    AS comment_cnt_30d,
            COALESCE(pl.link_cnt,0)                       AS linked_posts_30d
        FROM Users u
        LEFT JOIN (
            SELECT
                p.OwnerUserId,
                SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                         WHEN v.VoteTypeId = 3 THEN -1
                         ELSE 0 END)                     AS vote_delta
            FROM Votes v
            JOIN Posts p ON p.Id = v.PostId
            WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 day'
              AND v.VoteTypeId IN (2,3)                     -- up‑/down‑votes
            GROUP BY p.OwnerUserId
        ) vc ON vc.OwnerUserId = u.Id
        LEFT JOIN (
            SELECT
                c.UserId,
                COUNT(*) AS comment_cnt
            FROM Comments c
            WHERE c.CreationDate >= CURRENT_DATE - INTERVAL '30 day'
            GROUP BY c.UserId
        ) cm ON cm.UserId = u.Id
        LEFT JOIN (
            SELECT
                pl.PostId,
                COUNT(*) AS link_cnt
            FROM PostLinks pl
            WHERE pl.CreationDate >= CURRENT_DATE - INTERVAL '30 day'
            GROUP BY pl.PostId
        ) pl ON pl.PostId = u.Id
    ),

    /* 7️⃣ Aggregated summary for UNION */
    summary AS (
        SELECT
            NULL::int                AS user_id,
            'SUMMARY'                AS DisplayName,
            NULL::int                AS Reputation,
            SUM(question_cnt)        AS question_cnt,
            SUM(answer_cnt)          AS answer_cnt,
            SUM(total_score)         AS total_score,
            SUM(gold_cnt)            AS gold_cnt,
            SUM(silver_cnt)          AS silver_cnt,
            SUM(bronze_cnt)          AS bronze_cnt,
            NULL::bigint             AS overall_rank,
            NULL::bigint             AS rep_rank,
            NULL::int                AS vote_delta_30d,
            NULL::int                AS comment_cnt_30d,
            NULL::int                AS linked_posts_30d,
            NULL::varchar            AS tag,
            NULL::int                AS posts_per_tag,
            NULL::int                AS score_per_tag,
            NULL::int                AS tag_rank
        FROM user_rankings
    )

/* 8️⃣ Final result set: top users + their top‑3 tags, plus a summary row */
SELECT
    ur.user_id,
    ur.DisplayName,
    ur.Reputation,
    ur.question_cnt,
    ur.answer_cnt,
    ur.total_score,
    ur.gold_cnt,
    ur.silver_cnt,
    ur.bronze_cnt,
    ur.overall_rank,
    ur.rep_rank,
    rm.vote_delta_30d,
    rm.comment_cnt_30d,
    rm.linked_posts_30d,
    tt.tag,
    tt.posts_per_tag,
    tt.score_per_tag,
    tt.tag_rank
FROM user_rankings ur
LEFT JOIN recent_month rm      ON rm.user_id = ur.user_id
LEFT JOIN top_tags tt         ON tt.user_id = ur.user_id
                               AND tt.tag_rank <= 3
WHERE ur.Reputation > 1000
ORDER BY ur.overall_rank
LIMIT 100

UNION ALL

SELECT * FROM summary
WHERE NOT EXISTS (SELECT 1 FROM user_rankings WHERE Reputation > 1000);
