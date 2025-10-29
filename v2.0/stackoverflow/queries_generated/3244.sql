-- {"query": "3244.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1704} 

/*  Complex performance‑benchmark query over the StackOverflow schema  */
WITH RECURSIVE
    /* 1️⃣ Users with at least one gold (Class = 1) badge  */
    gold_badge_users AS (
        SELECT DISTINCT b.UserId
        FROM Badges b
        WHERE b.Class = 1
    ),

    /* 2️⃣ Question‑level stats: answer count, accepted answer flag, duplicate‑close count  */
    question_stats AS (
        SELECT
            q.Id                                   AS QuestionId,
            q.OwnerUserId                           AS OwnerUserId,
            q.Score                                 AS QuestionScore,
            COALESCE(q.AnswerCount, 0)              AS AnswerCount,
            CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAccepted,
            /* correlated subquery to count duplicate‑close events from PostHistory */
            (
                SELECT COUNT(*)
                FROM PostHistory ph
                WHERE ph.PostId = q.Id
                  AND ph.PostHistoryTypeId = 10                -- Post Closed
                  AND ph.Comment = '101'                       -- Duplicate close reason
            )                                        AS DuplicateCloseCount
        FROM Posts q
        WHERE q.PostTypeId = 1                                   -- only questions
    ),

    /* 3️⃣ Tag extraction per question (splits <tag1><tag2>…)  */
    question_tags AS (
        SELECT
            qs.QuestionId,
            TRIM(BOTH '><' FROM UNNEST(
                regexp_split_to_array(qs.Tags, '><')
            )) AS Tag
        FROM (
            SELECT Id, Tags
            FROM Posts
            WHERE PostTypeId = 1 AND Tags IS NOT NULL
        ) qs
    ),

    /* 4️⃣ Aggregate tag usage per user  */
    user_tag_agg AS (
        SELECT
            qs.OwnerUserId               AS UserId,
            COUNT(DISTINCT qt.Tag)       AS DistinctTagCount,
            STRING_AGG(DISTINCT qt.Tag, ',') FILTER (WHERE qt.Tag IS NOT NULL) AS TagList
        FROM question_stats qs
        LEFT JOIN question_tags qt
               ON qs.QuestionId = qt.QuestionId
        GROUP BY qs.OwnerUserId
    ),

    /* 5️⃣ Answer‑level stats per user (including vote‑derived score)  */
    answer_stats AS (
        SELECT
            a.OwnerUserId                            AS UserId,
            COUNT(*)                                 AS AnswerCount,
            AVG(a.Score)                             AS AvgAnswerScore,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)  AS UpVoteTotal,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)  AS DownVoteTotal
        FROM Posts a
        LEFT JOIN Votes v
               ON v.PostId = a.Id AND v.VoteTypeId IN (2,3)
        WHERE a.PostTypeId = 2                      -- only answers
        GROUP BY a.OwnerUserId
    ),

    /* 6️⃣ Recent activity per user (latest post date, latest badge date) */
    recent_activity AS (
        SELECT
            u.Id                                      AS UserId,
            GREATEST(
                COALESCE(MAX(p.CreationDate), '1970-01-01'::timestamp),
                COALESCE(MAX(b.Date),          '1970-01-01'::timestamp)
            )                                         AS LastActivityDate
        FROM Users u
        LEFT JOIN Posts p
               ON p.OwnerUserId = u.Id
        LEFT JOIN Badges b
               ON b.UserId = u.Id
        GROUP BY u.Id
    ),

    /* 7️⃣ Combine all per‑user metrics */
    user_metrics AS (
        SELECT
            u.Id                                         AS UserId,
            u.DisplayName,
            u.Reputation,
            COALESCE(qs_q.QuestionCount,0)                AS TotalQuestions,
            COALESCE(qs_a.AnswerCount,0)                  AS TotalAnswers,
            COALESCE(qs_a.AvgAnswerScore,0)              AS AvgAnswerScore,
            COALESCE(gb.HasGoldBadge,0)                  AS HasGoldBadge,
            COALESCE(uta.DistinctTagCount,0)             AS DistinctTagCount,
            COALESCE(uta.TagList,'')                     AS TagList,
            COALESCE(ra.LastActivityDate,'1970-01-01')   AS LastActivityDate,
            RANK() OVER (ORDER BY u.Reputation DESC)    AS ReputationRank,
            ROW_NUMBER() OVER (PARTITION BY u.Reputation ORDER BY u.Id) AS RepTieBreaker
        FROM Users u
        LEFT JOIN (
            SELECT OwnerUserId, COUNT(*) AS QuestionCount
            FROM question_stats
            GROUP BY OwnerUserId
        ) qs_q
               ON qs_q.OwnerUserId = u.Id
        LEFT JOIN answer_stats qs_a
               ON qs_a.UserId = u.Id
        LEFT JOIN (
            SELECT UserId, 1 AS HasGoldBadge
            FROM gold_badge_users
        ) gb
               ON gb.UserId = u.Id
        LEFT JOIN user_tag_agg uta
               ON uta.UserId = u.Id
        LEFT JOIN recent_activity ra
               ON ra.UserId = u.Id
    )

/* Final result set with a UNION to also show top‑10 most‑active tags */
SELECT
    um.UserId,
    um.DisplayName,
    um.Reputation,
    um.TotalQuestions,
    um.TotalAnswers,
    ROUND(um.AvgAnswerScore,2)          AS AvgAnswerScore,
    um.HasGoldBadge,
    um.DistinctTagCount,
    um.TagList,
    um.LastActivityDate,
    um.ReputationRank,
    um.RepTieBreaker,
    NULL::varchar(35)                   AS TagName,
    NULL::int                           AS TagQuestionCount
FROM user_metrics um
WHERE um.ReputationRank <= 100                     -- top‑100 users
  AND um.HasGoldBadge = 1
  AND um.TotalQuestions >= 5
  AND um.TotalAnswers >= 10

UNION ALL

SELECT
    NULL::int,
    NULL::varchar(40),
    NULL::int,
    NULL::int,
    NULL::int,
    NULL::numeric,
    NULL::bit,
    NULL::int,
    NULL::varchar,
    NULL::timestamp,
    NULL::int,
    NULL::int,
    t.TagName,
    t.Count AS TagQuestionCount
FROM (
    SELECT
        tg.TagName,
        tg.Count,
        ROW_NUMBER() OVER (ORDER BY tg.Count DESC) AS rn
    FROM Tags tg
) t
WHERE t.rn <= 10
ORDER BY
    ReputationRank NULLS LAST,
    TagQuestionCount DESC NULLS FIRST;
