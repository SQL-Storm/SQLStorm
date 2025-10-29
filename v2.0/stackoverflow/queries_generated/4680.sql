-- {"query": "4680.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1059} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_score_views,
        DENSE_RANK() OVER (ORDER BY p.CreationDate) AS dr_creation_date,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS previous_day_score,
        SUM(p.AnswerCount) OVER (ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_answer_count
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.Score > 0 AND p.ViewCount > 100
),
UserPostEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId = 2
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.Id END) AS BodyEdits,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN ph.Comment ELSE NULL END) AS LastCloseReason,
        CASE WHEN COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 19 THEN ph.Id END) > 0 THEN 'Protected' ELSE 'Not Protected' END AS ProtectionStatus
    FROM PostHistory ph
    WHERE ph.CreationDate >= DATE('now', '-30 day')
    GROUP BY ph.PostId
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    rp.Score,
    rp.ViewCount,
    rp.cumulative_answer_count,
    upe.DisplayName AS OwnerDisplayName,
    upe.TotalPostsOwned,
    upe.TotalComments,
    CASE
        WHEN upe.TotalUpvotesGiven > 500 THEN 'Power User'
        WHEN upe.TotalUpvotesGiven > 100 THEN 'Frequent Voter'
        ELSE 'Regular User'
    END AS UserVotingTier,
    COALESCE(phs.BodyEdits, 0) AS BodyEditCount,
    COALESCE(phs.LastCloseReason, 'No Close Action') AS MostRecentCloseReason,
    phs.ProtectionStatus,
    CASE
        WHEN rp.previous_day_score < rp.Score THEN 'Increased'
        WHEN rp.previous_day_score > rp.Score THEN 'Decreased'
        ELSE 'Stable'
    END AS ScoreTrend,
    CASE
        WHEN rp.rn_score_views <= 10 THEN 'Top 10 in Type'
        WHEN rp.rn_score_views <= 50 THEN 'Top 50 in Type'
        ELSE 'Other'
    END AS RankInCategory,
    COALESCE(rp.Title, 'No Title') || ' - ' || rp.PostTypeName AS PostIdentifier,
    CASE
        WHEN rp.Title LIKE '%performance%' OR rp.Title LIKE '%benchmark%' THEN 'Performance Related'
        WHEN rp.Title LIKE '%sql%' OR rp.Title LIKE '%database%' THEN 'Database Related'
        ELSE 'General'
    END AS ContentCategory
FROM RankedPosts rp
INNER JOIN UserPostEngagement upe ON rp.OwnerUserId = upe.UserId
LEFT JOIN PostHistorySummary phs ON rp.PostId = phs.PostId
WHERE rp.dr_creation_date > 1000
ORDER BY rp.Score DESC, rp.ViewCount DESC
LIMIT 100;
