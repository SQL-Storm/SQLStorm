-- {"query": "3038.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2377} 

WITH
    -- Basic per‑user aggregates
    user_stats AS (
        SELECT
            u.id,
            u.displayname,
            u.reputation,
            COALESCE(u.upvotes,0) - COALESCE(u.downvotes,0)               AS net_votes,
            (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 1) AS gold_badges,
            (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 2) AS silver_badges,
            (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 3) AS bronze_badges,
            (SELECT COUNT(*) FROM posts p WHERE p.owneruserid = u.id AND p.posttypeid = 1) AS q_count,
            (SELECT COUNT(*) FROM posts p WHERE p.owneruserid = u.id AND p.posttypeid = 2) AS a_count,
            (SELECT AVG(v.score)
               FROM votes v
               JOIN posts p ON p.id = v.postid
              WHERE p.owneruserid = u.id AND v.votetypeid = 2)         AS avg_upvote_score
        FROM users u
    ),

    -- Tag‑level statistics (used later for a string aggregation)
    tag_stats AS (
        SELECT
            t.tagname,
            t.count                                   AS tag_use_count,
            COALESCE(SUM(CASE WHEN p.posttypeid = 1 THEN 1 END),0) AS q_with_tag,
            COALESCE(SUM(CASE WHEN p.posttypeid = 2 THEN 1 END),0) AS a_with_tag
        FROM tags t
        LEFT JOIN posts p
               ON p.tags LIKE '%'||t.tagname||'%'
        GROUP BY t.tagname, t.count
    ),

    -- Top‑scoring questions (window rank)
    ranked_questions AS (
        SELECT
            p.id,
            p.title,
            p.score,
            p.viewcount,
            p.creationdate,
            u.displayname                                      AS owner_name,
            ROW_NUMBER() OVER (ORDER BY p.score DESC, p.viewcount DESC) AS rank,
            CASE
                WHEN p.closeddate IS NOT NULL      THEN 'Closed'
                WHEN p.communityowneddate IS NOT NULL THEN 'Community'
                ELSE 'Open'
            END                                                AS status,
            p.tags
        FROM posts p
        LEFT JOIN users u ON u.id = p.owneruserid
        WHERE p.posttypeid = 1
    ),

    -- Votes in the last 30 days per post
    recent_votes AS (
        SELECT
            v.postid,
            COUNT(*) FILTER (WHERE v.votetypeid = 2) AS up_votes_30d,
            COUNT(*) FILTER (WHERE v.votetypeid = 3) AS down_votes_30d
        FROM votes v
        WHERE v.creationdate >= CURRENT_DATE - INTERVAL '30 days'
        GROUP BY v.postid
    )

SELECT
    us.id,
    us.displayname,
    us.reputation,
    us.net_votes,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    us.q_count,
    us.a_count,
    ROUND(COALESCE(us.avg_upvote_score,0),2)                     AS avg_upvote_score,
    rq.id                                                          AS top_q_id,
    rq.title                                                       AS top_q_title,
    rq.score                                                       AS top_q_score,
    rq.viewcount                                                   AS top_q_views,
    rq.status                                                      AS top_q_status,
    rv.up_votes_30d,
    rv.down_votes_30d,
    STRING_AGG(DISTINCT tg.tagname, ', ') FILTER (WHERE tg.tagname IS NOT NULL) AS top_q_tags,
    CASE
        WHEN us.reputation > 20000 THEN 'Legendary'
        WHEN us.reputation > 10000 THEN 'Expert'
        WHEN us.reputation > 5000  THEN 'Intermediate'
        ELSE 'Novice'
    END                                                            AS reputation_band
FROM user_stats us
LEFT JOIN LATERAL (
    SELECT *
    FROM ranked_questions rq
    WHERE rq.owner_name = us.displayname
    ORDER BY rq.rank
    LIMIT 1
) rq ON TRUE
LEFT JOIN recent_votes rv ON rv.postid = rq.id
LEFT JOIN LATERAL (
    SELECT regexp_split_to_table(rq.tags, '[><]') AS tagname
) tg ON TRUE
GROUP BY
    us.id, us.displayname, us.reputation, us.net_votes,
    us.gold_badges, us.silver_badges, us.bronze_badges,
    us.q_count, us.a_count, us.avg_upvote_score,
    rq.id, rq.title, rq.score, rq.viewcount, rq.status,
    rv.up_votes_30d, rv.down_votes_30d
HAVING COUNT(*) FILTER (WHERE rq.id IS NOT NULL) > 0
ORDER BY us.reputation DESC, us.net_votes DESC
LIMIT 100

UNION ALL

SELECT
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
FROM (SELECT 1) AS dummy
WHERE NOT EXISTS (SELECT 1 FROM users WHERE reputation > 0);
