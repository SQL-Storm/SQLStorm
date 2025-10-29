-- {"query": "4053.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1420}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY pt.Name ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.Score > 0 AND p.ViewCount > 0 AND p.AnswerCount IS NOT NULL
),
UserPostInteraction AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LatestPostDate,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 50
),
TopContributors AS (
    SELECT
        UPI.UserId,
        UPI.UserName,
        UPI.TotalPostsOwned,
        UPI.TotalScore,
        CASE
            WHEN UPI.TotalScore > 10000 THEN 'High Contributor'
            WHEN UPI.TotalScore > 5000 THEN 'Medium Contributor'
            ELSE 'Low Contributor'
        END AS ContributionLevel,
        RANK() OVER (ORDER BY UPI.TotalScore DESC) AS ScoreRank
    FROM UserPostInteraction UPI
),
PostEditAnalysis AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.Id) AS EditHistoryCount,
        MAX(ph.CreationDate) AS LastEditDate,
        CASE
            WHEN COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) > 0 THEN 'Edited'
            WHEN COUNT(CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN ph.Id END) > 0 THEN 'Rolled Back'
            ELSE 'No Significant Edits'
        END AS EditStatus,
        AVG(diff_minutes) AS AvgTimeBetweenEdits
    FROM (
        SELECT
            ph.*,
            EXTRACT(EPOCH FROM (ph.CreationDate - LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate))) / 60.0 AS diff_minutes
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    ) ph
    GROUP BY ph.PostId
    HAVING COUNT(ph.Id) > 2
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    tc.UserName AS TopContributorName,
    tc.ContributionLevel,
    tc.ScoreRank,
    pea.EditStatus,
    pea.AvgTimeBetweenEdits,
    CASE
        WHEN rp.Score > 1000 AND rp.ViewCount > 10000 AND rp.AnswerCount > 10 THEN 'Popular and Engaging'
        WHEN rp.Score < 0 AND rp.ViewCount < 1000 THEN 'Low Engagement'
        ELSE 'Standard Performance'
    END AS PerformanceCategory,
    COALESCE(u.DisplayName, p.OwnerDisplayName, 'Community') AS ActualOwnerDisplayName,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3) THEN 'Is Duplicate Of Another Post'
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.RelatedPostId = rp.PostId AND pl.LinkTypeId = 3) THEN 'Has Duplicate Posts Linking To It'
        ELSE 'No Direct Duplicate Links'
    END AS DuplicateStatus
FROM RankedPosts rp
LEFT JOIN Posts p ON rp.PostId = p.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN TopContributors tc ON tc.UserId = p.OwnerUserId
LEFT JOIN PostEditAnalysis pea ON rp.PostId = pea.PostId
WHERE rp.rn <= 100

UNION ALL

SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    tc.UserName AS TopContributorName,
    tc.ContributionLevel,
    tc.ScoreRank,
    pea.EditStatus,
    pea.AvgTimeBetweenEdits,
    CASE
        WHEN rp.Score > 1000 AND rp.ViewCount > 10000 AND rp.AnswerCount > 10 THEN 'Popular and Engaging'
        WHEN rp.Score < 0 AND rp.ViewCount < 1000 THEN 'Low Engagement'
        ELSE 'Standard Performance'
    END AS PerformanceCategory,
    COALESCE(u.DisplayName, p.OwnerDisplayName, 'Community') AS ActualOwnerDisplayName,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3) THEN 'Is Duplicate Of Another Post'
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.RelatedPostId = rp.PostId AND pl.LinkTypeId = 3) THEN 'Has Duplicate Posts Linking To It'
        ELSE 'No Direct Duplicate Links'
    END AS DuplicateStatus
FROM RankedPosts rp
LEFT JOIN Posts p ON rp.PostId = p.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN TopContributors tc ON tc.UserId = p.OwnerUserId
LEFT JOIN PostEditAnalysis pea ON rp.PostId = pea.PostId
WHERE rp.rn > 9900 AND rp.rn <= 10000;