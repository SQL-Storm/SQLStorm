WITH 
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
UserScore AS (
    SELECT 
        ua.*,
        (ua.BaseReputation * 0.5) +
        (ua.QuestionCount * 10)   +
        (ua.AnswerCount   * 20)   +
        (ua.GoldBadgeCount * 100) AS WeightedScore
    FROM UserActivity ua
),
TopUsers AS (
    SELECT 
        us.*,
        ROW_NUMBER() OVER (ORDER BY us.WeightedScore DESC) AS Rank
    FROM UserScore us
    WHERE us.WeightedScore > 0
),
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
    WHERE p.PostTypeId = 1
      AND p.ClosedDate IS NULL
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 100
),
RecentClosed AS (
    SELECT 
        ph.PostId,
        MAX(ph.CreationDate)                     AS ClosedAt,
        ph.Comment                               AS CloseReasonRaw,
        NULLIF(ph.Comment, '') AS CloseReasonRaw2,
        -- try to parse numeric close reason where possible; portable SQL: use CASE / TRY_CAST if available,
        -- otherwise attempt CAST; here we use a safe CAST inside CASE for dialects that support TRY_CAST or equivalent.
        CASE
          WHEN NULLIF(ph.Comment,'') IS NULL THEN NULL
          WHEN ph.Comment ~ '^[0-9]+$' THEN CAST(ph.Comment AS INTEGER)
          ELSE NULL
        END AS CloseReasonId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId, ph.Comment
),
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
        SELECT TagName, TaggedQuestionCount, TotalScore, AvgViews, UsersInvolved
        FROM TagStats
        ORDER BY TaggedQuestionCount DESC
        LIMIT 1
    ) ts ON TRUE
    LEFT JOIN LATERAL (
        SELECT p.Id, p.OwnerUserId, p.CreationDate
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
SELECT *
FROM Combined

UNION ALL

SELECT 
    CAST(NULL AS INTEGER) AS Rank,
    CAST(NULL AS VARCHAR(4000)) AS DisplayName,
    CAST(NULL AS NUMERIC) AS WeightedScore,
    ts.TagName,
    ts.TaggedQuestionCount,
    ts.TotalScore,
    CAST(NULL AS TIMESTAMP) AS ClosedAt,
    CAST(NULL AS VARCHAR(4000)) AS CloseReasonName,
    CAST(NULL AS VARCHAR(100)) AS ReasonEra,
    CAST(NULL AS INTEGER) AS UserCommentCountOnClosedPost
FROM TagStats ts
WHERE ts.TaggedQuestionCount > (SELECT AVG(TaggedQuestionCount) FROM TagStats)
GROUP BY ts.TagName, ts.TaggedQuestionCount, ts.TotalScore, ts.AvgViews, ts.UsersInvolved;