-- {"query": "55061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1674} 
WITH
    -- Aggregate basic user activity
    user_stats AS (
        SELECT
            u.id,
            u.displayname,
            u.reputation,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 2)           AS answer_count,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 1)           AS question_count,
            AVG(p.score) FILTER (WHERE p.posttypeid = 2)          AS avg_answer_score,
            SUM(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END)    AS upvotes_received,
            SUM(CASE WHEN v.votetypeid = 3 THEN 1 ELSE 0 END)    AS downvotes_received
        FROM users u
        LEFT JOIN posts p      ON p.owneruserid = u.id
        LEFT JOIN votes v      ON v.postid = p.id
        GROUP BY u.id, u.displayname, u.reputation
    ),

    -- Badge aggregation per user
    badge_stats AS (
        SELECT
            b.userid,
            COUNT(*)                                     AS total_badges,
            COUNT(*) FILTER (WHERE b.class = 1)          AS gold,
            COUNT(*) FILTER (WHERE b.class = 2)          AS silver,
            COUNT(*) FILTER (WHERE b.class = 3)          AS bronze
        FROM badges b
        GROUP BY b.userid
    ),

    -- Tag usage derived from post history (edits that touched tags)
    tag_usage AS (
        SELECT
            ph.userid,
            TRIM(both '<>' FROM t.tag)                  AS tag_name,
            COUNT(*)                                    AS tag_edits
        FROM posthistory ph
        JOIN posts po            ON po.id = ph.postid
        CROSS JOIN LATERAL regexp_split_to_table(po.tags, '><') AS t(tag)
        WHERE ph.posthistorytypeid IN (3,6,9)   -- initial tags, edit tags, rollback tags
          AND ph.userid IS NOT NULL
        GROUP BY ph.userid, tag_name
    ),

    -- Recent link activity (linked/duplicate relationships)
    recent_links AS (
        SELECT
            pl.postid,
            COUNT(*) FILTER (WHERE pl.linktypeid = 1) AS linked_count,
            COUNT(*) FILTER (WHERE pl.linktypeid = 3) AS duplicate_count,
            MAX(pl.creationdate)                      AS last_link_date
        FROM postlinks pl
        WHERE pl.creationdate >= cast('2024-10-01' as date) - INTERVAL '30 days'
        GROUP BY pl.postid
    ),

    -- Rank users by reputation, enriched with stats
    ranked_users AS (
        SELECT
            us.id,
            us.displayname,
            us.reputation,
            us.answer_count,
            us.question_count,
            us.avg_answer_score,
            us.upvotes_received,
            us.downvotes_received,
            bs.total_badges,
            bs.gold,
            bs.silver,
            bs.bronze,
            ROW_NUMBER() OVER (ORDER BY us.reputation DESC) AS rank
        FROM user_stats us
        LEFT JOIN badge_stats bs ON bs.userid = us.id
    )

SELECT
    ru.rank,
    ru.id,
    ru.displayname,
    ru.reputation,
    ru.answer_count,
    ru.question_count,
    ROUND(ru.avg_answer_score::numeric, 2)      AS avg_answer_score,
    ru.upvotes_received,
    ru.downvotes_received,
    ru.total_badges,
    ru.gold,
    ru.silver,
    ru.bronze,
    ARRAY_AGG(DISTINCT tu.tag_name) FILTER (WHERE tu.tag_edits > 5) AS active_tags,
    COALESCE(pl.linked_count, 0)               AS recent_linked_posts,
    COALESCE(pl.duplicate_count, 0)            AS recent_duplicate_posts,
    pl.last_link_date
FROM ranked_users ru
LEFT JOIN tag_usage tu          ON tu.userid = ru.id
LEFT JOIN recent_links pl      ON pl.postid = ru.id
WHERE ru.rank <= 100
GROUP BY
    ru.rank,
    ru.id,
    ru.displayname,
    ru.reputation,
    ru.answer_count,
    ru.question_count,
    ru.avg_answer_score,
    ru.upvotes_received,
    ru.downvotes_received,
    ru.total_badges,
    ru.gold,
    ru.silver,
    ru.bronze,
    pl.linked_count,
    pl.duplicate_count,
    pl.last_link_date
ORDER BY ru.rank;