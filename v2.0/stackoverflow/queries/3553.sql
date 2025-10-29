-- {"query": "3553.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2537}
WITH
user_base AS (
    SELECT
        u.Id                               AS user_id,
        u.DisplayName                      AS display_name,
        u.Reputation                       AS reputation,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.CreationDate)) / 86400
                                           AS account_age_days,
        COALESCE(u.Views,0)                AS total_views,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS net_votes,
        GREATEST(
            COALESCE(
                (SELECT MAX(p.LastActivityDate) FROM Posts p WHERE p.OwnerUserId = u.Id),
                CAST('1970-01-01' AS timestamp)
            ),
            COALESCE(
                (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.UserId = u.Id),
                CAST('1970-01-01' AS timestamp)
            ),
            COALESCE(
                (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.UserId = u.Id),
                CAST('1970-01-01' AS timestamp)
            )
        )                                    AS last_activity_ts
    FROM Users u
),

user_badges AS (
    SELECT
        b.UserId                           AS user_id,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_cnt,
        SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS tagbased_cnt,
        COUNT(*)                           AS total_badges
    FROM Badges b
    GROUP BY b.UserId
),

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

tag_stats AS (
    SELECT
        qt.primary_tag                       AS tag_name,
        COUNT(*)                             AS question_cnt,
        COALESCE(SUM(a.AnswerCount),0)       AS total_answers,
        CASE WHEN COUNT(*) = 0 THEN 0
             ELSE COALESCE(SUM(a.AnswerCount),0) * 1.0 / COUNT(*)
        END                                 AS avg_answers_per_q
    FROM question_tags qt
    LEFT JOIN Posts a
        ON a.ParentId = qt.post_id
        AND a.PostTypeId = 2
    GROUP BY qt.primary_tag
),

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
            ELSE (CAST(up.answer_cnt AS decimal) / NULLIF(up.question_cnt,0))
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

ranked_users AS (
    SELECT
        fus.user_id,
        fus.display_name,
        fus.reputation,
        fus.account_age_days,
        fus.profile_views,
        fus.net_votes,
        fus.last_activity_ts,
        fus.gold_cnt,
        fus.silver_cnt,
        fus.bronze_cnt,
        fus.tagbased_cnt,
        fus.total_badges,
        fus.question_cnt,
        fus.answer_cnt,
        fus.avg_q_score,
        fus.avg_a_score,
        fus.post_views,
        fus.questions_with_accepted,
        fus.closed_questions,
        fus.last_post_activity,
        fus.upvote_cnt,
        fus.downvote_cnt,
        fus.vote_balance,
        fus.answer_to_question_ratio,
        fus.reputation_tier,
        fus.has_gold_badge,
        fus.gold_and_active,
        DENSE_RANK() OVER (
            ORDER BY
                (fus.reputation * 0.4
                 + COALESCE(fus.total_badges,0) * 10
                 + COALESCE(fus.answer_to_question_ratio,0) * 1000
                 + COALESCE(fus.vote_balance,0) * 0.2) DESC
        ) AS performance_rank,
        ROW_NUMBER() OVER (ORDER BY fus.last_activity_ts DESC) AS recent_activity_seq
    FROM final_user_stats fus
)

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
    CAST(NULL AS varchar(35))        AS tag_name,
    CAST(NULL AS integer)            AS tag_question_cnt,
    CAST(NULL AS numeric)            AS tag_avg_answers
FROM ranked_users ru
WHERE ru.performance_rank <= 100

UNION ALL

SELECT
    CAST(NULL AS integer)                AS user_id,
    CAST(NULL AS varchar(40))        AS display_name,
    CAST(NULL AS integer)                AS reputation,
    CAST(NULL AS numeric)            AS account_age_days,
    CAST(NULL AS integer)                AS profile_views,
    CAST(NULL AS integer)                AS net_votes,
    CAST(NULL AS integer)                AS total_badges,
    CAST(NULL AS integer)                AS gold_cnt,
    CAST(NULL AS integer)                AS silver_cnt,
    CAST(NULL AS integer)                AS bronze_cnt,
    CAST(NULL AS numeric)            AS answer_to_question_ratio,
    CAST(NULL AS varchar(20))        AS reputation_tier,
    CAST(NULL AS integer)                AS performance_rank,
    CAST(NULL AS integer)                AS recent_activity_seq,
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