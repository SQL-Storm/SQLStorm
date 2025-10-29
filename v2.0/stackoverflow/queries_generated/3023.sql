-- {"query": "3023.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2634} 

WITH
    /* Aggregate badge counts per user */
    badge_counts AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_cnt
        FROM Badges b
        GROUP BY b.UserId
    ),

    /* Core user statistics */
    user_stats AS (
        SELECT
            u.Id                     AS user_id,
            u.DisplayName,
            u.Reputation,
            COALESCE(bc.gold_cnt,   0) AS gold_badges,
            COALESCE(bc.silver_cnt, 0) AS silver_badges,
            COALESCE(bc.bronze_cnt, 0) AS bronze_badges,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions_asked,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers_given,
            SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS answer_score,
            MAX(p.CreationDate)                     AS last_post_dt,
            ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS rn_posts
        FROM Users u
        LEFT JOIN badge_counts bc ON bc.UserId = u.Id
        LEFT JOIN Posts p        ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, bc.gold_cnt, bc.silver_cnt, bc.bronze_cnt
    ),

    /* Filter to high‑reputation users */
    top_users AS (
        SELECT *
        FROM user_stats
        WHERE Reputation > 10000
        ORDER BY Reputation DESC
        LIMIT 100
    ),

    /* Detailed answer metrics per user */
    answer_metrics AS (
        SELECT
            a.OwnerUserId                           AS user_id,
            COUNT(*)                                AS total_answers,
            AVG(a.Score)                            AS avg_answer_score,
            PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY a.Score) OVER (PARTITION BY a.OwnerUserId) AS p90_score,
            SUM(CASE WHEN a.Id = p.AcceptedAnswerId THEN 1 ELSE 0 END) AS accepted_answers,
            MAX(a.CreationDate)                     AS last_answer_dt
        FROM Posts a
        JOIN Posts p ON p.Id = a.ParentId AND p.PostTypeId = 1   -- parent question
        WHERE a.PostTypeId = 2
        GROUP BY a.OwnerUserId
    ),

    /* Tag usage per user (questions only) */
    tag_activity AS (
        SELECT
            q.OwnerUserId                             AS user_id,
            COUNT(DISTINCT UNNEST(string_to_array(REPLACE(REPLACE(q.Tags,'<',''),'>',''), '><'))) AS distinct_tags,
            STRING_AGG(DISTINCT UNNEST(string_to_array(REPLACE(REPLACE(q.Tags,'<',''),'>',''), '><')), ',')
                FILTER (WHERE q.Tags IS NOT NULL)    AS tag_list
        FROM Posts q
        WHERE q.PostTypeId = 1 AND q.Tags IS NOT NULL
        GROUP BY q.OwnerUserId
    ),

    /* Recent vote snapshot (last 30 days) */
    recent_votes AS (
        SELECT
            v.PostId,
            v.VoteTypeId,
            v.UserId           AS voter_id,
            v.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS vote_rank
        FROM Votes v
        WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    ),

    /* Close/reopen info for the latest question of each user */
    post_close_info AS (
        SELECT
            ph.PostId,
            MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END)      AS close_reason_code,
            MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS close_dt,
            MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS reopen_dt
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (10,11)
        GROUP BY ph.PostId
    ),

    /* Compose the final report */
    final_report AS (
        SELECT
            tu.user_id,
            tu.DisplayName,
            tu.Reputation,
            tu.gold_badges,
            tu.silver_badges,
            tu.bronze_badges,
            tu.questions_asked,
            tu.answers_given,
            tu.answer_score,
            am.total_answers,
            am.avg_answer_score,
            am.p90_score,
            am.accepted_answers,
            ta.distinct_tags,
            COALESCE(ta.tag_list, '')               AS tag_list,
            COALESCE(pci.close_reason_code, '0')    AS close_reason,
            pci.close_dt,
            pci.reopen_dt,
            EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - tu.last_post_dt))/86400 AS days_since_last_post,
            EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - am.last_answer_dt))/86400 AS days_since_last_answer,
            CASE
                WHEN tu.Reputation > 20000 THEN 'Elite'
                WHEN tu.Reputation > 10000 THEN 'High'
                ELSE 'Mid'
            END                                      AS reputation_tier
        FROM top_users tu
        LEFT JOIN answer_metrics am   ON am.user_id = tu.user_id
        LEFT JOIN tag_activity ta      ON ta.user_id = tu.user_id
        LEFT JOIN LATERAL (
            SELECT pc.*
            FROM post_close_info pc
            WHERE pc.PostId = (
                SELECT p.Id
                FROM Posts p
                WHERE p.OwnerUserId = tu.user_id
                  AND p.PostTypeId = 1
                ORDER BY p.CreationDate DESC
                LIMIT 1
            )
            LIMIT 1
        ) pci ON TRUE
    )

SELECT *
FROM final_report
WHERE reputation_tier <> 'Mid'
ORDER BY Reputation DESC
OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY

UNION ALL

SELECT
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
WHERE FALSE;
