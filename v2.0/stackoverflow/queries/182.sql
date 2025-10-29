-- {"query": "182.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3322}
WITH recent_users AS (
    SELECT
        u.id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        COALESCE(NULLIF(TRIM(u.websiteurl), ''), 'N/A') AS websiteurl,
        DATE_TRUNC('month', u.creationdate) AS signup_month
    FROM users u
    WHERE u.creationdate >= (SELECT MAX(creationdate) - INTERVAL '365 days' FROM users)
),
user_badge_stats AS (
    SELECT
        b.userid,
        COUNT(*) AS total_badges,
        SUM(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
        MAX(b.date) AS last_badge_date
    FROM badges b
    GROUP BY b.userid
),
user_post_activity AS (
    SELECT
        p.owneruserid AS userid,
        COUNT(*) FILTER (WHERE p.posttypeid = 1) AS question_count,
        COUNT(*) FILTER (WHERE p.posttypeid = 2) AS answer_count,
        SUM(COALESCE(p.score,0)) AS total_post_score,
        SUM(COALESCE(p.viewcount,0)) AS total_views,
        MAX(p.lastactivitydate) AS last_post_activity,
        AVG(NULLIF(p.answercount,0)) FILTER (WHERE p.posttypeid = 1) AS avg_answers_per_question
    FROM posts p
    WHERE p.owneruserid IS NOT NULL
    GROUP BY p.owneruserid
),
user_comment_stats AS (
    SELECT
        c.userid,
        COUNT(*) AS comment_count,
        SUM(COALESCE(c.score,0)) AS comment_score,
        MAX(c.creationdate) AS last_comment_date
    FROM comments c
    WHERE c.userid IS NOT NULL
    GROUP BY c.userid
),
user_vote_stats AS (
    SELECT
        v.userid,
        COUNT(*) FILTER (WHERE v.votetypeid = 2) AS upvotes_cast,
        COUNT(*) FILTER (WHERE v.votetypeid = 3) AS downvotes_cast,
        COUNT(*) FILTER (WHERE v.votetypeid = 5) AS favorites_cast,
        SUM(COALESCE(v.bountyamount,0)) FILTER (WHERE v.votetypeid IN (8,9)) AS bounty_total
    FROM votes v
    WHERE v.userid IS NOT NULL
    GROUP BY v.userid
),
question_closure AS (
    SELECT
        ph.postid,
        MIN(ph.creationdate) FILTER (WHERE ph.posthistorytypeid IN (10,35)) AS first_close_or_migrate_date,
        MAX(ph.creationdate) FILTER (WHERE ph.posthistorytypeid IN (11)) AS last_reopen_date,
        COUNT(*) FILTER (WHERE ph.posthistorytypeid = 10) AS close_events,
        COUNT(*) FILTER (WHERE ph.posthistorytypeid = 11) AS reopen_events,
        COUNT(*) FILTER (WHERE ph.posthistorytypeid IN (35,36)) AS migrate_events
    FROM posthistory ph
    GROUP BY ph.postid
),
tag_exploded AS (
    SELECT
        p.id AS postid,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(p.tags, 2, LENGTH(p.tags)-2), '><')) AS tagname
    FROM posts p
    WHERE p.posttypeid = 1
      AND p.tags IS NOT NULL
      AND LENGTH(p.tags) > 2
),
user_top_tags AS (
    SELECT
        p.owneruserid AS userid,
        t.tagname,
        COUNT(*) AS tag_questions,
        ROW_NUMBER() OVER (PARTITION BY p.owneruserid ORDER BY COUNT(*) DESC, t.tagname) AS rn
    FROM posts p
    JOIN tag_exploded t ON t.postid = p.id
    WHERE p.posttypeid = 1
      AND p.owneruserid IS NOT NULL
    GROUP BY p.owneruserid, t.tagname
),
accepted_answerers AS (
    SELECT
        q.owneruserid AS asker_id,
        a.owneruserid AS answerer_id,
        COUNT(*) AS accepted_answers_given_to_asker
    FROM posts q
    JOIN posts a ON a.id = q.acceptedanswerid
    WHERE q.posttypeid = 1 AND a.posttypeid = 2
    GROUP BY q.owneruserid, a.owneruserid
),
user_peer_accepts AS (
    SELECT
        aa.answerer_id AS userid,
        SUM(aa.accepted_answers_given_to_asker) AS total_accepts_from_peers,
        COUNT(DISTINCT aa.asker_id) AS distinct_askers_helped
    FROM accepted_answerers aa
    GROUP BY aa.answerer_id
),
post_link_graph AS (
    SELECT
        pl.postid,
        COUNT(*) FILTER (WHERE pl.linktypeid = 1) AS linked_out_count,
        COUNT(*) FILTER (WHERE pl.linktypeid = 3) AS duplicate_of_count,
        COUNT(DISTINCT pl.relatedpostid) AS distinct_related
    FROM postlinks pl
    GROUP BY pl.postid
),
question_quality AS (
    SELECT
        q.id,
        q.owneruserid AS userid,
        q.score,
        q.viewcount,
        q.favoritecount,
        q.answercount,
        COALESCE(pg.linked_out_count,0) AS linked_out_count,
        COALESCE(pg.duplicate_of_count,0) AS duplicate_of_count,
        COALESCE(pg.distinct_related,0) AS distinct_related,
        COALESCE(qc.close_events,0) AS close_events,
        COALESCE(qc.reopen_events,0) AS reopen_events,
        CASE
            WHEN q.viewcount IS NULL OR q.viewcount = 0 THEN NULL
            ELSE ROUND((CAST(q.score AS numeric) / NULLIF(CAST(q.viewcount AS numeric),0)) * LN(NULLIF(CAST(q.viewcount AS numeric),0)+1), 6)
        END AS engagement_score
    FROM posts q
    LEFT JOIN post_link_graph pg ON pg.postid = q.id
    LEFT JOIN question_closure qc ON qc.postid = q.id
    WHERE q.posttypeid = 1
),
user_quality_agg AS (
    SELECT
        qq.userid,
        AVG(qq.engagement_score) AS avg_engagement_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qq.engagement_score) AS median_engagement_score,
        STDDEV_POP(qq.engagement_score) AS std_engagement_score,
        SUM(qq.close_events) AS total_closes,
        SUM(qq.reopen_events) AS total_reopens,
        SUM(qq.duplicate_of_count) AS total_marked_duplicate
    FROM question_quality qq
    GROUP BY qq.userid
),
recent_activity AS (
    SELECT
        u.id AS userid,
        GREATEST(
            COALESCE(upa.last_post_activity, TIMESTAMP 'epoch'),
            COALESCE(ucs.last_comment_date, TIMESTAMP 'epoch'),
            COALESCE(ubs.last_badge_date, TIMESTAMP 'epoch')
        ) AS last_any_activity
    FROM users u
    LEFT JOIN user_post_activity upa ON upa.userid = u.id
    LEFT JOIN user_comment_stats ucs ON ucs.userid = u.id
    LEFT JOIN user_badge_stats ubs ON ubs.userid = u.id
),
ranked_users AS (
    SELECT
        ru.id AS userid,
        ru.displayname,
        ru.reputation,
        ru.location,
        ru.websiteurl,
        ru.signup_month,
        COALESCE(ubs.total_badges,0) AS total_badges,
        COALESCE(ubs.gold_badges,0) AS gold_badges,
        COALESCE(ubs.silver_badges,0) AS silver_badges,
        COALESCE(ubs.bronze_badges,0) AS bronze_badges,
        COALESCE(upa.question_count,0) AS question_count,
        COALESCE(upa.answer_count,0) AS answer_count,
        COALESCE(upa.total_post_score,0) AS total_post_score,
        COALESCE(upa.total_views,0) AS total_views,
        upa.last_post_activity,
        upa.avg_answers_per_question,
        COALESCE(ucs.comment_count,0) AS comment_count,
        COALESCE(ucs.comment_score,0) AS comment_score,
        ucs.last_comment_date,
        COALESCE(uvs.upvotes_cast,0) AS upvotes_cast,
        COALESCE(uvs.downvotes_cast,0) AS downvotes_cast,
        COALESCE(uvs.favorites_cast,0) AS favorites_cast,
        COALESCE(uvs.bounty_total,0) AS bounty_total,
        COALESCE(uqa.avg_engagement_score,0) AS avg_engagement_score,
        uqa.median_engagement_score,
        COALESCE(uqa.std_engagement_score,0) AS std_engagement_score,
        COALESCE(uqa.total_closes,0) AS total_closes,
        COALESCE(uqa.total_reopens,0) AS total_reopens,
        COALESCE(uqa.total_marked_duplicate,0) AS total_marked_duplicate,
        COALESCE(upr.total_accepts_from_peers,0) AS total_accepts_from_peers,
        COALESCE(upr.distinct_askers_helped,0) AS distinct_askers_helped,
        ra.last_any_activity,
        ROW_NUMBER() OVER (
            PARTITION BY DATE_TRUNC('quarter', ru.creationdate)
            ORDER BY
                COALESCE(upa.answer_count,0) * 2
              + COALESCE(upa.question_count,0)
              + COALESCE(ubs.gold_badges,0) * 5
              + COALESCE(ubs.silver_badges,0) * 2
              + COALESCE(ubs.bronze_badges,0) * 1
              + COALESCE(uvs.upvotes_cast,0) * 0.2
              - COALESCE(uvs.downvotes_cast,0) * 0.5
              + COALESCE(uqa.avg_engagement_score,0) * 10
              + COALESCE(upr.total_accepts_from_peers,0) * 3 DESC,
              ru.id
        ) AS quarter_rank
    FROM recent_users ru
    LEFT JOIN user_badge_stats ubs ON ubs.userid = ru.id
    LEFT JOIN user_post_activity upa ON upa.userid = ru.id
    LEFT JOIN user_comment_stats ucs ON ucs.userid = ru.id
    LEFT JOIN user_vote_stats uvs ON uvs.userid = ru.id
    LEFT JOIN user_quality_agg uqa ON uqa.userid = ru.id
    LEFT JOIN user_peer_accepts upr ON upr.userid = ru.id
    LEFT JOIN recent_activity ra ON ra.userid = ru.id
),
top_tag_pivot AS (
    SELECT
        utt.userid,
        MAX(CASE WHEN utt.rn = 1 THEN utt.tagname END) AS top_tag_1,
        MAX(CASE WHEN utt.rn = 2 THEN utt.tagname END) AS top_tag_2,
        MAX(CASE WHEN utt.rn = 3 THEN utt.tagname END) AS top_tag_3
    FROM user_top_tags utt
    WHERE utt.rn <= 3
    GROUP BY utt.userid
),
activity_buckets AS (
    SELECT
        r.userid,
        CASE
            WHEN ra.last_any_activity IS NULL THEN 'never'
            WHEN ra.last_any_activity >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days') THEN 'last_30_days'
            WHEN ra.last_any_activity >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days') THEN 'last_90_days'
            WHEN ra.last_any_activity >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days') THEN 'last_180_days'
            ELSE 'stale'
        END AS activity_bucket
    FROM ranked_users r
    LEFT JOIN recent_activity ra ON ra.userid = r.userid
),
score_norm AS (
    SELECT
        r.userid,
        r.displayname,
        r.reputation,
        r.location,
        r.websiteurl,
        r.signup_month,
        r.total_badges,
        r.gold_badges,
        r.silver_badges,
        r.bronze_badges,
        r.question_count,
        r.answer_count,
        r.total_post_score,
        r.total_views,
        r.last_post_activity,
        r.avg_answers_per_question,
        r.comment_count,
        r.comment_score,
        r.last_comment_date,
        r.upvotes_cast,
        r.downvotes_cast,
        r.favorites_cast,
        r.bounty_total,
        r.avg_engagement_score,
        r.median_engagement_score,
        r.std_engagement_score,
        r.total_closes,
        r.total_reopens,
        r.total_marked_duplicate,
        r.total_accepts_from_peers,
        r.distinct_askers_helped,
        r.last_any_activity,
        r.quarter_rank,
        NTILE(100) OVER (ORDER BY COALESCE(r.total_post_score,0)) AS score_percentile,
        -- Replace ordered-set aggregate with scalar percentile via subquery to avoid OVER on ordered-set aggregates
        (SELECT PERCENTILE_DISC(0.9) WITHIN GROUP (ORDER BY COALESCE(r2.total_post_score,0))
         FROM ranked_users r2
        ) AS p90_score
    FROM ranked_users r
)
SELECT
    r.userid,
    r.displayname,
    r.reputation,
    r.location,
    r.websiteurl,
    r.signup_month,
    COALESCE(tp.top_tag_1,'') AS top_tag_1,
    COALESCE(tp.top_tag_2,'') AS top_tag_2,
    COALESCE(tp.top_tag_3,'') AS top_tag_3,
    r.question_count,
    r.answer_count,
    r.total_post_score,
    r.total_views,
    r.avg_engagement_score,
    r.median_engagement_score,
    r.std_engagement_score,
    r.total_closes,
    r.total_reopens,
    r.total_marked_duplicate,
    r.total_badges,
    r.gold_badges,
    r.silver_badges,
    r.bronze_badges,
    r.comment_count,
    r.comment_score,
    r.upvotes_cast,
    r.downvotes_cast,
    r.favorites_cast,
    r.bounty_total,
    r.total_accepts_from_peers,
    r.distinct_askers_helped,
    r.last_post_activity,
    r.last_comment_date,
    r.last_any_activity,
    ab.activity_bucket,
    sn.score_percentile,
    CASE
        WHEN r.total_post_score IS NULL THEN 'unknown'
        WHEN r.total_post_score >= sn.p90_score THEN 'elite'
        WHEN r.total_post_score >= sn.p90_score * 0.5 THEN 'strong'
        WHEN r.total_post_score >= 0 THEN 'average'
        ELSE 'controversial'
    END AS performance_band,
    r.quarter_rank,
    CASE
        WHEN COALESCE(r.answer_count,0) = 0 THEN NULL
        ELSE ROUND((CAST(COALESCE(r.total_accepts_from_peers,0) AS numeric) / NULLIF(CAST(r.answer_count AS numeric),0)) * 100, 2)
    END AS accept_help_rate_pct,
    CASE
        WHEN r.websiteurl ILIKE '%github.com%' THEN 'github'
        WHEN r.websiteurl ILIKE '%gitlab.com%' THEN 'gitlab'
        WHEN r.websiteurl ILIKE '%bitbucket.org%' THEN 'bitbucket'
        WHEN r.websiteurl IS NULL OR r.websiteurl = 'N/A' THEN 'none'
        ELSE 'other'
    END AS site_affinity,
    COALESCE(NULLIF(TRIM(SPLIT_PART(COALESCE(r.location,''), ',', 1)), ''), 'Unknown') AS location_primary
FROM score_norm sn
JOIN ranked_users r ON r.userid = sn.userid
LEFT JOIN top_tag_pivot tp ON tp.userid = r.userid
LEFT JOIN activity_buckets ab ON ab.userid = r.userid
WHERE
    (
        r.reputation >= (
            SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY reputation)
            FROM users
            WHERE creationdate >= (SELECT MAX(creationdate) - INTERVAL '365 days' FROM users)
        )
        OR r.gold_badges >= 1
        OR (r.answer_count + r.question_count) >= 10
    )
    AND NOT EXISTS (
        SELECT 1
        FROM posts p
        WHERE p.owneruserid = r.userid
          AND p.posttypeid = 1
          AND p.closeddate IS NOT NULL
          AND p.creationdate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7 days')
    )
    AND (
        r.avg_engagement_score IS NULL
        OR r.avg_engagement_score >= (
            SELECT AVG(avg_engagement_score)
            FROM user_quality_agg
        )
    )
ORDER BY
    r.quarter_rank NULLS LAST,
    r.reputation DESC,
    r.total_post_score DESC,
    r.userid
LIMIT 500;