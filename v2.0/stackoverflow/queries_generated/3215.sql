-- {"query": "3215.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2237} 

WITH
    /* ------------------------------------------------------------------
       1. Aggregate basic user statistics (badges, posts, scores)
       ------------------------------------------------------------------ */
    UserStats AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COUNT(DISTINCT b.Id)                               AS BadgeCount,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)      AS GoldBadges,
            AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END)  AS AvgQuestionScore,
            COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount
        FROM Users u
        LEFT JOIN Badges b   ON b.UserId = u.Id
        LEFT JOIN Posts  p   ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    /* ------------------------------------------------------------------
       2. Tag meta‑information (visibility, prefix, etc.)
       ------------------------------------------------------------------ */
    TagInfo AS (
        SELECT
            t.Id,
            t.TagName,
            COALESCE(t.Count,0)                                   AS TagUseCount,
            CASE WHEN t.IsModeratorOnly = 1 THEN 'ModOnly' ELSE 'Public' END AS Visibility,
            SUBSTRING(t.TagName FROM 1 FOR 3)                     AS TagPrefix
        FROM Tags t
    ),

    /* ------------------------------------------------------------------
       3. Core question metrics with window functions and correlated sub‑queries
       ------------------------------------------------------------------ */
    QuestionMetrics AS (
        SELECT
            p.Id                                AS QuestionId,
            p.Title,
            p.CreationDate,
            p.Score,
            p.ViewCount,
            p.FavoriteCount,
            p.Tags,
            COALESCE(p.AnswerCount,0)           AS AnswerCount,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS RN,
            COUNT(*)      OVER ()               AS TotalQuestions,
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
            (SELECT MAX(CreationDate) FROM PostHistory ph
                 WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10)               AS LastCloseDate
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),

    /* ------------------------------------------------------------------
       4. Extract close‑reason IDs from PostHistory (type = 10)
       ------------------------------------------------------------------ */
    ClosedReason AS (
        SELECT
            ph.PostId,
            CASE
                WHEN ph.Comment ~ '^\d+$' THEN CAST(ph.Comment AS integer)
                ELSE NULL
            END                          AS CloseReasonId,
            ph.CreationDate              AS ClosedOn
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId = 10
    ),

    /* ------------------------------------------------------------------
       5. Join everything together, add string handling and NULL logic
       ------------------------------------------------------------------ */
    Aggregated AS (
        SELECT
            q.QuestionId,
            q.Title,
            q.Score,
            q.ViewCount,
            q.FavoriteCount,
            q.AnswerCount,
            q.RN,
            q.TotalQuestions,
            q.UpVotes,
            q.DownVotes,
            cr.CloseReasonId,
            cr.ClosedOn,
            u.DisplayName,
            u.Reputation,
            us.BadgeCount,
            us.GoldBadges,
            us.AvgQuestionScore,
            us.AnswerCount               AS UserAnswerCount,
            t.TagName,
            t.Visibility,
            t.TagPrefix,
            CASE
                WHEN q.Tags IS NOT NULL THEN
                    array_length(string_to_array(substring(q.Tags,2,length(q.Tags)-2), '><'),1)
                ELSE 0
            END                          AS TagCount,
            COALESCE(q.LastCloseDate, cr.ClosedOn) AS EffectiveCloseDate
        FROM QuestionMetrics q
        LEFT JOIN Users u          ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = q.QuestionId)
        LEFT JOIN UserStats us    ON us.Id = u.Id
        LEFT JOIN ClosedReason cr ON cr.PostId = q.QuestionId
        LEFT JOIN LATERAL (
            SELECT ti.TagName, ti.Visibility, ti.TagPrefix
            FROM TagInfo ti
            WHERE q.Tags LIKE '%' || ti.TagName || '%'
            LIMIT 1
        ) t ON TRUE
        WHERE q.RN <= 5                     -- top‑5 per user
           OR q.AnswerCount = 0             -- also include unanswered
    )

/* ------------------------------------------------------------------
   Final result set with complex predicates and a set operator
   ------------------------------------------------------------------ */
SELECT
    QuestionId,
    Title,
    Score,
    ViewCount,
    FavoriteCount,
    AnswerCount,
    TagCount,
    DisplayName,
    Reputation,
    BadgeCount,
    GoldBadges,
    AvgQuestionScore,
    UserAnswerCount,
    TagName,
    Visibility,
    TagPrefix,
    EffectiveCloseDate
FROM Aggregated
WHERE (Reputation > 10000 OR GoldBadges > 5)
  AND (Score + ViewCount/1000.0) > 50
  AND (EffectiveCloseDate IS NULL
       OR EffectiveCloseDate < CURRENT_TIMESTAMP - INTERVAL '30 days')

UNION ALL

/* Return a single “empty” row when no rows satisfy the above conditions */
SELECT
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
WHERE NOT EXISTS (SELECT 1 FROM Aggregated);
