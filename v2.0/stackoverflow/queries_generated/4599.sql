-- {"query": "4599.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 907} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) as rn
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.Title IS NOT NULL AND LENGTH(p.Title) > 10
),
PostComments AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
HighReputationUsers AS (
    SELECT Id
    FROM Users
    WHERE Reputation > 10000
),
PostHistoryWithCounts AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS BodyEditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS TitleEditCount
    FROM PostHistory ph
    WHERE ph.UserId IN (SELECT Id FROM HighReputationUsers)
    GROUP BY ph.PostId
),
PostLinkSummary AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS NumberOfLinkedPosts,
        SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinkCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
)
SELECT
    rp.PostId,
    rp.Title,
    pt.Name AS PostTypeName,
    rp.OwnerDisplayName,
    rp.CreationDate,
    COALESCE(pc.CommentCount, 0) AS TotalComments,
    COALESCE(pc.AvgCommentScore, 0.0) AS AverageCommentScore,
    CASE
        WHEN pc.LastCommentDate IS NULL THEN 'Never Commented'
        WHEN JULIANDAY('now') - JULIANDAY(pc.LastCommentDate) < 7 THEN 'Recent'
        ELSE 'Old'
    END AS CommentActivity,
    COALESCE(phc.BodyEditCount, 0) AS HighReputationBodyEdits,
    COALESCE(phc.TitleEditCount, 0) AS HighReputationTitleEdits,
    COALESCE(pls.NumberOfLinkedPosts, 0) AS TotalLinkedPosts,
    COALESCE(pls.DuplicateLinkCount, 0) AS TotalDuplicateLinks,
    CASE
        WHEN rp.rn <= 5 THEN 'Top 5 Recent Post'
        WHEN rp.rn > 5 AND rp.rn <= 20 THEN 'Next 15 Recent Post'
        ELSE 'Older Post'
    END AS PostRankByType,
    CASE
        WHEN rp.OwnerUserId IN (SELECT Id FROM HighReputationUsers) THEN 'High Rep User'
        ELSE 'Standard User'
    END AS OwnerReputationStatus,
    LENGTH(rp.Title) AS TitleLength,
    UPPER(SUBSTR(rp.Title, 1, 1)) || SUBSTR(rp.Title, 2) AS FormattedTitle -- Capitalize first letter
FROM RankedPosts rp
JOIN PostTypes pt ON rp.PostTypeId = pt.Id
LEFT JOIN PostComments pc ON rp.PostId = pc.PostId
LEFT JOIN PostHistoryWithCounts phc ON rp.PostId = phc.PostId
LEFT JOIN PostLinkSummary pls ON rp.PostId = pls.PostId
WHERE rp.PostTypeId IN (1, 2) -- Questions and Answers
AND rp.Title LIKE '%performance%' OR rp.Title LIKE '%benchmark%'
ORDER BY rp.CreationDate DESC
LIMIT 100;
