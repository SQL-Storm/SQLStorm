-- {"query": "4440.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1828}
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
        p.CommunityOwnedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RowNumPerType,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountForPost,
        AVG(p.Score) OVER (PARTITION BY p.PostTypeId) AS AvgScorePerType,
        SUM(p.ViewCount) OVER (PARTITION BY p.PostTypeId) AS TotalViewsPerType,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS NextPostScore,
        CASE
            WHEN p.Title LIKE '%[^a-zA-Z0-9 ]%' THEN 'Contains Special Chars'
            WHEN p.Title LIKE '%[a-z]%' THEN 'Has Lowercase'
            WHEN p.Title LIKE '%[A-Z]%' THEN 'Has Uppercase'
            ELSE 'Other Title Pattern'
        END AS TitlePattern,
        LENGTH(p.Body) AS BodyLength,
        COALESCE(p.FavoriteCount, 0) AS NonNullFavoriteCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosedFlag,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwnedFlag
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    WHERE p.CreationDate >= TIMESTAMP '2023-01-01' AND p.OwnerUserId IS NOT NULL
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount AS CommentCountFromWindow,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.CommunityOwnedDate,
    rp.RowNumPerType,
    rp.AvgScorePerType,
    rp.TotalViewsPerType,
    rp.PreviousPostScore,
    rp.NextPostScore,
    rp.TitlePattern,
    rp.BodyLength,
    rp.NonNullFavoriteCount,
    rp.IsClosedFlag,
    rp.IsCommunityOwnedFlag,
    CASE
        WHEN rp.Score > rp.AvgScorePerType * 1.5 AND rp.ViewCount > rp.TotalViewsPerType / 1000 THEN 'High Performing'
        WHEN rp.Score < rp.AvgScorePerType * 0.5 OR rp.ViewCount < rp.TotalViewsPerType / 10000 THEN 'Low Performing'
        ELSE 'Average Performing'
    END AS PerformanceTier,
    ph.PostHistoryTypeId,
    pht.Name AS PostHistoryTypeName,
    ph.CreationDate AS HistoryCreationDate,
    ph.UserId AS HistoryUserId,
    ph.UserDisplayName AS HistoryUserDisplayName,
    ph.Comment AS HistoryComment,
    lt.Name AS LinkTypeName,
    pl.RelatedPostId,
    (SELECT COUNT(*) FROM Votes AS v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 2) AS UpVoteCountForPost,
    (SELECT COUNT(*) FROM Votes AS v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 3) AS DownVoteCountForPost
FROM RankedPosts AS rp
LEFT JOIN PostHistory AS ph ON rp.PostId = ph.PostId AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 19, 20, 24, 33, 35, 36, 50, 52, 53, 66)
LEFT JOIN PostHistoryTypes AS pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN PostLinks AS pl ON rp.PostId = pl.PostId AND pl.LinkTypeId = 3
LEFT JOIN LinkTypes AS lt ON pl.LinkTypeId = lt.Id
WHERE rp.RowNumPerType <= 100
  AND rp.PostTypeName IN ('Question', 'Answer')
  AND rp.PostCreationDate >= (cast('2024-10-01' as date) - INTERVAL '365 day')
  AND (rp.OwnerDisplayName IS NULL OR LENGTH(rp.OwnerDisplayName) > 3)
  AND rp.BodyLength > 100
  AND rp.NonNullFavoriteCount > 0
  AND rp.PreviousPostScore <> rp.NextPostScore

UNION

SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount AS CommentCountFromWindow,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.CommunityOwnedDate,
    rp.RowNumPerType,
    rp.AvgScorePerType,
    rp.TotalViewsPerType,
    rp.PreviousPostScore,
    rp.NextPostScore,
    rp.TitlePattern,
    rp.BodyLength,
    rp.NonNullFavoriteCount,
    rp.IsClosedFlag,
    rp.IsCommunityOwnedFlag,
    CASE
        WHEN rp.Score > rp.AvgScorePerType * 1.5 AND rp.ViewCount > rp.TotalViewsPerType / 1000 THEN 'High Performing'
        WHEN rp.Score < rp.AvgScorePerType * 0.5 OR rp.ViewCount < rp.TotalViewsPerType / 10000 THEN 'Low Performing'
        ELSE 'Average Performing'
    END AS PerformanceTier,
    ph.PostHistoryTypeId,
    pht.Name AS PostHistoryTypeName,
    ph.CreationDate AS HistoryCreationDate,
    ph.UserId AS HistoryUserId,
    ph.UserDisplayName AS HistoryUserDisplayName,
    ph.Comment AS HistoryComment,
    lt.Name AS LinkTypeName,
    pl.RelatedPostId,
    (SELECT COUNT(*) FROM Votes AS v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 2) AS UpVoteCountForPost,
    (SELECT COUNT(*) FROM Votes AS v WHERE v.PostId = rp.PostId AND v.VoteTypeId = 3) AS DownVoteCountForPost
FROM RankedPosts AS rp
LEFT JOIN PostHistory AS ph ON rp.PostId = ph.PostId AND ph.PostHistoryTypeId IN (35, 36)
LEFT JOIN PostHistoryTypes AS pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN PostLinks AS pl ON rp.PostId = pl.RelatedPostId AND pl.LinkTypeId = 3
LEFT JOIN LinkTypes AS lt ON pl.LinkTypeId = lt.Id
WHERE rp.RowNumPerType <= 100
  AND rp.PostTypeName IN ('Question', 'Answer')
  AND rp.PostCreationDate >= (cast('2024-10-01' as date) - INTERVAL '365 day')
  AND rp.IsCommunityOwnedFlag = 1
  AND rp.Score < 0;