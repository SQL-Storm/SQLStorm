-- {"query": "3416.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1925} 

WITH 
/* 1. Basic user activity aggregates */
UserActivity AS (
    SELECT 
        u.Id                                     AS UserId,
        COALESCE(u.DisplayName, 'Anonymous')     AS DisplayName,
        COALESCE(u.Reputation,0)                 AS BaseReputation,
        (SELECT COUNT(*) FROM Posts p 
         WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p 
         WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) FROM Badges b 
         WHERE b.UserId = u.Id AND b.Class = 1)      AS GoldBadgeCount
    FROM Users u
),

/* 2. Weighted score per user */
UserScore AS (
    SELECT 
        ua.*,
        (ua.BaseReputation * 0.5) +
        (ua.QuestionCount * 10)   +
        (ua.AnswerCount   * 20)   +
        (ua.GoldBadgeCount * 100) AS WeightedScore
    FROM UserActivity ua
),

/* 3. Top‑N users by score */
TopUsers AS (
    SELECT 
        us.*,
        ROW_NUMBER() OVER (ORDER BY us.WeightedScore DESC) AS Rank
    FROM UserScore us
    WHERE us.WeightedScore > 0
),

/* 4. Tag‑level statistics for open questions */
TagStats AS (
    SELECT 
        t.TagName,
        COUNT(p.Id)                               AS TaggedQuestionCount,
        SUM(p.Score)                              AS TotalScore,
        AVG(p.ViewCount)                          AS AvgViews,
        STRING_AGG(DISTINCT LOWER(u.DisplayName), ',') AS UsersInvolved
    FROM Tags t
    JOIN Posts p 
      ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    JOIN Users u 
      ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1               -- only questions
      AND p.ClosedDate IS NULL           -- exclude closed
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 100
),

/* 5. Most recent close event per post (if any) */
RecentClosed AS (
    SELECT 
        ph.PostId,
        MAX(ph.CreationDate)                     AS ClosedAt,
        ph.Comment                               AS CloseReasonRaw,
        TRY_CAST(NULLIF(ph.Comment, '') AS int) AS CloseReasonId   -- legacy vs current ids
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10            -- Post Closed
    GROUP BY ph.PostId, ph.Comment
),

/* 6. Combine everything for the benchmark */
Combined AS (
    SELECT 
        tu.Rank,
        tu.DisplayName,
        tu.WeightedScore,
        ts.TagName,
        ts.TaggedQuestionCount,
        ts.TotalScore,
        rc.ClosedAt,
        COALESCE(crt.Name,'Unknown')            AS CloseReasonName,
        CASE 
            WHEN rc.CloseReasonId IS NULL THEN 'N/A'
            WHEN rc.CloseReasonId BETWEEN 1 AND 20 THEN 'Legacy'
            ELSE 'Current' 
        END                                     AS ReasonEra,
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.PostId = rc.PostId 
           AND c.UserId = tu.UserId)           AS UserCommentCountOnClosedPost
    FROM TopUsers tu
    LEFT JOIN LATERAL (
        SELECT *
        FROM TagStats
        ORDER BY TaggedQuestionCount DESC
        LIMIT 1
    ) ts ON TRUE
    LEFT JOIN LATERAL (
        SELECT *
        FROM Posts p
        WHERE p.OwnerUserId = tu.UserId
        ORDER BY p.CreationDate DESC
        LIMIT 1
    ) latestp ON TRUE
    LEFT JOIN RecentClosed rc 
      ON rc.PostId = latestp.Id
    LEFT JOIN CloseReasonTypes crt 
      ON crt.Id = rc.CloseReasonId
    WHERE tu.Rank <= 50
)

/* Final result set – unioned with a spare “heavy‑tag” bucket for set‑operator stress */
SELECT *
FROM Combined

UNION ALL

SELECT 
    NULL AS Rank,
    NULL AS DisplayName,
    NULL AS WeightedScore,
    ts.TagName,
    ts.TaggedQuestionCount,
    ts.TotalScore,
    NULL AS ClosedAt,
    NULL AS CloseReasonName,
    NULL AS ReasonEra,
    NULL AS UserCommentCountOnClosedPost
FROM TagStats ts
WHERE ts.TaggedQuestionCount > (SELECT AVG(TaggedQuestionCount) FROM TagStats);
