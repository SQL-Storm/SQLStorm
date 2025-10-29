-- {"query": "3492.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1939} 

/*  Performance‑benchmarking query – uses CTEs, window functions, outer joins,
    correlated subqueries, set operators, string manipulation and NULL logic   */
WITH 
/* -------------------------------------------------------------
   Tag‑level aggregates for questions (PostTypeId = 1)
   ------------------------------------------------------------- */
TagStats AS (
    SELECT 
        t.TagName,
        COUNT(p.Id)               AS QuestionCount,
        SUM(p.Score)              AS TotalScore,
        MAX(p.CreationDate)       AS LatestQuestionDate,
        -- extract the most recent question id for later look‑ups
        MAX(CASE WHEN p.CreationDate = MAX(p.CreationDate) OVER (PARTITION BY t.TagName)
                 THEN p.Id END)  AS RecentQuestionId
    FROM Tags t
    JOIN Posts p 
      ON p.PostTypeId = 1
     AND p.Tags LIKE CONCAT('%', t.TagName, '%')
    GROUP BY t.TagName
),

/* -------------------------------------------------------------
   User activity scoring (questions asked, answers given, up‑votes cast)
   ------------------------------------------------------------- */
UserActivity AS (
    SELECT 
        u.Id                                   AS UserId,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v   ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),

/* -------------------------------------------------------------
   Top‑scoring answer per question – uses a window function
   ------------------------------------------------------------- */
TopAnswerPerQuestion AS (
    SELECT 
        a.Id               AS AnswerId,
        a.ParentId         AS QuestionId,
        a.Score,
        ROW_NUMBER() OVER (
            PARTITION BY a.ParentId
            ORDER BY a.Score DESC, a.CreationDate ASC
        )                 AS rn
    FROM Posts a
    WHERE a.PostTypeId = 2               -- answers only
),

/* -------------------------------------------------------------
   Most recent closed‑question info extracted from PostHistory
   ------------------------------------------------------------- */
RecentClosed AS (
    SELECT 
        ph.PostId                AS QuestionId,
        ph.CreationDate          AS ClosedDate,
        ph.Comment               AS CloseReason
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10   -- Post Closed
),

/* -------------------------------------------------------------
   Badges per user concatenated into a single string
   ------------------------------------------------------------- */
BadgesAgg AS (
    SELECT 
        b.UserId,
        STRING_AGG(b.Name, ',') AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
)

/* =============================================================
   Final result set – combines the above CTEs with outer joins,
   correlated sub‑queries, CASE/COALESCE logic and a UNION ALL.
   ============================================================= */
SELECT
    ts.TagName,
    ts.QuestionCount,
    ts.TotalScore,
    ua.DisplayName,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    COALESCE(ba.BadgeList, '')                AS Badges,
    ta.AnswerId,
    ta.Score          AS TopAnswerScore,
    rc.CloseReason,
    CASE 
        WHEN rc.CloseReason IS NULL THEN 'OPEN'
        ELSE rc.CloseReason
    END               AS QuestionStatus
FROM TagStats ts
LEFT JOIN UserActivity ua
    ON ua.UserId = (
        SELECT p.OwnerUserId
        FROM Posts p
        WHERE p.Id = ts.RecentQuestionId
          AND p.OwnerUserId IS NOT NULL
        LIMIT 1
    )
LEFT JOIN BadgesAgg ba
    ON ba.UserId = ua.UserId
LEFT JOIN (
    SELECT AnswerId, QuestionId, Score
    FROM TopAnswerPerQuestion
    WHERE rn = 1
) ta
    ON ta.QuestionId = ts.RecentQuestionId
LEFT JOIN RecentClosed rc
    ON rc.QuestionId = ts.RecentQuestionId
WHERE ts.QuestionCount > 10
  AND (ua.QuestionsAsked > 5 OR ua.AnswersGiven > 20)
ORDER BY ts.TotalScore DESC
LIMIT 100

UNION ALL

/* -------------------------------------------------------------
   Overall summary row (no tag, aggregates across all tags)
   ------------------------------------------------------------- */
SELECT
    'Overall'           AS TagName,
    SUM(ts.QuestionCount) AS QuestionCount,
    SUM(ts.TotalScore)    AS TotalScore,
    NULL                 AS DisplayName,
    NULL                 AS QuestionsAsked,
    NULL                 AS AnswersGiven,
    NULL                 AS Badges,
    NULL                 AS AnswerId,
    NULL                 AS TopAnswerScore,
    NULL                 AS CloseReason,
    NULL                 AS QuestionStatus
FROM TagStats ts;
