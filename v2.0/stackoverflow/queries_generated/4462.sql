-- {"query": "4462.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1643} 

WITH PostEngagement AS (
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
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) + COALESCE(p.FavoriteCount, 0) AS TotalInteractions,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS RowNumByUser,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextScore,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank
    FROM Posts AS p
    LEFT JOIN PostTypes AS pt
        ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u
        ON p.OwnerUserId = u.Id
    WHERE p.OwnerUserId IS NOT NULL
      AND p.PostTypeId IN (1, 2)
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        MAX(u.LastAccessDate) AS LastAccessDate,
        AVG(CAST(strftime('%w', u.CreationDate) AS REAL)) AS AvgCreationDayOfWeek,
        CAST(SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS REAL) / COUNT(p.Id) AS ClosureRate
    FROM Users AS u
    LEFT JOIN PostHistory AS ph
        ON u.Id = ph.UserId
    LEFT JOIN Posts AS p
        ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    HAVING COUNT(DISTINCT ph.PostId) > 5 OR COUNT(p.Id) > 10
),
CommentWordCount AS (
    SELECT
        c.PostId,
        COUNT(CASE WHEN LOWER(c.Text) LIKE '%great%' THEN 1 END) AS GreatCount,
        COUNT(CASE WHEN LOWER(c.Text) LIKE '%thanks%' THEN 1 END) AS ThanksCount,
        AVG(LENGTH(c.Text)) AS AvgCommentLength
    FROM Comments AS c
    GROUP BY c.PostId
)
SELECT
    pe.PostId,
    pe.PostTypeName,
    pe.OwnerDisplayName,
    pe.PostCreationDate,
    pe.Score,
    pe.ViewCount,
    pe.TotalInteractions,
    pe.IsClosed,
    pe.ScoreRank,
    uas.Reputation AS OwnerReputation,
    uas.UserCreationDate,
    uas.PostHistoryCount,
    uas.EditCount,
    uas.CloseVoteRate,
    cwc.GreatCount,
    cwc.ThanksCount,
    COALESCE(cwc.AvgCommentLength, 0) AS AverageCommentLength,
    CASE
        WHEN pe.Score > 100 AND pe.AnswerCount > 5 THEN 'High Engagement Question'
        WHEN pe.Score < 0 AND pe.IsClosed = 1 THEN 'Closed Negative Score Post'
        WHEN uas.EditCount > 10 AND pe.PostTypeId = 1 THEN 'Prolific Editor Question'
        ELSE 'Standard Post'
    END AS PostCategory,
    CASE
        WHEN pe.OwnerUserId = (SELECT UserId FROM Users WHERE DisplayName = 'Community') THEN 'Community Owned'
        WHEN uas.Reputation > 50000 THEN 'High Reputation User'
        ELSE 'Regular User'
    END AS OwnerStatus,
    CASE
        WHEN pe.Score > pe.PreviousScore AND pe.Score > pe.NextScore THEN 'Score Increased Significantly'
        WHEN pe.Score < pe.PreviousScore AND pe.Score < pe.NextScore THEN 'Score Decreased Significantly'
        ELSE 'Score Stable'
    END AS ScoreTrend,
    CONCAT(pe.PostTypeName, ' - ', COALESCE(pe.OwnerDisplayName, 'Anonymous')) AS PostIdentifier
FROM PostEngagement AS pe
LEFT JOIN UserActivitySummary AS uas
    ON pe.OwnerUserId = uas.UserId
LEFT JOIN CommentWordCount AS cwc
    ON pe.PostId = cwc.PostId
WHERE pe.RowNumByUser <= 10
  AND uas.Reputation > 100
UNION
SELECT
    p.Id,
    pt.Name,
    p.OwnerDisplayName,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) + COALESCE(p.FavoriteCount, 0),
    CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END,
    DENSE_RANK() OVER (ORDER BY p.Score DESC),
    u.Reputation,
    u.CreationDate,
    COUNT(DISTINCT ph.PostId),
    SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5) THEN 1 ELSE 0 END),
    CAST(SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS REAL) / COUNT(p.Id),
    NULL,
    NULL,
    NULL,
    'Excluded Post',
    'Excluded Status',
    'Excluded Trend',
    CONCAT(pt.Name, ' - ', COALESCE(p.OwnerDisplayName, 'Anonymous'))
FROM Posts AS p
JOIN PostTypes AS pt
    ON p.PostTypeId = pt.Id
LEFT JOIN Users AS u
    ON p.OwnerUserId = u.Id
LEFT JOIN PostHistory AS ph
    ON u.Id = ph.UserId
WHERE p.OwnerUserId IS NULL OR u.Reputation <= 100 OR p.PostTypeId NOT IN (1, 2)
GROUP BY p.Id, pt.Name, p.OwnerDisplayName, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, u.Reputation, u.CreationDate
HAVING COUNT(DISTINCT ph.PostId) < 5 AND COUNT(p.Id) < 10;
