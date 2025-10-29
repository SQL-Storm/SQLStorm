-- {"query": "320.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3099}
WITH recent_users AS (
    SELECT
        u.id AS user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        date_trunc('month', u.creationdate) AS cohort_month,
        row_number() OVER (ORDER BY u.creationdate DESC, u.id DESC) AS rn_newest
    FROM users u
),
active_questions AS (
    SELECT
        p.id AS question_id,
        p.owneruserid AS asker_id,
        p.creationdate,
        p.score,
        coalesce(p.viewcount, 0) AS views,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.closeddate,
        p.favoritecount,
        p.commentcount
    FROM posts p
    WHERE p.posttypeid = 1
      AND p.creationdate >= (SELECT min(creationdate) FROM users)
),
answers AS (
    SELECT
        a.id AS answer_id,
        a.parentid AS question_id,
        a.owneruserid AS answerer_id,
        a.creationdate AS answer_date,
        a.score AS answer_score
    FROM posts a
    WHERE a.posttypeid = 2
),
answer_stats AS (
    SELECT
        a.question_id,
        count(*) AS total_answers,
        sum(CASE WHEN a.answer_score > 0 THEN 1 ELSE 0 END) AS positive_answers,
        max(a.answer_score) AS best_answer_score,
        min(a.answer_score) AS worst_answer_score,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY a.answer_score) AS median_answer_score,
        avg(extract(epoch FROM (a.answer_date - q.creationdate)) / 3600.0) AS avg_hours_to_answer
    FROM answers a
    JOIN active_questions q ON q.question_id = a.question_id
    GROUP BY a.question_id
),
accepted_answer_stats AS (
    SELECT
        q.question_id,
        aa.id AS accepted_answer_id,
        aa.owneruserid AS accepted_answerer_id,
        aa.score AS accepted_answer_score,
        extract(epoch FROM (aa.creationdate - q.creationdate)) / 3600.0 AS hours_to_accept
    FROM active_questions q
    LEFT JOIN posts aa ON aa.id = q.acceptedanswerid
),
question_votes AS (
    SELECT
        v.postid AS question_id,
        sum(CASE WHEN v.votetypeid = 2 THEN 1 ELSE 0 END) AS upvotes,
        sum(CASE WHEN v.votetypeid = 3 THEN 1 ELSE 0 END) AS downvotes,
        sum(CASE WHEN v.votetypeid = 5 THEN 1 ELSE 0 END) AS favorites,
        sum(CASE WHEN v.votetypeid IN (8,9) THEN coalesce(v.bountyamount,0) ELSE 0 END) AS bounty_total
    FROM votes v
    GROUP BY v.postid
),
question_comments AS (
    SELECT
        c.postid AS question_id,
        count(*) AS comment_count,
        max(c.score) AS max_comment_score,
        sum(CASE WHEN c.score > 0 THEN 1 ELSE 0 END) AS positive_comments
    FROM comments c
    GROUP BY c.postid
),
question_links AS (
    SELECT
        pl.postid AS question_id,
        sum(CASE WHEN pl.linktypeid = 1 THEN 1 ELSE 0 END) AS links_count,
        sum(CASE WHEN pl.linktypeid = 3 THEN 1 ELSE 0 END) AS dup_count
    FROM postlinks pl
    GROUP BY pl.postid
),
question_closures AS (
    SELECT
        ph.postid AS question_id,
        min(CASE WHEN ph.posthistorytypeid = 10 THEN ph.creationdate END) AS first_closed_at,
        bool_or(ph.posthistorytypeid = 11) AS ever_reopened,
        count(*) FILTER (WHERE ph.posthistorytypeid = 10) AS close_events,
        string_agg(DISTINCT
            CASE
                WHEN ph.posthistorytypeid = 10 THEN
                    coalesce(
                        (SELECT crt.name FROM closereasontypes crt WHERE cast(ph.comment AS integer) = crt.id),
                        'Unknown'
                    )
            END
        , '|') AS close_reasons
    FROM posthistory ph
    WHERE ph.posthistorytypeid IN (10,11)
    GROUP BY ph.postid
),
tag_expansion AS (
    SELECT
        q.question_id,
        unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) AS tag
    FROM active_questions q
    WHERE q.tags IS NOT NULL AND q.tags LIKE '<%>'
),
tag_stats AS (
    SELECT
        te.question_id,
        count(*) AS tag_count,
        sum(CASE WHEN lower(te.tag) similar TO '(?:how-to|best-practices|beginner|advanced)' THEN 1 ELSE 0 END) AS meta_tag_count,
        max(CASE WHEN t.ismoderatoronly THEN 1 ELSE 0 END) AS has_mod_only_tag,
        max(CASE WHEN t.isrequired THEN 1 ELSE 0 END) AS has_required_tag
    FROM tag_expansion te
    LEFT JOIN tags t ON t.tagname = te.tag
    GROUP BY te.question_id
),
user_badge_summary AS (
    SELECT
        b.userid,
        sum(CASE WHEN b.class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        sum(CASE WHEN b.class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        sum(CASE WHEN b.class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
        sum(CASE WHEN b.tagbased THEN 1 ELSE 0 END) AS tag_badges,
        count(*) AS total_badges,
        max(b.date) AS last_badge_date
    FROM badges b
    GROUP BY b.userid
),
question_owner AS (
    SELECT
        q.question_id,
        u.id AS owner_id,
        u.displayname AS owner_name,
        u.reputation AS owner_rep,
        u.creationdate AS owner_since,
        ub.total_badges,
        coalesce(ub.gold_badges,0) AS gold_badges,
        coalesce(ub.silver_badges,0) AS silver_badges,
        coalesce(ub.bronze_badges,0) AS bronze_badges
    FROM active_questions q
    LEFT JOIN users u ON u.id = q.asker_id
    LEFT JOIN user_badge_summary ub ON ub.userid = u.id
),
question_quality AS (
    SELECT
        q.question_id,
        q.title,
        q.score,
        q.views,
        q.favoritecount,
        q.commentcount,
        qs.upvotes,
        qs.downvotes,
        qs.favorites AS vote_favorites,
        qs.bounty_total,
        qc.comment_count AS c_count,
        qc.max_comment_score,
        coalesce(qs.upvotes,0) - coalesce(qs.downvotes,0) AS net_votes,
        coalesce(as1.total_answers,0) AS total_answers,
        coalesce(as1.positive_answers,0) AS positive_answers,
        coalesce(as1.best_answer_score, null) AS best_answer_score,
        coalesce(as1.worst_answer_score, null) AS worst_answer_score,
        as1.median_answer_score,
        as1.avg_hours_to_answer,
        CASE
            WHEN q.closeddate IS NOT NULL THEN 1 ELSE 0
        END AS is_closed,
        q.closeddate,
        q.acceptedanswerid,
        aa.accepted_answer_score,
        aa.hours_to_accept,
        tl.links_count,
        tl.dup_count,
        ts.tag_count,
        ts.meta_tag_count,
        ts.has_mod_only_tag,
        ts.has_required_tag,
        greatest(
            coalesce(q.score,0) * 3
            + (coalesce(qs.upvotes,0) - coalesce(qs.downvotes,0)) * 2
            + coalesce(q.views,0) / nullif(100,0)
            + coalesce(q.favoritecount,0) * 1.5
            + coalesce(as1.total_answers,0) * 0.5
            + coalesce(aa.accepted_answer_score,0) * 2
            - coalesce(tl.dup_count,0) * 5
            - CASE WHEN q.closeddate IS NOT NULL THEN 10 ELSE 0 END
        , -100000) AS quality_score
    FROM active_questions q
    LEFT JOIN question_votes qs ON qs.question_id = q.question_id
    LEFT JOIN question_comments qc ON qc.question_id = q.question_id
    LEFT JOIN answer_stats as1 ON as1.question_id = q.question_id
    LEFT JOIN accepted_answer_stats aa ON aa.question_id = q.question_id
    LEFT JOIN question_links tl ON tl.question_id = q.question_id
    LEFT JOIN tag_stats ts ON ts.question_id = q.question_id
),
ranked_questions AS (
    SELECT
        qq.question_id,
        qq.title,
        qq.score,
        qq.views,
        qq.favoritecount,
        qq.commentcount,
        qq.upvotes,
        qq.downvotes,
        qq.vote_favorites,
        qq.bounty_total,
        qq.c_count,
        qq.max_comment_score,
        qq.net_votes,
        qq.total_answers,
        qq.positive_answers,
        qq.best_answer_score,
        qq.worst_answer_score,
        qq.median_answer_score,
        qq.avg_hours_to_answer,
        qq.is_closed,
        qq.closeddate,
        qq.acceptedanswerid,
        qq.accepted_answer_score,
        qq.hours_to_accept,
        qq.links_count,
        qq.dup_count,
        qq.tag_count,
        qq.meta_tag_count,
        qq.has_mod_only_tag,
        qq.has_required_tag,
        qq.quality_score,
        row_number() OVER (ORDER BY qq.quality_score DESC, coalesce(qq.views,0) DESC, coalesce(qq.score,0) DESC, qq.question_id DESC) AS rn_global,
        rank() OVER (ORDER BY coalesce(qq.dup_count,0) DESC, coalesce(qq.score,0) DESC) AS rn_duplicates,
        dense_rank() OVER (PARTITION BY CASE WHEN qq.is_closed=1 THEN 1 ELSE 0 END ORDER BY qq.quality_score DESC) AS rn_by_closed,
        ntile(10) OVER (ORDER BY qq.quality_score DESC) AS decile_quality
    FROM question_quality qq
),
owner_activity AS (
    SELECT
        qo.question_id,
        qo.owner_id,
        qo.owner_name,
        qo.owner_rep,
        qo.owner_since,
        rb.recent_questions,
        rb.recent_answers,
        rb.recent_comments,
        ub.total_badges,
        ub.gold_badges,
        ub.silver_badges,
        ub.bronze_badges
    FROM question_owner qo
    LEFT JOIN user_badge_summary ub ON ub.userid = qo.owner_id
    LEFT JOIN LATERAL (
        SELECT
            sum(CASE WHEN p.posttypeid = 1 AND p.creationdate >= cast('2024-10-01 12:34:56' AS timestamp) - interval '365 days' THEN 1 ELSE 0 END) AS recent_questions,
            sum(CASE WHEN p.posttypeid = 2 AND p.creationdate >= cast('2024-10-01 12:34:56' AS timestamp) - interval '365 days' THEN 1 ELSE 0 END) AS recent_answers,
            coalesce((
                SELECT count(*) FROM comments c WHERE c.userid = qo.owner_id AND c.creationdate >= cast('2024-10-01 12:34:56' AS timestamp) - interval '365 days'
            ),0) AS recent_comments
        FROM posts p
        WHERE p.owneruserid = qo.owner_id
    ) rb ON true
),
null_edge_cases AS (
    SELECT
        q.question_id,
        CASE WHEN q.tags IS NULL OR trim(q.tags) = '' THEN 1 ELSE 0 END AS missing_tags,
        CASE WHEN q.title IS NULL OR length(trim(q.title)) = 0 THEN 1 ELSE 0 END AS missing_title,
        CASE WHEN q.acceptedanswerid IS NULL THEN 1 ELSE 0 END AS no_accepted_answer,
        CASE WHEN q.closeddate IS NULL THEN 0 ELSE 1 END AS was_closed
    FROM active_questions q
),
popular_views_threshold AS (
    SELECT percentile_cont(0.9) WITHIN GROUP (ORDER BY coalesce(views,0)) AS p90_views
    FROM question_quality
),
unpopular_but_high_views AS (
    SELECT
        question_id
    FROM question_quality, popular_views_threshold
    WHERE coalesce(net_votes,0) <= 0
      AND coalesce(views,0) > popular_views_threshold.p90_views
),
final AS (
    SELECT
        rq.question_id,
        rq.title,
        rq.quality_score,
        rq.decile_quality,
        rq.net_votes,
        rq.views,
        rq.score AS post_score,
        rq.total_answers,
        rq.acceptedanswerid,
        rq.accepted_answer_score,
        rq.hours_to_accept,
        rq.dup_count,
        rq.is_closed,
        rq.closeddate,
        rq.tag_count,
        rq.meta_tag_count,
        rq.has_mod_only_tag,
        rq.has_required_tag,
        oa.owner_id,
        oa.owner_name,
        oa.owner_rep,
        oa.total_badges,
        oa.gold_badges,
        oa.silver_badges,
        oa.bronze_badges,
        oa.recent_questions,
        oa.recent_answers,
        oa.recent_comments,
        ne.missing_tags,
        ne.missing_title,
        ne.no_accepted_answer,
        (SELECT count(*) FROM answers a2 WHERE a2.question_id = rq.question_id AND a2.answer_score <= 0) AS nonpositive_answers,
        (SELECT count(*) FROM comments c2 WHERE c2.postid = rq.question_id AND c2.score < 0) AS negative_comments,
        (SELECT count(distinct pl2.relatedpostid) FROM postlinks pl2 WHERE pl2.postid = rq.question_id AND pl2.linktypeid = 1) AS outgoing_links_unique,
        CASE WHEN rq.question_id IN (SELECT question_id FROM unpopular_but_high_views) THEN 1 ELSE 0 END AS is_unpopular_but_high_views,
        CASE
            WHEN coalesce(rq.views,0) = 0 THEN NULL
            ELSE round( (coalesce(rq.net_votes,0) * 1.0) / nullif(rq.views,0) * 1000, 3)
        END AS votes_per_kview,
        CASE
            WHEN rq.total_answers = 0 THEN NULL
            ELSE round(coalesce(rq.positive_answers,0) * 1.0 / nullif(rq.total_answers,0), 3)
        END AS positive_answer_ratio,
        rq.rn_global,
        rq.rn_duplicates,
        rq.rn_by_closed
    FROM ranked_questions rq
    LEFT JOIN owner_activity oa ON oa.question_id = rq.question_id
    LEFT JOIN null_edge_cases ne ON ne.question_id = rq.question_id
)
SELECT *
FROM final
WHERE (
        quality_score > (
            SELECT avg(quality_score) + stddev_pop(quality_score)
            FROM ranked_questions
        )
        OR (is_unpopular_but_high_views = 1 AND no_accepted_answer = 1)
      )
  AND coalesce(owner_rep,0) >= (
        SELECT percentile_cont(0.25) WITHIN GROUP (ORDER BY reputation)
        FROM users
      )
  AND (
        CASE WHEN missing_tags = 1 THEN 0 ELSE 1 END = 1
      )
  AND (
        (dup_count = 0 AND is_closed = 0)
        OR (dup_count > 0 AND net_votes > 10)
      )
ORDER BY decile_quality ASC, quality_score DESC, views DESC
LIMIT 500;