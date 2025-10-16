WITH TagUsage AS (
    SELECT 
        t.TagName,
        t.Count,
        p.PostTypeId,
        p.Id AS PostId,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.CreationDate DESC) AS RecentUsageRank
    FROM 
        Tags t
        JOIN Posts p ON t.WikiPostId = p.Id AND p.PostTypeId = 1
),
TopTags AS (
    SELECT 
        TagName,
        COUNT(DISTINCT PostId) AS QuestionCount,
        AVG( (CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - CreationDate)) AS DOUBLE PRECISION) / 86400.0) ) AS AvgDaysSinceLastUse
    FROM 
        TagUsage
    WHERE 
        RecentUsageRank = 1
    GROUP BY 
        TagName
),
UserAnswerStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT a.Id) AS TotalAnswers,
        AVG( (CAST(EXTRACT(EPOCH FROM (a.CreationDate - u.CreationDate)) AS DOUBLE PRECISION) / 86400.0) ) AS AvgDaysToAnswer
    FROM 
        Users u
        LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    GROUP BY 
        u.Id, u.DisplayName
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,22,24,25,31,33,34,35,36,37,38,50,52,53,66) THEN 1 ELSE 0 END) AS ChangeCount,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10,11,12,13,14,15,16,17,18,19,20,22,24,25,31,33,34,35,36,37,38,50,52,53,66) THEN ph.CreationDate END) AS LastChangeDate
    FROM 
        PostHistory ph
    GROUP BY 
        ph.PostId
),
FullOuterJoin AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        u.DisplayName AS OwnerName,
        COALESCE(US2.TotalAnswers, 0) AS TotalAnswers,
        US2.AvgDaysToAnswer,
        HS.ChangeCount,
        HS.LastChangeDate
    FROM 
        Posts p
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
        LEFT JOIN UserAnswerStats US2 ON u.Id = US2.UserId
        LEFT JOIN PostHistorySummary HS ON p.Id = HS.PostId
    WHERE 
        p.PostTypeId = 1
)
SELECT
    PostId,
    Title,
    STRING_AGG(Tags, ', ') AS TagList,
    PostTypeId,
    Score,
    CreationDate,
    OwnerName,
    COALESCE(TotalAnswers, 0) AS TotalAnswers,
    ROUND(COALESCE(AvgDaysToAnswer, 0.0), 2) AS AvgDaysToAnswer,
    ChangeCount,
    LastChangeDate,
    (Score + COALESCE(TotalAnswers,0) * 2 - COALESCE(ChangeCount,0) * 0.5) AS PerformanceScore,
    CASE WHEN OwnerName IS NULL THEN 'Unknown Owner' ELSE OwnerName END AS OwnerDisplay,
    CASE WHEN LastChangeDate IS NULL OR LastChangeDate < (CreationDate + INTERVAL '180 days') THEN 'Stable' ELSE 'Recently Modified' END AS ModStatus
FROM
    FullOuterJoin
WHERE
    (Score > 0 OR COALESCE(TotalAnswers, 0) > 0)
    AND (ChangeCount IS NULL OR ChangeCount < 10)
GROUP BY
    PostId,
    Title,
    PostTypeId,
    Score,
    CreationDate,
    OwnerName,
    TotalAnswers,
    AvgDaysToAnswer,
    ChangeCount,
    LastChangeDate
ORDER BY
    PerformanceScore DESC
LIMIT 100;