WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn_by_type_creation,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS rn_by_type_score,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountForPost,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVoteCountForPost,
        CASE
            WHEN p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1 THEN
                (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = p.OwnerUserId AND p2.CreationDate < p.CreationDate)
            ELSE 0
        END AS PostsOwnedBeforeThis,
        AVG(CAST(p.Score AS NUMERIC(10, 2))) OVER (ORDER BY p.CreationDate ROWS BETWEEN 9 PRECEDING AND CURRENT ROW) AS MovingAvgScore
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
),
TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(CAST(u.Reputation AS NUMERIC(10, 2))) AS AvgReputation
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IS NOT NULL AND u.Id <> -1 AND p.PostTypeId IN (1, 2)
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 100
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    GROUP BY ph.PostId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.CommentCountForPost,
    rp.UpVoteCountForPost,
    rp.PostsOwnedBeforeThis,
    rp.MovingAvgScore,
    tu.TotalPosts AS OwnerTotalPosts,
    tu.TotalScore AS OwnerTotalScore,
    tu.AvgReputation AS OwnerAvgReputation,
    phs.EditCount AS PostEditCount,
    CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    CASE WHEN rp.rn_by_type_creation <= 5 THEN 'Top 5 by Creation Date (Type)' ELSE '' END AS TypeCreationRank,
    CASE WHEN rp.rn_by_type_score <= 5 THEN 'Top 5 by Score (Type)' ELSE '' END AS TypeScoreRank,
    COALESCE(rp.OwnerUserId, -99) AS SafeOwnerUserId,
    CASE WHEN rp.FavoriteCount > 10 THEN 'Popular' ELSE 'Regular' END AS PopularityIndicator,
    CHAR_LENGTH(rp.OwnerDisplayName) AS OwnerDisplayNameLength,
    'Processed_' || SUBSTRING(rp.OwnerDisplayName FROM 1 FOR 3) AS ProcessedDisplayName,
    rp.Score + rp.FavoriteCount * 5 AS WeightedScore,
    CASE
        WHEN rp.OwnerUserId IS NOT NULL AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = rp.OwnerUserId AND b.Name LIKE '%Gold%') THEN 'Has Gold Badge'
        WHEN rp.OwnerUserId IS NOT NULL AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = rp.OwnerUserId AND b.Name LIKE '%Silver%') THEN 'Has Silver Badge'
        ELSE 'No High Tier Badge'
    END AS UserBadgeStatus
FROM RankedPosts rp
LEFT JOIN TopUsers tu ON rp.OwnerUserId = tu.UserId
LEFT JOIN PostHistorySummary phs ON rp.PostId = phs.PostId
WHERE
    (
      (rp.Score > 0 AND rp.ViewCount > 1000 AND rp.CreationDate > DATE '2020-01-01')
      OR rp.FavoriteCount > 50
    )
UNION
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.CommentCountForPost,
    rp.UpVoteCountForPost,
    rp.PostsOwnedBeforeThis,
    rp.MovingAvgScore,
    tu.TotalPosts AS OwnerTotalPosts,
    tu.TotalScore AS OwnerTotalScore,
    tu.AvgReputation AS OwnerAvgReputation,
    phs.EditCount AS PostEditCount,
    CASE WHEN rp.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    CASE WHEN rp.rn_by_type_creation <= 5 THEN 'Top 5 by Creation Date (Type)' ELSE '' END AS TypeCreationRank,
    CASE WHEN rp.rn_by_type_score <= 5 THEN 'Top 5 by Score (Type)' ELSE '' END AS TypeScoreRank,
    COALESCE(rp.OwnerUserId, -99) AS SafeOwnerUserId,
    CASE WHEN rp.FavoriteCount > 10 THEN 'Popular' ELSE 'Regular' END AS PopularityIndicator,
    CHAR_LENGTH(rp.OwnerDisplayName) AS OwnerDisplayNameLength,
    'Processed_' || SUBSTRING(rp.OwnerDisplayName FROM 1 FOR 3) AS ProcessedDisplayName,
    rp.Score + rp.FavoriteCount * 5 AS WeightedScore,
    CASE
        WHEN rp.OwnerUserId IS NOT NULL AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = rp.OwnerUserId AND b.Name LIKE '%Gold%') THEN 'Has Gold Badge'
        WHEN rp.OwnerUserId IS NOT NULL AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = rp.OwnerUserId AND b.Name LIKE '%Silver%') THEN 'Has Silver Badge'
        ELSE 'No High Tier Badge'
    END AS UserBadgeStatus
FROM RankedPosts rp
LEFT JOIN TopUsers tu ON rp.OwnerUserId = tu.UserId
LEFT JOIN PostHistorySummary phs ON rp.PostId = phs.PostId
WHERE rp.PostTypeId = 1 AND rp.AnswerCount > 5 AND rp.Score > 100;