-- {"query": "4994.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1159} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as rn_by_type,
        AVG(CAST(p.Score AS DECIMAL)) OVER(PARTITION BY p.PostTypeId) AS avg_score_for_type,
        LAG(p.Score, 1, 0) OVER(ORDER BY p.CreationDate) AS previous_post_score
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) AND p.Score > 0
),
CommentAggregates AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        AVG(CAST(c.Score AS DECIMAL)) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
PostLinkCounts AS (
    SELECT
        pl.PostId,
        COUNT(pl.Id) AS LinkCount,
        SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinkCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
),
UserPostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS UserPostCount,
        SUM(p.Score) AS UserTotalPostScore,
        AVG(CAST(p.Score AS DECIMAL)) AS UserAvgPostScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.PostTypeId IN (1, 2)
    GROUP BY p.OwnerUserId
)
SELECT
    rp.PostId,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    rp.AnswerCount,
    rp.FavoriteCount,
    CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    rp.rn_by_type,
    rp.avg_score_for_type,
    rp.previous_post_score,
    COALESCE(ca.CommentCount, 0) AS TotalComments,
    COALESCE(ca.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(ca.AvgCommentScore, 0.0) AS AvgCommentScore,
    ca.LastCommentDate,
    COALESCE(plc.LinkCount, 0) AS TotalPostLinks,
    COALESCE(plc.DuplicateLinkCount, 0) AS TotalDuplicateLinks,
    COALESCE(ups.UserPostCount, 0) AS UserTotalPosts,
    COALESCE(ups.UserTotalPostScore, 0) AS UserTotalScore,
    COALESCE(ups.UserAvgPostScore, 0.0) AS UserAvgScore,
    CASE
        WHEN rp.OwnerReputation >= 100000 THEN 'Legendary'
        WHEN rp.OwnerReputation >= 50000 THEN 'High Reputation'
        WHEN rp.OwnerReputation >= 10000 THEN 'Experienced'
        WHEN rp.OwnerReputation >= 1000 THEN 'Intermediate'
        ELSE 'Novice'
    END AS ReputationTier,
    UPPER(SUBSTRING(rp.OwnerDisplayName, 1, 3)) AS DisplayNamePrefix,
    CASE
        WHEN rp.PostScore > (rp.avg_score_for_type * 2) THEN 'Above Average'
        WHEN rp.PostScore < (rp.avg_score_for_type / 2) THEN 'Below Average'
        ELSE 'Average'
    END AS PerformanceVsAverage,
    (rp.PostScore * 1.5) + (COALESCE(ca.CommentCount, 0) * 0.5) - (COALESCE(plc.DuplicateLinkCount, 0) * 2) AS CustomMetric
FROM RankedPosts rp
LEFT JOIN CommentAggregates ca ON rp.PostId = ca.PostId
LEFT JOIN PostLinkCounts plc ON rp.PostId = plc.PostId
LEFT JOIN UserPostStats ups ON rp.OwnerUserId = ups.OwnerUserId
WHERE rp.rn_by_type <= 100 -- Limit to the top 100 posts of each type by creation date
ORDER BY rp.PostTypeId, rp.rn_by_type;
