-- {"query": "3050.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1519} 

/*  Benchmark query – complex mix of CTEs, joins, window functions, set operators,
    correlated subqueries, string handling and NULL logic on the StackOverflow schema. */
WITH 
/* 1️⃣ Recent (last 30 days) questions with their tag list expanded */
recent_questions AS (
    SELECT 
        p.Id                                    AS QuestionId,
        p.Title,
        p.CreationDate,
        p.Score                                 AS QuestionScore,
        COALESCE(
            NULLIF(
                SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), 
                ''
            ), 
            NULL
        )                                      AS RawTagString,
        regexp_split_to_table(
            COALESCE(
                NULLIF(
                    SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), 
                    ''
                ), 
                ''
            ), 
            '\><'
        )                                      AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1                     -- Question
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),

/* 2️⃣ Answers per question with the latest edit info (correlated subquery) */
answers_with_latest_edit AS (
    SELECT 
        a.Id                                 AS AnswerId,
        a.ParentId                           AS QuestionId,
        a.OwnerUserId                        AS AnswererId,
        a.Score                              AS AnswerScore,
        a.CreationDate,
        (SELECT MAX(ph.CreationDate)
         FROM PostHistory ph
         WHERE ph.PostId = a.Id 
           AND ph.PostHistoryTypeId IN (4,5,6)   -- any edit type
        )                                    AS LastEditDate
    FROM Posts a
    WHERE a.PostTypeId = 2                     -- Answer
),

/* 3️⃣ Aggregate per user: total answers, avg score, recent activity window rank */
user_answer_stats AS (
    SELECT 
        u.Id                                 AS UserId,
        u.DisplayName,
        COUNT(a.AnswerId)                    AS AnswerCount,
        AVG(a.AnswerScore)::numeric(10,2)    AS AvgAnswerScore,
        MAX(a.CreationDate)                  AS LastAnswerDate,
        ROW_NUMBER() OVER (ORDER BY COUNT(a.AnswerId) DESC) AS AnswerRank
    FROM Users u
    LEFT JOIN answers_with_latest_edit a
           ON a.AnswererId = u.Id
    GROUP BY u.Id, u.DisplayName
),

/* 4️⃣ Badge statistics per user, with NULL‑aware CASE handling */
user_badge_stats AS (
    SELECT 
        b.UserId,
        COUNT(*)                              AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(CASE WHEN b.TagBased = 1 THEN b.Name END) AS FirstTagBadge
    FROM Badges b
    GROUP BY b.UserId
),

/* 5️⃣ Most recent comment per answer (correlated subquery) */
latest_comment_per_answer AS (
    SELECT 
        a.AnswerId,
        (SELECT c.Text
         FROM Comments c
         WHERE c.PostId = a.AnswerId
         ORDER BY c.CreationDate DESC
         LIMIT 1)                           AS LatestCommentText
    FROM answers_with_latest_edit a
),

/* 6️⃣ Union of top‑scoring recent questions and their duplicate links (set operator) */
top_questions_union AS (
    SELECT 
        q.QuestionId,
        q.Title,
        q.QuestionScore,
        'Original'        AS Source
    FROM recent_questions q
    WHERE q.QuestionScore >= 50

    UNION ALL

    SELECT 
        pl.PostId        AS QuestionId,
        p.Title,
        p.Score          AS QuestionScore,
        'DuplicateLink'  AS Source
    FROM PostLinks pl
    JOIN Posts p ON p.Id = pl.RelatedPostId
    WHERE pl.LinkTypeId = 3               -- Duplicate
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
)

/* Final SELECT pulling everything together */
SELECT 
    tq.QuestionId,
    tq.Title,
    tq.QuestionScore,
    tq.Source,
    STRING_AGG(DISTINCT rq.Tag, ', ')           AS Tags,
    ua.AnswerCount,
    ua.AvgAnswerScore,
    ub.TotalBadges,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.FirstTagBadge,
    lc.LatestCommentText,
    CASE 
        WHEN ua.AnswerCount IS NULL THEN 'NoAnswers'
        WHEN ua.AvgAnswerScore > 10    THEN 'HighQuality'
        ELSE 'Regular'
    END                                          AS QualityCategory,
    COALESCE(ua.LastAnswerDate, tq.QuestionScore::TEXT) AS ReferenceMetric
FROM top_questions_union tq
LEFT JOIN recent_questions rq
       ON rq.QuestionId = tq.QuestionId
LEFT JOIN user_answer_stats ua
       ON ua.UserId = (
            SELECT a.AnswererId
            FROM answers_with_latest_edit a
            WHERE a.QuestionId = tq.QuestionId
            ORDER BY a.AnswerScore DESC NULLS LAST
            LIMIT 1
         )
LEFT JOIN user_badge_stats ub
       ON ub.UserId = ua.UserId
LEFT JOIN latest_comment_per_answer lc
       ON lc.AnswerId = (
            SELECT a.AnswerId
            FROM answers_with_latest_edit a
            WHERE a.QuestionId = tq.QuestionId
            ORDER BY a.AnswerScore DESC NULLS LAST
            LIMIT 1
         )
GROUP BY 
    tq.QuestionId, tq.Title, tq.QuestionScore, tq.Source,
    ua.AnswerCount, ua.AvgAnswerScore, ub.TotalBadges,
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
    ub.FirstTagBadge, lc.LatestCommentText,
    ua.LastAnswerDate
ORDER BY tq.QuestionScore DESC, ua.AnswerRank NULLS LAST
LIMIT 100;
