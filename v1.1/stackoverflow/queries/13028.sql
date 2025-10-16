WITH UserActivity AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC, SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) DESC) AS UserRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.LastAccessDate > (CAST('2024-10-01' AS date) - INTERVAL '6 months')
    GROUP BY u.Id, u.DisplayName
),
TagMetrics AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseCount,
        STRING_AGG(DISTINCT u.DisplayName, ', ') AS TopContributors
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags IS NOT NULL AND POSITION('<' || t.TagName || '>' IN p.Tags) > 0
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND (p.ClosedDate IS NULL OR ph.CreationDate > p.ClosedDate)
    GROUP BY t.TagName
),
PostEditHistory AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        COUNT(ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '1 year')
    GROUP BY p.Id, p.Title
)
SELECT 
    ua.DisplayName,
    ua.PostCount,
    ua.TotalQuestionViews,
    ua.AvgAnswerScore,
    tm.TagName,
    tm.PostCount AS TagPostCount,
    tm.CloseCount,
    peh.EditCount,
    peh.LastEditDate,
    CASE 
        WHEN peh.EditCount > 0 THEN (ua.PostCount * 1.0 / peh.EditCount)
        ELSE NULL 
    END AS PostsPerEdit,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.VoteTypeId = 8 AND v.PostId = peh.PostId) AS AvgBounty
FROM UserActivity ua
LEFT JOIN PostEditHistory peh ON ua.Id = peh.PostId
LEFT JOIN TagMetrics tm ON tm.TagName IS NOT NULL AND POSITION(tm.TagName IN COALESCE(peh.Title, '')) > 0
WHERE ua.UserRank <= 100 AND peh.EditCount > 1
GROUP BY
    ua.DisplayName,
    ua.PostCount,
    ua.TotalQuestionViews,
    ua.AvgAnswerScore,
    tm.TagName,
    tm.PostCount,
    tm.CloseCount,
    peh.EditCount,
    peh.LastEditDate,
    ua.UserRank,
    peh.PostId
ORDER BY ua.UserRank, tm.CloseCount DESC;