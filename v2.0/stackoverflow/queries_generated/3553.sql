-- {"query": "3553.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2537} 

/*  Benchmark‑Heavy Query – combines CTEs, window functions, outer joins, 
    correlated subqueries, set operators, complex predicates, string
    manipulation and NULL logic on the StackOverflow schema. */

WITH
/* ------------------------------------------------------------------ *
 * 1️⃣  Base user metrics (reputation, account age, recent activity)   *
 * ------------------------------------------------------------------ */
user_base AS (
    SELECT
        u.Id                               AS user_id,
        u.DisplayName                      AS display_name,
        u.Reputation                       AS reputation,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate)) / 86400
                                           AS account_age_days,
        COALESCE(u.Views,0)                AS total_views,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS net_votes,
        -- recent activity: last post, comment or vote in the last 90 days
        GREATEST(
            COALESCE(
                (SELECT MAX(p.LastActivityDate) FROM Posts p WHERE p.OwnerUserId = u.Id),
                '1970-01-01'::timestamp
            ),
            COALESCE(
                (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.UserId = u.Id),
                '1970-01-01'::timestamp
            ),
            COALESCE(
                (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.UserId = u.Id),
                '1970-01-01'::timestamp
            )
        )                                    AS last_activity_ts
    FROM Users u
),

/* ------------------------------------------------------------------ *
 * 2️⃣  Badge aggregation (gold, silver, bronze, tag‑based)           *
 * ------------------------------------------------------------------ */
user_badges AS (
    SELECT
        b.UserId                           AS user_id,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_cnt,
        SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS tagbased_cnt,
        COUNT(*)                           AS total_badges
    FROM Badges b
    GROUP BY b.UserId
),

/* ------------------------------------------------------------------ *
 * 3️⃣  Post‑level metrics per user (questions, answers, avg score)   *
 * ------------------------------------------------------------------ */
user_posts AS (
    SELECT
        p.OwnerUserId                       AS user_id,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS question_cnt,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS answer_cnt,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS avg_q_score,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS avg_a_score,
        SUM(p.ViewCount)                    AS total_views,
        COUNT(*) FILTER (WHERE p.AcceptedAnswerId IS NOT NULL) AS questions_with_accepted,
        COUNT(*) FILTER (WHERE p.ClosedDate IS NOT NULL) AS closed_questions,
        MAX(p.LastActivityDate)             AS last_post_activity
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),

/* ------------------------------------------------------------------ *
 * 4️⃣  Vote‑derived influence score (upvotes minus downvotes)       *
 * ------------------------------------------------------------------ */
user_votes AS (
    SELECT
        v.UserId                           AS voter_id,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS upvote_cnt,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS downvote_cnt,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                 WHEN v.VoteTypeId = 3 THEN -1
                 ELSE 0 END)                 AS vote_balance
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),

/* ------------------------------------------------------------------ *
 * 5️⃣  Tag usage extraction for questions (first tag only)          *
 * ------------------------------------------------------------------ */
question_tags AS (
    SELECT
        p.Id                                 AS post_id,
        p.OwnerUserId                        AS user_id,
        CASE
            WHEN p.Tags IS NOT NULL
            THEN split_part(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><', 1)
            ELSE NULL
        END                                 AS primary_tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),

/* ------------------------------------------------------------------ *
 * 6️⃣  Tag‑level popularity (questions per tag, answer ratio)       *
 * ------------------------------------------------------------------ */
tag_stats AS (
    SELECT
        qt.primary_tag                       AS tag_name,
        COUNT(*)                             AS question_cnt,
        COALESCE(SUM(a.AnswerCount),0)       AS total_answers,
        CASE WHEN COUNT(*) = 0 THEN 0
             ELSE COALESCE(SUM(a.AnswerCount),0)::decimal / COUNT(*)
        END                                 AS avg_answers_per_q
    FROM question_tags qt
    LEFT JOIN Posts a
        ON a.ParentId = qt.post_id
        AND a.PostTypeId = 2
    GROUP BY qt.primary_tag
),

/* ------------------------------------------------------------------ *
 * 7️⃣  Intersecting set: Users who have both gold badges and >1000   *
 *    reputation, and have posted a question that is still open.     *
 * ------------------------------------------------------------------ */
gold_active_users AS (
    SELECT
        ub.user_id
    FROM user_badges ub
    JOIN user_base ubas ON ub.user_id = ubas.user_id
    WHERE ub.gold_cnt > 0
      AND ubas.reputation > 1000
      AND EXISTS (
          SELECT 1
          FROM Posts p
          WHERE p.OwnerUserId = ub.user_id
            AND p.PostTypeId = 1
            AND p.ClosedDate IS NULL
      )
),

/* ------------------------------------------------------------------ *
 * 8️⃣  Final amalgamation – left outer join to keep all users        *
 * ------------------------------------------------------------------ */
final_user_stats AS (
    SELECT
        ub.user_id,
        ub.display_name,
        ub.reputation,
        ub.account_age_days,
        ub.total_views                                      AS profile_views,
        ub.net_votes,
        ub.last_activity_ts,
        ubad.gold_cnt,
        ubad.silver_cnt,
        ubad.bronze_cnt,
        ubad.tagbased_cnt,
        ubad.total_badges,
        up.question_cnt,
        up.answer_cnt,
        up.avg_q_score,
        up.avg_a_score,
        up.total_views                              AS post_views,
        up.questions_with_accepted,
        up.closed_questions,
        up.last_post_activity,
        uv.upvote_cnt,
        uv.downvote_cnt,
        uv.vote_balance,
        CASE
            WHEN up.question_cnt = 0 THEN 0
            ELSE (up.answer_cnt::decimal / up.question_cnt)
        END                                         AS answer_to_question_ratio,
        CASE
            WHEN ub.reputation >= 20000 THEN 'Legendary'
            WHEN ub.reputation >= 10000 THEN 'Expert'
            WHEN ub.reputation >= 5000  THEN 'Seasoned'
            WHEN ub.reputation >= 2000  THEN 'Intermediate'
            WHEN ub.reputation >= 1000  THEN 'Novice'
            ELSE 'Newbie'
        END                                         AS reputation_tier,
        CASE
            WHEN ubad.gold_cnt > 0 THEN 1
            ELSE 0
        END                                         AS has_gold_badge,
        CASE
            WHEN ub.user_id IN (SELECT user_id FROM gold_active_users) THEN 1
            ELSE 0
        END                                         AS gold_and_active
    FROM user_base ub
    LEFT JOIN user_badges ubad   ON ub.user_id = ubad.user_id
    LEFT JOIN user_posts up      ON ub.user_id = up.user_id
    LEFT JOIN user_votes uv      ON ub.user_id = uv.voter_id
),

/* ------------------------------------------------------------------ *
 * 9️⃣  Ranked view – compute dense rank over a composite score       *
 * ------------------------------------------------------------------ */
ranked_users AS (
    SELECT
        fus.*,
        DENSE_RANK() OVER (
            ORDER BY
                (fus.reputation * 0.4
                 + fus.total_badges * 10
                 + fus.answer_to_question_ratio * 1000
                 + fus.vote_balance * 0.2) DESC
        ) AS performance_rank,
        ROW_NUMBER() OVER (ORDER BY fus.last_activity_ts DESC) AS recent_activity_seq
    FROM final_user_stats fus
)

/* ------------------------------------------------------------------ *
 * 🔚  Final SELECT – return top 100 users plus a UNION ALL with   *
 *       the 5 most popular tags (by question count)               *
 * ------------------------------------------------------------------ */
SELECT
    ru.user_id,
    ru.display_name,
    ru.reputation,
    ru.account_age_days,
    ru.profile_views,
    ru.net_votes,
    ru.total_badges,
    ru.gold_cnt,
    ru.silver_cnt,
    ru.bronze_cnt,
    ru.answer_to_question_ratio,
    ru.reputation_tier,
    ru.performance_rank,
    ru.recent_activity_seq,
    NULL::varchar(35)        AS tag_name,
    NULL::int                AS tag_question_cnt,
    NULL::decimal            AS tag_avg_answers
FROM ranked_users ru
WHERE ru.performance_rank <= 100

UNION ALL

SELECT
    NULL::int                AS user_id,
    NULL::varchar(40)        AS display_name,
    NULL::int                AS reputation,
    NULL::numeric            AS account_age_days,
    NULL::int                AS profile_views,
    NULL::int                AS net_votes,
    NULL::int                AS total_badges,
    NULL::int                AS gold_cnt,
    NULL::int                AS silver_cnt,
    NULL::int                AS bronze_cnt,
    NULL::decimal            AS answer_to_question_ratio,
    NULL::varchar(20)        AS reputation_tier,
    NULL::int                AS performance_rank,
    NULL::int                AS recent_activity_seq,
    ts.tag_name,
    ts.question_cnt,
    ts.avg_answers_per_q
FROM (
    SELECT
        tag_name,
        question_cnt,
        avg_answers_per_q
    FROM tag_stats
    ORDER BY question_cnt DESC
    LIMIT 5
) ts
ORDER BY
    performance_rank NULLS LAST,
    tag_question_cnt DESC NULLS LAST;
