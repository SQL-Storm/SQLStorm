-- {"query": "25042.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2372} 

WITH
    -- 1️⃣ User statistics with window functions and correlated sub‑queries
    user_stats AS (
        SELECT
            u.id                              AS user_id,
            u.displayname                     AS user_name,
            u.reputation,
            COALESCE(u.upvotes, 0) - COALESCE(u.downvotes, 0) AS net_votes,
            ROW_NUMBER() OVER (ORDER BY u.reputation DESC, net_votes DESC) AS reputation_rank,
            (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 1) AS gold_badges,
            (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 2) AS silver_badges,
            (SELECT COUNT(*) FROM badges b WHERE b.userid = u.id AND b.class = 3) AS bronze_badges,
            (SELECT STRING_AGG(DISTINCT b.name, ', ') 
               FROM badges b 
               WHERE b.userid = u.id AND b.class = 1)           AS gold_badge_names
        FROM users u
        WHERE u.reputation IS NOT NULL
    ),

    -- 2️⃣ Tag aggregates: explode tags, compute averages, rank with a window function
    tag_agg AS (
        SELECT
            t.tagname,
            t.count                                 AS tag_usage,
            COALESCE(agg.avg_answer_cnt, 0)         AS avg_answers_per_q,
            ROW_NUMBER() OVER (ORDER BY t.count DESC) AS tag_rank
        FROM tags t
        LEFT JOIN (
            SELECT
                UNNEST(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) AS tag,
                AVG(p.answercount)::numeric                               AS avg_answer_cnt
            FROM posts p
            WHERE p.posttypeid = 1               -- only questions
            GROUP BY 1
        ) agg ON agg.tag = t.tagname
    ),

    -- 3️⃣ Question details with lateral join, correlated vote counts and NULL logic
    question_detail AS (
        SELECT
            q.id                                   AS question_id,
            q.title,
            q.creationdate,
            q.score,
            q.viewcount,
            q.favoritecount,
            q.answercount,
            q.commentcount,
            CASE WHEN q.closeddate IS NULL THEN 0 ELSE 1 END        AS is_closed,
            CASE WHEN q.acceptedanswerid IS NOT NULL THEN 1 ELSE 0 END AS has_accepted,
            ROW_NUMBER() OVER (PARTITION BY q.owneruserid ORDER BY q.score DESC) AS user_q_rank,
            (SELECT COUNT(*) FROM votes v WHERE v.postid = q.id AND v.votetypeid = 2) AS up_votes,
            (SELECT COUNT(*) FROM votes v WHERE v.postid = q.id AND v.votetypeid = 3) AS down_votes,
            COALESCE(plc.linkcount, 0)                                         AS duplicate_link_count
        FROM posts q
        LEFT JOIN LATERAL (
            SELECT COUNT(*) AS linkcount
            FROM postlinks pl
            WHERE pl.postid = q.id
              AND pl.linktypeid = 3                 -- Duplicate links
        ) plc ON TRUE
        WHERE q.posttypeid = 1                       -- questions only
    ),

    -- 4️⃣ Combine top users and top tags using a set operator
    top_entities AS (
        SELECT
            'User'   AS entity_type,
            us.user_id,
            us.user_name,
            us.reputation,
            us.net_votes,
            us.gold_badges,
            us.silver_badges,
            us.bronze_badges,
            us.reputation_rank          AS rank,
            NULL::int                   AS tag_rank,
            NULL::text                  AS tag_name,
            NULL::int                   AS question_id,
            NULL::text                  AS question_title
        FROM user_stats us
        WHERE us.reputation_rank <= 100

        UNION ALL

        SELECT
            'Tag'    AS entity_type,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            ta.tag_rank,
            ta.tagname,
            NULL,
            NULL
        FROM tag_agg ta
        WHERE ta.tag_rank <= 100
    ),

    -- 5️⃣ Final projection joining questions to their owners for a richer benchmark set
    final_set AS (
        SELECT
            te.entity_type,
            te.user_id,
            te.user_name,
            te.reputation,
            te.net_votes,
            te.gold_badges,
            te.silver_badges,
            te.bronze_badges,
            te.rank,
            te.tag_rank,
            te.tag_name,
            qd.question_id,
            qd.title                AS question_title,
            qd.score,
            qd.viewcount,
            qd.favoritecount,
            qd.answercount,
            qd.up_votes,
            qd.down_votes,
            qd.is_closed,
            qd.has_accepted,
            qd.duplicate_link_count
        FROM top_entities te
        LEFT JOIN question_detail qd
               ON te.user_id = qd.question_id % 1000   -- artificial join to increase complexity
    )
SELECT *
FROM final_set
ORDER BY
    entity_type,
    CASE WHEN entity_type = 'User' THEN rank END,
    CASE WHEN entity_type = 'Tag'  THEN tag_rank END
LIMIT 200;
