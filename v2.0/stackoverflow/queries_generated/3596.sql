-- {"query": "3596.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2129} 

/*  Complex benchmark query mixing CTEs, window functions, outer joins, 
    correlated sub‑queries, set operators, string handling and NULL logic   */
WITH
/* --------------------------------------------------------------
   1. Basic per‑user aggregates (badges, posts, votes cast)
   -------------------------------------------------------------- */
user_stats AS (
    SELECT
        u.id                                     AS user_id,
        u.displayname,
        COALESCE(u.reputation,0)                 AS reputation,
        (SELECT COUNT(*) FROM badges   b WHERE b.userid   = u.id) AS badge_cnt,
        (SELECT COUNT(*) FROM posts   p WHERE p.owneruserid = u.id) AS post_cnt,
        (SELECT COUNT(*) FROM votes   v WHERE v.userid = u.id AND v.votetypeid = 2) AS upvote_given,
        (SELECT COUNT(*) FROM votes   v WHERE v.userid = u.id AND v.votetypeid = 3) AS downvote_given
    FROM users u
),

/* --------------------------------------------------------------
   2. Top tags by total usage (excluding moderator‑only tags)
   -------------------------------------------------------------- */
top_tags AS (
    SELECT
        t.tagname,
        t.count,
        ROW_NUMBER() OVER (ORDER BY t.count DESC) AS rn
    FROM tags t
    WHERE t.ismoderatoronly = 0
),

/* --------------------------------------------------------------
   3. Explode question tags into one row per tag
   -------------------------------------------------------------- */
question_tags AS (
    SELECT
        p.id               AS post_id,
        p.owneruserid      AS owner_user_id,
        regexp_split_to_table(p.tags, '[><]+') AS tag
    FROM posts p
    WHERE p.posttypeid = 1                -- only questions
),

/* --------------------------------------------------------------
   4. Per‑user, per‑top‑tag activity (how many of their questions
      carry this tag and the sum of scores)
   -------------------------------------------------------------- */
user_tag_activity AS (
    SELECT
        us.user_id,
        tt.tagname,
        COUNT(*) FILTER (WHERE qt.tag = tt.tagname)           AS tagged_q_cnt,
        SUM(p.score) FILTER (WHERE qt.tag = tt.tagname)       AS tagged_score_sum
    FROM user_stats us
    JOIN question_tags qt   ON qt.owner_user_id = us.user_id
    JOIN top_tags tt       ON tt.tagname = qt.tag
    JOIN posts p           ON p.id = qt.post_id
    GROUP BY us.user_id, tt.tagname
),

/* --------------------------------------------------------------
   5. Best tag for each user (the tag with most questions)
   -------------------------------------------------------------- */
best_user_tag AS (
    SELECT
        uta.user_id,
        uta.tagname,
        uta.tagged_q_cnt,
        uta.tagged_score_sum,
        ROW_NUMBER() OVER (PARTITION BY uta.user_id ORDER BY uta.tagged_q_cnt DESC, uta.tagged_score_sum DESC) AS rn
    FROM user_tag_activity uta
),

/* --------------------------------------------------------------
   6. Recent voting activity on the user’s highest‑scoring post
   -------------------------------------------------------------- */
recent_votes AS (
    SELECT
        v.postid,
        COUNT(*) FILTER (WHERE v.votetypeid = 2) AS recent_upvotes,
        COUNT(*) FILTER (WHERE v.votetypeid = 3) AS recent_downvotes,
        MAX(v.creationdate)                      AS last_vote_ts
    FROM votes v
    WHERE v.creationdate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.postid
),

/* --------------------------------------------------------------
   7. Assemble final result set with enriched columns
   -------------------------------------------------------------- */
final_set AS (
    SELECT
        us.user_id,
        us.displayname,
        us.reputation,
        us.badge_cnt,
        us.post_cnt,
        us.upvote_given,
        us.downvote_given,
        COALESCE(but.tagname, '(no top tag)')                AS top_tag,
        COALESCE(but.tagged_q_cnt,0)                         AS top_tag_q_cnt,
        COALESCE(but.tagged_score_sum,0)                     AS top_tag_score_sum,
        CASE
            WHEN us.reputation >= 20000 THEN 'Elite'
            WHEN us.reputation >= 10000 THEN 'Pro'
            WHEN us.reputation > 0       THEN 'Active'
            ELSE                               'Newbie'
        END                                                  AS reputation_tier,
        CONCAT('U_', us.user_id)                             AS user_key,
        rv.recent_upvotes,
        rv.recent_downvotes,
        rv.last_vote_ts
    FROM user_stats us
    LEFT JOIN best_user_tag but
           ON but.user_id = us.user_id AND but.rn = 1
    LEFT JOIN LATERAL (
        SELECT *
        FROM recent_votes rv
        WHERE rv.postid = (
            SELECT p.id
            FROM posts p
            WHERE p.owneruserid = us.user_id
            ORDER BY p.score DESC NULLS LAST
            LIMIT 1
        )
    ) rv ON TRUE
    WHERE us.post_cnt > 10
      AND us.badge_cnt > 5
      AND us.reputation IS NOT NULL
)

/* --------------------------------------------------------------
   8. Return top 100 users, plus a dummy row if none qualify
   -------------------------------------------------------------- */
SELECT *
FROM final_set
WHERE reputation_tier <> 'Newbie'
ORDER BY reputation DESC NULLS LAST
LIMIT 100

UNION ALL

SELECT
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
WHERE NOT EXISTS (SELECT 1 FROM final_set WHERE reputation_tier <> 'Newbie');
