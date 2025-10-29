-- {"query": "3329.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2298} 

WITH
    /* Basic user activity aggregation */
    user_stats AS (
        SELECT
            u.id                                         AS user_id,
            u.displayname                                 AS display_name,
            u.reputation,
            COALESCE(SUM(CASE WHEN v.votetypeid = 2 THEN 1 END),0) AS up_votes_given,
            COALESCE(SUM(CASE WHEN v.votetypeid = 3 THEN 1 END),0) AS down_votes_given,
            COUNT(b.id) FILTER (WHERE b.class = 1)       AS gold_badges,
            COUNT(b.id) FILTER (WHERE b.class = 2)       AS silver_badges,
            COUNT(b.id) FILTER (WHERE b.class = 3)       AS bronze_badges,
            MAX(v.creationdate)                          AS last_vote_date
        FROM users u
        LEFT JOIN votes v   ON v.userid = u.id
        LEFT JOIN badges b  ON b.userid = u.id
        GROUP BY u.id, u.displayname, u.reputation
    ),

    /* Answer‑centric metrics per user */
    answer_metrics AS (
        SELECT
            p.owneruserid                                     AS user_id,
            COUNT(*)                                          AS answer_count,
            AVG(p.score)                                      AS avg_answer_score,
            MAX(p.creationdate)                               AS last_answer_date,
            SUM(CASE WHEN p.id = p.acceptedanswerid THEN 1 END) AS accepted_answers,
            STRING_AGG(DISTINCT t.tagname, ',') FILTER (WHERE t.tagname IS NOT NULL) AS top_tags
        FROM posts p
        /* explode the <tag><list> string */
        LEFT JOIN LATERAL (
            SELECT unnest(string_to_array(
                       regexp_replace(p.tags, '^<|>$', '', 'g'), '><')) AS tag
        ) pt ON TRUE
        LEFT JOIN tags t ON t.tagname = pt.tag
        WHERE p.posttypeid = 2                -- answers only
          AND p.score >= 0
        GROUP BY p.owneruserid
    ),

    /* Most recent closed question per user (if any) */
    recent_closed AS (
        SELECT
            q.owneruserid                     AS user_id,
            q.id,
            q.title,
            q.creationdate,
            COALESCE(NULLIF(ph.comment, ''), 'NoReason') AS close_reason,
            jsonb_extract_path_text(ph.text::jsonb, 'users') AS close_voters
        FROM posts q
        JOIN posthistory ph
          ON ph.postid = q.id
         AND ph.posthistorytypeid = 10          -- Post Closed
        WHERE q.posttypeid = 1
          AND q.closeddate IS NOT NULL
          AND q.creationdate > CURRENT_DATE - INTERVAL '180 days'
    ),

    /* Tag popularity ranking */
    tag_popularity AS (
        SELECT
            tagname,
            count,
            ROW_NUMBER() OVER (ORDER BY count DESC) AS rank
        FROM tags
        WHERE ismoderatoronly = 0
    ),

    /* Combine everything */
    combined AS (
        SELECT
            us.user_id,
            us.display_name,
            us.reputation,
            us.gold_badges,
            us.silver_badges,
            us.bronze_badges,
            am.answer_count,
            am.avg_answer_score,
            am.last_answer_date,
            am.accepted_answers,
            am.top_tags,
            rc.title            AS recent_closed_title,
            rc.close_reason,
            tp.tagname          AS most_popular_tag,
            tp.rank
        FROM user_stats us
        LEFT JOIN answer_metrics am ON am.user_id = us.user_id

        /* pull the most recent closed question for the user */
        LEFT JOIN LATERAL (
            SELECT rc2.title, rc2.close_reason
            FROM recent_closed rc2
            WHERE rc2.id = (
                SELECT q2.id
                FROM posts q2
                WHERE q2.owneruserid = us.user_id
                  AND q2.posttypeid = 1
                  AND q2.closeddate IS NOT NULL
                ORDER BY q2.closeddate DESC
                LIMIT 1
            )
        ) rc ON TRUE

        /* pick the highest‑ranked tag from the user's top_tags list */
        LEFT JOIN LATERAL (
            SELECT tp2.tagname, tp2.rank
            FROM tag_popularity tp2
            WHERE tp2.tagname = ANY (string_to_array(am.top_tags, ','))
            ORDER BY tp2.rank
            LIMIT 1
        ) tp ON TRUE

        WHERE us.reputation > 10000
          AND (am.answer_count IS NULL OR am.answer_count > 0)
    )

SELECT
    user_id,
    display_name,
    reputation,
    gold_badges,
    silver_badges,
    bronze_badges,
    answer_count,
    avg_answer_score,
    last_answer_date,
    accepted_answers,
    top_tags,
    recent_closed_title,
    close_reason,
    most_popular_tag,
    rank
FROM combined
ORDER BY
    reputation DESC,
    gold_badges DESC,
    avg_answer_score DESC
LIMIT 100

UNION ALL

/* dummy rows to stress set‑operator handling */
SELECT
    NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL
FROM generate_series(1,5);
