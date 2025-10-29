-- {"query": "4840.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1069}
WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.UserDisplayName,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(p.ViewCount) AS TotalViewsReceived,
        AVG(CAST(p.Score AS DECIMAL(10, 2))) AS AveragePostScore,
        MAX(p.CreationDate) AS LastPostCreationDate,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName
    HAVING COALESCE(SUM(p.ViewCount), 0) > 1000
),
PostEditFrequency AS (
    SELECT
        rpe.UserId,
        rpe.UserDisplayName,
        COUNT(DISTINCT rpe.PostId) AS PostsEdited,
        MAX(rpe.CreationDate) AS LastEditDate
    FROM RankedPostEdits rpe
    WHERE rpe.rn = 1
    GROUP BY rpe.UserId, rpe.UserDisplayName
    HAVING COUNT(DISTINCT rpe.PostId) > 5
),
LaggedPostScores AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
),
PostScoreDelta AS (
    SELECT
        lps.PostId,
        lps.OwnerUserId,
        lps.Score - lps.PreviousScore AS ScoreDelta
    FROM LaggedPostScores lps
    WHERE lps.rn > 1 AND (lps.Score - lps.PreviousScore) > 5
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.TotalPostsOwned,
    uas.TotalViewsReceived,
    uas.AveragePostScore,
    uas.LastPostCreationDate,
    uas.TotalCommentsMade,
    uas.TotalUpvotesGiven,
    COALESCE(pef.PostsEdited, 0) AS PostsEditedByThisUser,
    pef.LastEditDate,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
    CASE
        WHEN p.ClosedDate IS NOT NULL AND p.AnswerCount = 0 THEN 'Unanswered Closed'
        WHEN p.ClosedDate IS NOT NULL AND p.AnswerCount > 0 THEN 'Answered Closed'
        WHEN p.AnswerCount > 50 THEN 'Highly Answered'
        ELSE 'Standard'
    END AS PostStatusCategory,
    psd.ScoreDelta AS TopScoreIncreaseOnNextPost,
    'Processing Complete' AS StatusMessage
FROM UserActivitySummary uas
LEFT JOIN PostEditFrequency pef ON uas.UserId = pef.UserId
LEFT JOIN Posts p ON uas.UserId = p.OwnerUserId AND p.PostTypeId = 1
    AND p.Id = (
        SELECT Id FROM Posts p2
        WHERE p2.OwnerUserId = uas.UserId AND p2.PostTypeId = 1
        ORDER BY p2.CreationDate DESC
        LIMIT 1
    )
LEFT JOIN PostScoreDelta psd ON uas.UserId = psd.OwnerUserId
WHERE uas.TotalPostsOwned > 10

UNION ALL

SELECT
    CAST(NULL AS BIGINT) AS UserId,
    CAST(NULL AS TEXT) AS DisplayName,
    CAST(NULL AS BIGINT) AS TotalPostsOwned,
    CAST(NULL AS BIGINT) AS TotalViewsReceived,
    CAST(NULL AS DECIMAL(10,2)) AS AveragePostScore,
    CAST(NULL AS TIMESTAMP) AS LastPostCreationDate,
    CAST(NULL AS BIGINT) AS TotalCommentsMade,
    CAST(NULL AS BIGINT) AS TotalUpvotesGiven,
    CAST(NULL AS BIGINT) AS PostsEditedByThisUser,
    CAST(NULL AS TIMESTAMP) AS LastEditDate,
    CAST(NULL AS BIGINT) AS DuplicateLinkCount,
    CAST(NULL AS TEXT) AS PostStatusCategory,
    CAST(NULL AS NUMERIC) AS TopScoreIncreaseOnNextPost,
    CAST(NULL AS TEXT) AS StatusMessage
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM UserActivitySummary uas WHERE uas.UserId = u.Id) AND u.Reputation > 5000

ORDER BY TotalViewsReceived DESC NULLS LAST, DisplayName ASC NULLS FIRST;