-- {"query": "4115.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1184} 

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
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousPostScore,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS PostRankWithinType
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.OwnerUserId IS NOT NULL
      AND p.PostTypeId IN (1, 2) -- Questions and Answers
      AND p.CreationDate >= DATE_SUB(NOW(), INTERVAL 1 YEAR)
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (1, 4, 7) THEN 1 END) AS TitleEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (2, 5, 8) THEN 1 END) AS BodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (3, 6, 9) THEN 1 END) AS TagEdits,
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36) THEN ph.CreationDate END) AS LastStatusChangeDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AverageViewCount,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount AS PostAnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.PreviousPostScore,
    rp.PostRankWithinType,
    COALESCE(phs.TitleEdits, 0) AS TotalTitleEdits,
    COALESCE(phs.BodyEdits, 0) AS TotalBodyEdits,
    COALESCE(phs.TagEdits, 0) AS TotalTagEdits,
    phs.LastStatusChangeDate,
    upa.TotalPosts AS OwnerTotalPosts,
    upa.TotalScore AS OwnerTotalScore,
    upa.AverageViewCount AS OwnerAverageViewCount,
    CASE
        WHEN rp.Score > 100 AND rp.ViewCount > 10000 THEN 'High Impact'
        WHEN rp.Score < 0 THEN 'Negative Score'
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Regular'
    END AS PostStatusCategory,
    LOWER(SUBSTRING(rp.OwnerDisplayName FROM 1 FOR 1)) AS OwnerInitial,
    IIF(rp.FavoriteCount > 50, 'Popular', 'Standard') AS Popularity,
    rp.Score - rp.PreviousPostScore AS ScoreDifference,
    CASE
        WHEN rp.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId AND c.Score > 5)
        ELSE (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId AND c.Score < 0)
    END AS HighOrLowScoreComments,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3) THEN 'Is Duplicate Of'
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.RelatedPostId = rp.PostId AND pl.LinkTypeId = 3) THEN 'Has Duplicates'
        ELSE 'No Duplicate Links'
    END AS DuplicateStatus,
    CASE
        WHEN rp.OwnerUserId = (SELECT OwnerUserId FROM Users WHERE DisplayName = 'Community') THEN 'Community Owned'
        ELSE 'User Owned'
    END AS OwnershipType
FROM RankedPosts rp
LEFT JOIN PostHistorySummary phs ON rp.PostId = phs.PostId
LEFT JOIN UserPostActivity upa ON rp.OwnerUserId = upa.OwnerUserId
WHERE rp.PostRankWithinType <= 1000
ORDER BY rp.PostCreationDate DESC
LIMIT 500;
