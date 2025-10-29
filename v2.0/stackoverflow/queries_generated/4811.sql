-- {"query": "4811.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1423} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        u.DisplayName AS EditorDisplayName,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ph.CreationDate AS EditDate,
        ph.Comment,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) -- Focus on edits and rollbacks
),
PostEditCounts AS (
    SELECT
        PostId,
        COUNT(DISTINCT CASE WHEN PostHistoryTypeId IN (4, 5, 6) THEN Id ELSE NULL END) AS EditCount,
        COUNT(DISTINCT CASE WHEN PostHistoryTypeId IN (7, 8, 9) THEN Id ELSE NULL END) AS RollbackCount,
        SUM(CASE WHEN rn = 1 THEN 1 ELSE 0 END) AS LatestEditFlag
    FROM RankedPostEdits
    GROUP BY PostId
),
UserContributionSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(u.Reputation) AS MaxReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
ComplexPostAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        DATEDIFF(day, p.CreationDate, p.ClosedDate) AS DaysToClose,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        COALESCE(pec.EditCount, 0) AS TotalEdits,
        COALESCE(pec.RollbackCount, 0) AS TotalRollbacks,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score < 0) AS NegativeScoreComments,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinks,
        p.Tags
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN PostEditCounts pec ON p.Id = pec.PostId
    WHERE p.Score > 10 AND p.CreationDate > '2023-01-01' AND p.CommentCount > 5
)
SELECT
    cpa.PostId,
    cpa.Title,
    cpa.PostTypeName,
    cpa.OwnerDisplayName,
    cpa.PostCreationDate,
    cpa.LastActivityDate,
    cpa.Score,
    cpa.AnswerCount,
    cpa.FavoriteCount,
    cpa.IsClosed,
    cpa.DaysToClose,
    cpa.TotalEdits,
    cpa.TotalRollbacks,
    cpa.NegativeScoreComments,
    cpa.DuplicateLinks,
    (
        SELECT STRING_AGG(TagName, ',') WITHIN GROUP (ORDER BY TagName)
        FROM (
            SELECT DISTINCT SUBSTRING(value, 2, LEN(value)-2) AS TagName
            FROM STRING_SPLIT(cpa.Tags, '><')
        ) AS SplitTags
    ) AS FormattedTags,
    ucs.TotalPostsOwned,
    ucs.QuestionCount,
    ucs.AnswerCount AS UserAnswerCount,
    ucs.BadgeCount,
    ucs.MaxReputation,
    CASE
        WHEN ucs.Reputation > 50000 THEN 'High Reputation'
        WHEN ucs.Reputation BETWEEN 10000 AND 50000 THEN 'Medium Reputation'
        ELSE 'Low Reputation'
    END AS ReputationLevel,
    COALESCE(AVG(cpa.Score) OVER (PARTITION BY cpa.PostTypeId), 0) AS AvgScoreForPostType,
    ROW_NUMBER() OVER (ORDER BY cpa.Score DESC, cpa.FavoriteCount DESC) AS RankByPopularity
FROM ComplexPostAnalysis cpa
JOIN UserContributionSummary ucs ON cpa.OwnerUserId = ucs.UserId
WHERE cpa.PostCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
UNION ALL
SELECT
    NULL,
    'Total Posts',
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    COUNT(DISTINCT cpa.PostId),
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM ComplexPostAnalysis cpa
WHERE cpa.PostCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
ORDER BY PostId NULLS FIRST, RankByPopularity;
