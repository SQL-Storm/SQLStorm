-- {"query": "3801.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2619} 

WITH
/* 1️⃣ Tag‑level question aggregates */
TagQuestions AS (
    SELECT
        t.Id                         AS TagId,
        t.TagName,
        COUNT(p.Id)                  AS QuestionCnt,
        SUM(p.Score)                 AS QuestionScore,
        MAX(p.CreationDate)          AS LastQuestionDate
    FROM Tags t
    JOIN Posts p
      ON p.PostTypeId = 1
     AND p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY t.Id, t.TagName
),

/* 2️⃣ Per‑user activity summary */
UserStats AS (
    SELECT
        u.Id                         AS UserId,
        COALESCE(u.DisplayName,'Anonymous') AS DisplayName,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionsAsked,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswersGiven,
        SUM(COALESCE(p.Score,0))    AS TotalPostScore,
        MAX(p.LastEditDate)         AS LastEditDate
    FROM Users u
    LEFT JOIN Posts p
      ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

/* 3️⃣ Badge points per user (Gold = 1000, Silver = 500, Bronze = 100) */
BadgePoints AS (
    SELECT
        b.UserId,
        SUM(CASE b.Class WHEN 1 THEN 1000 WHEN 2 THEN 500 ELSE 100 END) AS BadgeScore
    FROM Badges b
    GROUP BY b.UserId
),

/* 4️⃣ Top scorer per tag (answers only) */
UserTagScore AS (
    SELECT
        t.TagName,
        u.Id                        AS UserId,
        COALESCE(u.DisplayName,'Anonymous') AS DisplayName,
        u.Reputation,
        SUM(COALESCE(p.Score,0))    AS TagScore,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY SUM(COALESCE(p.Score,0)) DESC) AS rn
    FROM TagQuestions t
    JOIN Posts p
      ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
     AND p.PostTypeId = 2                      -- answers
    JOIN Users u
      ON u.Id = p.OwnerUserId
    GROUP BY t.TagName, u.Id, u.DisplayName, u.Reputation
),

/* 5️⃣ Most recent close‑vote info per post */
RecentCloseVotes AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END)      AS CloseDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN CAST(ph.Comment AS INT) END) AS CloseReasonId
    FROM PostHistory ph
    GROUP BY ph.PostId
)

SELECT
    tq.TagName,
    tq.QuestionCnt,
    tq.QuestionScore,
    uts.DisplayName,
    uts.Reputation,
    uts.QuestionsAsked,
    uts.AnswersGiven,
    uts.TotalPostScore,
    COALESCE(bp.BadgeScore,0)        AS BadgeScore,
    utsc.TagScore,
    rc.CloseDate,
    cr.Name                         AS CloseReason,
    CASE
        WHEN rc.CloseReasonId IS NULL THEN 'Open'
        WHEN cr.Name IS NULL          THEN 'UnknownReason'
        ELSE                         'Closed'
    END                             AS Status,
    /* fancy string expression mixing NULL‑logic */
    CONCAT('Tag ',tq.TagName,': ',COALESCE(CAST(tq.QuestionCnt AS VARCHAR), '0'),' Qs, ',
           COALESCE(CAST(tq.QuestionScore AS VARCHAR), '0'),' pts')                AS Summary
FROM TagQuestions            tq
LEFT JOIN UserTagScore      utsc  ON utsc.TagName = tq.TagName AND utsc.rn = 1
LEFT JOIN UserStats         uts   ON uts.UserId = utsc.UserId
LEFT JOIN BadgePoints       bp    ON bp.UserId = uts.UserId
/* correlated sub‑query to fetch the latest question of the tag for close‑vote lookup */
LEFT JOIN LATERAL (
        SELECT p.Id
        FROM Posts p
        WHERE p.Tags LIKE CONCAT('%<', tq.TagName, '>%')
          AND p.PostTypeId = 1
        ORDER BY p.CreationDate DESC
        LIMIT 1
) AS latest_q ON TRUE
LEFT JOIN RecentCloseVotes rc ON rc.PostId = latest_q.Id
LEFT JOIN CloseReasonTypes cr ON cr.Id = rc.CloseReasonId
WHERE tq.QuestionCnt > 10

UNION ALL

/* 6️⃣ Global aggregation row */
SELECT
    'AllTags'                         AS TagName,
    SUM(tq.QuestionCnt)                AS QuestionCnt,
    SUM(tq.QuestionScore)              AS QuestionScore,
    NULL                               AS DisplayName,
    NULL                               AS Reputation,
    NULL                               AS QuestionsAsked,
    NULL                               AS AnswersGiven,
    SUM(tq.QuestionScore)              AS TotalPostScore,
    NULL                               AS BadgeScore,
    NULL                               AS TagScore,
    NULL                               AS CloseDate,
    NULL                               AS CloseReason,
    'Aggregated'                       AS Status,
    'Overall summary'                  AS Summary
FROM TagQuestions tq
WHERE tq.QuestionCnt > 10
ORDER BY QuestionScore DESC;
