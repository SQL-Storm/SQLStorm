-- {"query": "3007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 836} 
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
        AVG(DATE_PART('day', CURRENT_TIMESTAMP - CreationDate)) AS AvgDaysSinceLastUse
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
        AVG(DATE_PART('day', a.CreationDate - u.CreationDate)) AS AvgDaysToAnswer
    FROM 
        Users u
        LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    GROUP BY 
        u.Id, u.DisplayName
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,22,24,25,31,33,34,35,36,37,38,50,52,53,66)) AS ChangeCount,
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
        AS2.TotalAnswers,
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
    string_agg(Tags, ', ') AS TagList,
    PostTypeId,
    Score,
    CreationDate,
    OwnerName,
    COALESCE(TotalAnswers, 0) AS TotalAnswers,
    ROUND(COALESCE(AvgDaysToAnswer, 0), 2) AS AvgDaysToAnswer,
    ChangeCount,
    LastChangeDate,
    -- Calculate a composite performance metric based on multiple factors
    (Score + TotalAnswers * 2 - ChangeCount * 0.5) AS PerformanceScore,
    -- Generate a descriptive string with string expressions and NULL handling
    CASE WHEN OwnerName IS NULL THEN 'Unknown Owner' ELSE OwnerName END AS OwnerDisplay,
    -- Example of complex predicate with null logic
    CASE WHEN LastChangeDate IS NULL OR LastChangeDate < CreationDate + INTERVAL '180 days' THEN 'Stable' ELSE 'Recently Modified' END AS ModStatus
FROM
    FullOuterJoin
WHERE
    (Score > 0 OR TotalAnswers > 0)
    AND (ChangeCount IS NULL OR ChangeCount < 10)
ORDER BY
    PerformanceScore DESC
LIMIT 100;