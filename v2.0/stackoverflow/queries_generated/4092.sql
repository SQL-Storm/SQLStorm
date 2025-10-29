-- {"query": "4092.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1712} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        DATEDIFF(day, p.CreationDate, p.ClosedDate) AS DaysToClose,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_by_score_views,
        AVG(CAST(p.Score AS FLOAT)) OVER (PARTITION BY p.PostTypeId) AS avg_score_per_type,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate >= '2023-01-01'
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(CAST(p.Score AS FLOAT)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts AS p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY p.OwnerUserId
),
TopUsers AS (
    SELECT
        upa.OwnerUserId,
        upa.TotalPosts,
        upa.QuestionCount,
        upa.AnswerCount,
        upa.AvgPostScore,
        u.DisplayName AS TopUserDisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        DATEDIFF(day, u.CreationDate, GETDATE()) AS UserAgeInDays
    FROM UserPostActivity AS upa
    JOIN Users AS u ON upa.OwnerUserId = u.Id
    WHERE upa.TotalPosts > 1000
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS BodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS TitleEdits,
        MAX(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.CreationDate END) AS LastTitleEditDate,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15) THEN 1 ELSE 0 END) AS ModerationActions
    FROM PostHistory AS ph
    GROUP BY ph.PostId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.DaysToClose,
    rp.rn_by_score_views,
    rp.avg_score_per_type,
    rp.PreviousPostScore,
    tu.TopUserDisplayName,
    tu.Reputation,
    tu.UserAgeInDays,
    pht.BodyEdits,
    pht.TitleEdits,
    pht.ModerationActions,
    CASE
        WHEN rp.Score > rp.avg_score_per_type * 1.5 THEN 'Above Average Score'
        WHEN rp.Score < rp.avg_score_per_type * 0.5 THEN 'Below Average Score'
        ELSE 'Average Score'
    END AS ScoreCategory,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.CreationDate > DATEADD(day, -30, GETDATE()) AND rp.Score > 50 THEN 'Trending Question'
        ELSE 'Active'
    END AS PostStatus,
    IIF(tu.OwnerUserId IS NULL, 'Not a Top User', 'Is a Top User') AS UserTier,
    LEN(rp.OwnerDisplayName) AS OwnerNameLength,
    UPPER(SUBSTRING(rp.OwnerDisplayName, 1, 1)) AS OwnerInitial,
    COALESCE(rp.FavoriteCount, 0) AS SafeFavoriteCount,
    CASE
        WHEN rp.OwnerUserId = rp.PreviousPostScore THEN 'Self-Referential Score'
        WHEN rp.OwnerUserId IS NULL THEN 'Anonymous Owner'
        ELSE 'Standard Owner'
    END AS OwnerRelationship
FROM RankedPosts AS rp
LEFT JOIN PostHistorySummary AS pht ON rp.PostId = pht.PostId
LEFT JOIN TopUsers AS tu ON rp.OwnerUserId = tu.OwnerUserId
WHERE rp.Score > 10 AND rp.ViewCount > 100
UNION ALL
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.DaysToClose,
    rp.rn_by_score_views,
    rp.avg_score_per_type,
    rp.PreviousPostScore,
    tu.TopUserDisplayName,
    tu.Reputation,
    tu.UserAgeInDays,
    pht.BodyEdits,
    pht.TitleEdits,
    pht.ModerationActions,
    CASE
        WHEN rp.Score > rp.avg_score_per_type * 1.5 THEN 'Above Average Score'
        WHEN rp.Score < rp.avg_score_per_type * 0.5 THEN 'Below Average Score'
        ELSE 'Average Score'
    END AS ScoreCategory,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.CreationDate > DATEADD(day, -30, GETDATE()) AND rp.Score > 50 THEN 'Trending Question'
        ELSE 'Active'
    END AS PostStatus,
    IIF(tu.OwnerUserId IS NULL, 'Not a Top User', 'Is a Top User') AS UserTier,
    LEN(rp.OwnerDisplayName) AS OwnerNameLength,
    UPPER(SUBSTRING(rp.OwnerDisplayName, 1, 1)) AS OwnerInitial,
    COALESCE(rp.FavoriteCount, 0) AS SafeFavoriteCount,
    CASE
        WHEN rp.OwnerUserId = rp.PreviousPostScore THEN 'Self-Referential Score'
        WHEN rp.OwnerUserId IS NULL THEN 'Anonymous Owner'
        ELSE 'Standard Owner'
    END AS OwnerRelationship
FROM RankedPosts AS rp
JOIN PostLinks AS pl ON rp.PostId = pl.PostId
LEFT JOIN PostHistorySummary AS pht ON rp.PostId = pht.PostId
LEFT JOIN TopUsers AS tu ON rp.OwnerUserId = tu.OwnerUserId
WHERE pl.LinkTypeId = 3;
