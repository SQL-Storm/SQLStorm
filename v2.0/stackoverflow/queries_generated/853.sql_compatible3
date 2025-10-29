WITH recent_users AS (
    SELECT
        u.id AS user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        COALESCE(NULLIF(TRIM(SPLIT_PART(COALESCE(u.location, ''), ',', 1)), ''), 'Unknown') AS region_hint,
        ROW_NUMBER() OVER (ORDER BY u.creationdate DESC, u.id) AS rn
    FROM users u
    WHERE u.creationdate >= (SELECT DATE_TRUNC('month', MAX(creationdate)) - INTERVAL '12 months' FROM users)
),
active_posts AS (
    SELECT
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.parentid,
        p.lastactivitydate,
        p.commentcount,
        CASE WHEN p.closeddate IS NOT NULL THEN 1 ELSE 0 END AS is_closed
    FROM posts p
    WHERE p.creationdate >= (SELECT DATE_TRUNC('month', MAX(creationdate)) - INTERVAL '24 months' FROM posts)
),
post_stats AS (
    SELECT
        ap.id AS post_id,
        ap.posttypeid,
        ap.owneruserid,
        ap.creationdate,
        ap.score,
        ap.viewcount,
        ap.title,
        ap.tags,
        ap.acceptedanswerid,
        ap.parentid,
        ap.lastactivitydate,
        ap.commentcount,
        ap.is_closed,
        SUM(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END) AS upvotes,
        SUM(CASE WHEN v.votetypeid = 3 THEN 1 ELSE 0 END) AS downvotes,
        SUM(CASE WHEN v.votetypeid = 5 THEN 1 ELSE 0 END) AS favorites,
        SUM(CASE WHEN v.votetypeid IN (8,9) THEN COALESCE(v.bountyamount,0) ELSE 0 END) AS bounty_total,
        COUNT(DISTINCT c.id) AS distinct_comment_count,
        COUNT(DISTINCT CASE WHEN c.score > 0 THEN c.id END) AS positive_comment_count,
        COUNT(DISTINCT CASE WHEN c.userid IS NULL THEN c.id END) AS anon_comment_count
    FROM active_posts ap
    LEFT JOIN votes v ON v.postid = ap.id
    LEFT JOIN comments c ON c.postid = ap.id
    GROUP BY ap.id, ap.posttypeid, ap.owneruserid, ap.creationdate, ap.score, ap.viewcount, ap.title, ap.tags, ap.acceptedanswerid, ap.parentid, ap.lastactivitydate, ap.commentcount, ap.is_closed
),
question_answer_links AS (
    SELECT
        q.id AS question_id,
        a.id AS answer_id,
        a.owneruserid AS answerer_id
    FROM posts q
    JOIN posts a ON a.parentid = q.id AND a.posttypeid = 2
    WHERE q.posttypeid = 1
),
user_activity AS (
    SELECT
        u.id AS user_id,
        COUNT(DISTINCT CASE WHEN p.posttypeid = 1 THEN p.id END) AS questions_asked,
        COUNT(DISTINCT CASE WHEN p.posttypeid = 2 THEN p.id END) AS answers_posted,
        SUM(COALESCE(ps.upvotes,0)) AS total_upvotes_received,
        SUM(COALESCE(ps.downvotes,0)) AS total_downvotes_received,
        SUM(COALESCE(ps.favorites,0)) AS total_favorites_received,
        SUM(COALESCE(ps.bounty_total,0)) AS bounty_earned,
        SUM(CASE WHEN ps.is_closed = 1 THEN 1 ELSE 0 END) AS closed_posts,
        MAX(ps.lastactivitydate) AS last_post_activity
    FROM users u
    LEFT JOIN post_stats ps ON ps.owneruserid = u.id
    LEFT JOIN posts p ON p.id = ps.post_id
    GROUP BY u.id
),
tag_tokens AS (
    SELECT
        ps.post_id,
        -- Use standard array split: split_part is used above; here emulate tokenization for tags like '<tag1><tag2>'
        -- For portability, use regexp_split_to_table if available; fallback to splitting by '><' removing leading/trailing angle brackets
        TRIM(BOTH '<>' FROM token) AS tag
    FROM post_stats ps,
    LATERAL (
        SELECT regexp_split_to_table(SUBSTRING(COALESCE(ps.tags, '') FROM 2 FOR GREATEST(LENGTH(COALESCE(ps.tags, ''))-2,0)), '><') AS token
    ) t
    WHERE ps.tags IS NOT NULL AND ps.posttypeid = 1
),
top_tags AS (
    SELECT
        tt.tag,
        COUNT(*) AS tag_usage,
        SUM(ps.viewcount) AS tag_views,
        SUM(ps.upvotes) AS tag_upvotes
    FROM tag_tokens tt
    JOIN post_stats ps ON ps.post_id = tt.post_id
    GROUP BY tt.tag
),
duplicate_network AS (
    SELECT
        pl.relatedpostid AS canonical_id,
        pl.postid AS duplicate_id,
        pl.creationdate
    FROM postlinks pl
    WHERE pl.linktypeid = 3
),
dup_clusters AS (
    SELECT
        dn.canonical_id,
        COUNT(DISTINCT dn.duplicate_id) AS dup_count,
        MIN(dn.creationdate) AS first_dup_date,
        MAX(dn.creationdate) AS last_dup_date
    FROM duplicate_network dn
    GROUP BY dn.canonical_id
),
edit_events AS (
    SELECT
        ph.postid,
        SUM(CASE WHEN ph.posthistorytypeid IN (4,5,6) THEN 1 ELSE 0 END) AS edits,
        SUM(CASE WHEN ph.posthistorytypeid IN (24) THEN 1 ELSE 0 END) AS suggested_edits_applied,
        SUM(CASE WHEN ph.posthistorytypeid IN (10) THEN 1 ELSE 0 END) AS closes,
        SUM(CASE WHEN ph.posthistorytypeid IN (11) THEN 1 ELSE 0 END) AS reopens
    FROM posthistory ph
    WHERE ph.creationdate >= (SELECT DATE_TRUNC('month', MAX(creationdate)) - INTERVAL '24 months' FROM posthistory)
    GROUP BY ph.postid
),
rolling_activity AS (
    SELECT
        ps.post_id,
        ps.owneruserid,
        CAST(ps.creationdate AS date) AS day,
        ps.viewcount,
        ps.upvotes,
        ps.downvotes,
        SUM(COALESCE(ps.viewcount,0)) OVER (PARTITION BY ps.owneruserid ORDER BY ps.creationdate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_views_by_user,
        SUM(COALESCE(ps.upvotes,0) - COALESCE(ps.downvotes,0)) OVER (PARTITION BY ps.posttypeid ORDER BY ps.creationdate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS net_votes_rolling_window
    FROM post_stats ps
),
user_badges AS (
    SELECT
        b.userid,
        SUM(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold,
        SUM(CASE WHEN b.class = 2 THEN 1 ELSE 0 END) AS silver,
        SUM(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) AS bronze,
        SUM(CASE WHEN b.tagbased = TRUE THEN 1 ELSE 0 END) AS tag_badges,
        MIN(b.date) AS first_badge_date
    FROM badges b
    GROUP BY b.userid
),
acceptance AS (
    SELECT
        q.owneruserid AS asker_id,
        COUNT(*) AS questions_total,
        COUNT(*) FILTER (WHERE q.acceptedanswerid IS NOT NULL) AS questions_accepted,
        100.0 * COUNT(*) FILTER (WHERE q.acceptedanswerid IS NOT NULL) / NULLIF(COUNT(*),0) AS accept_rate_percent
    FROM posts q
    WHERE q.posttypeid = 1
    GROUP BY q.owneruserid
),
answers_on_top_tags AS (
    SELECT
        qal.answerer_id,
        COUNT(*) AS answers_on_top_10_tags
    FROM question_answer_links qal
    JOIN tag_tokens tt ON tt.post_id = qal.question_id
    WHERE tt.tag IN (
        SELECT tag FROM (
            SELECT tag, tag_usage, DENSE_RANK() OVER (ORDER BY tag_usage DESC, tag) AS rnk
            FROM top_tags
        ) t
        WHERE rnk <= 10
    )
    GROUP BY qal.answerer_id
),
user_classification AS (
    SELECT
        u.id AS user_id,
        CASE
            WHEN COALESCE(ua.answers_posted,0) >= 100 AND COALESCE(ub.gold,0) >= 1 THEN 'Expert'
            WHEN COALESCE(ua.answers_posted,0) >= 50 THEN 'Contributor'
            WHEN COALESCE(ua.questions_asked,0) >= 20 THEN 'Inquisitive'
            ELSE 'Newbie'
        END AS user_level
    FROM users u
    LEFT JOIN user_activity ua ON ua.user_id = u.id
    LEFT JOIN user_badges ub ON ub.userid = u.id
),
normalized_scores AS (
    SELECT
        ps.post_id,
        ps.posttypeid,
        ps.score,
        AVG(ps.score) OVER (PARTITION BY ps.posttypeid) AS avg_score_by_type,
        STDDEV_POP(ps.score) OVER (PARTITION BY ps.posttypeid) AS sd_score_by_type,
        CASE
            WHEN STDDEV_POP(ps.score) OVER (PARTITION BY ps.posttypeid) > 0
            THEN (ps.score - AVG(ps.score) OVER (PARTITION BY ps.posttypeid)) / NULLIF(STDDEV_POP(ps.score) OVER (PARTITION BY ps.posttypeid),0)
            ELSE 0
        END AS z_score_by_type
    FROM post_stats ps
),
final AS (
    SELECT
        u.id AS user_id,
        u.displayname,
        u.reputation,
        ru.region_hint,
        uc.user_level,
        ua.questions_asked,
        ua.answers_posted,
        COALESCE(aott.answers_on_top_10_tags,0) AS answers_on_top_10_tags,
        COALESCE(ac.accept_rate_percent, 0) AS accept_rate_percent,
        COALESCE(ub.gold,0) AS gold_badges,
        COALESCE(ub.silver,0) AS silver_badges,
        COALESCE(ub.bronze,0) AS bronze_badges,
        COALESCE(ub.tag_badges,0) AS tag_badges,
        ua.total_upvotes_received,
        ua.total_downvotes_received,
        ua.total_favorites_received,
        ua.bounty_earned,
        ua.closed_posts,
        ua.last_post_activity,
        SUM(CASE WHEN ps.posttypeid = 1 THEN 1 ELSE 0 END) AS questions_in_window,
        SUM(CASE WHEN ps.posttypeid = 2 THEN 1 ELSE 0 END) AS answers_in_window,
        SUM(COALESCE(ps.viewcount,0)) AS views_in_window,
        AVG(COALESCE(ps.score,0)) AS avg_score_in_window,
        MAX(COALESCE(nz.z_score_by_type,0)) AS max_post_zscore_bytype,
        COUNT(DISTINCT CASE WHEN dc.dup_count IS NOT NULL THEN ps.post_id END) AS posts_with_duplicates,
        SUM(COALESCE(ee.edits,0)) AS edits_count,
        SUM(COALESCE(ee.suggested_edits_applied,0)) AS suggested_edits_applied,
        SUM(COALESCE(ee.closes,0)) AS closes_count,
        SUM(COALESCE(ee.reopens,0)) AS reopens_count,
        MAX(COALESCE(ra.cum_views_by_user,0)) AS cum_views_by_user,
        MAX(COALESCE(ra.net_votes_rolling_window,0)) AS last_net_votes_rolling_window,
        SUM(CASE WHEN ps.tags IS NOT NULL AND (
                LOWER(ps.tags) LIKE '%<performance>%' OR
                LOWER(ps.tags) LIKE '%<benchmark>%' OR
                LOWER(ps.tags) LIKE '%<sql>%' OR
                LOWER(ps.tags) LIKE '%<postgresql>%' OR
                LOWER(ps.tags) LIKE '%<optimization>%'
            ) THEN 1 ELSE 0 END) AS perf_related_posts
    FROM users u
    LEFT JOIN recent_users ru ON ru.user_id = u.id AND ru.rn <= 1000000
    LEFT JOIN user_activity ua ON ua.user_id = u.id
    LEFT JOIN user_badges ub ON ub.userid = u.id
    LEFT JOIN acceptance ac ON ac.asker_id = u.id
    LEFT JOIN answers_on_top_tags aott ON aott.answerer_id = u.id
    LEFT JOIN user_classification uc ON uc.user_id = u.id
    LEFT JOIN post_stats ps ON ps.owneruserid = u.id
    LEFT JOIN normalized_scores nz ON nz.post_id = ps.post_id
    LEFT JOIN dup_clusters dc ON dc.canonical_id = ps.post_id
    LEFT JOIN edit_events ee ON ee.postid = ps.post_id
    LEFT JOIN rolling_activity ra ON ra.post_id = ps.post_id
    WHERE COALESCE(u.displayname,'') <> ''
      AND (u.reputation > 0 OR ua.answers_posted IS NOT NULL OR ua.questions_asked IS NOT NULL)
      AND (
          EXISTS (
              SELECT 1
              FROM posts p2
              WHERE p2.owneruserid = u.id
                AND p2.creationdate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '36 months'
          )
          OR u.creationdate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '12 years'
      )
    GROUP BY
        u.id, u.displayname, u.reputation, ru.region_hint, uc.user_level,
        ua.questions_asked, ua.answers_posted, aott.answers_on_top_10_tags,
        ac.accept_rate_percent, ub.gold, ub.silver, ub.bronze, ub.tag_badges,
        ua.total_upvotes_received, ua.total_downvotes_received, ua.total_favorites_received,
        ua.bounty_earned, ua.closed_posts, ua.last_post_activity
)
SELECT
    f.*,
    ROW_NUMBER() OVER (ORDER BY f.reputation DESC, f.views_in_window DESC, f.avg_score_in_window DESC, f.user_id) AS rank_overall,
    DENSE_RANK() OVER (PARTITION BY f.user_level ORDER BY f.reputation DESC) AS rank_within_level,
    CASE
        WHEN f.accept_rate_percent >= 80 AND f.answers_on_top_10_tags >= 25 THEN 'High Impact'
        WHEN f.accept_rate_percent >= 50 AND f.answers_on_top_10_tags >= 10 THEN 'Impactful'
        WHEN f.accept_rate_percent IS NULL THEN 'Unknown'
        ELSE 'Regular'
    END AS impact_label
FROM final f
WHERE (f.gold_badges + f.silver_badges + f.bronze_badges) >= 0
  AND (f.total_upvotes_received - f.total_downvotes_received) >= -100
  AND (COALESCE(f.views_in_window,0) + COALESCE(f.bounty_earned,0)) >= 0
ORDER BY
    f.user_level,
    rank_within_level,
    rank_overall
LIMIT 500;