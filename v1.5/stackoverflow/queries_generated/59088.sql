-- {"query": "59088.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 1570} 
SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT bh.Id) AS HistoryCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        ELSE 'Other'
    END AS PostType,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answer Accepted'
        ELSE 'Open'
    END AS PostStatus,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
    MAX(v.CreationDate) AS LastVoteDate,
    MAX(c.CreationDate) AS LastCommentDate,
    MAX(bh.CreationDate) AS LastHistoryDate,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2, 3) THEN v.UserId END) AS UniqueVoters,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.UserId END) AS UniqueFavoriters,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (1, 4, 6) THEN bh.UserId END) AS Editors,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (10, 11, 12, 13) THEN bh.UserId END) AS Moderators,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId = 17 THEN bh.UserId END) AS Migrators,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId = 22 THEN bh.UserId END) AS Unmergers,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId = 24 THEN bh.UserId END) AS EditApprovers,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (33, 34) THEN bh.UserId END) AS NoticeHandlers,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS MovingAvgScore,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostRank,
    DENSE_RANK() OVER (ORDER BY p.Score DESC) AS GlobalScoreRank,
    CASE 
        WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Average'
        ELSE 'Below Average'
    END AS ScorePerformance,
    CASE 
        WHEN p.ViewCount > 1000 THEN 'High Traffic'
        WHEN p.ViewCount > 100 THEN 'Medium Traffic'
        WHEN p.ViewCount > 10 THEN 'Low Traffic'
        ELSE 'Very Low Traffic'
    END AS TrafficLevel,
    CASE 
        WHEN p.CreationDate >= '2020-01-01' AND p.CreationDate < '2021-01-01' THEN '2020'
        WHEN p.CreationDate >= '2021-01-01' AND p.CreationDate < '2022-01-01' THEN '2021'
        WHEN p.CreationDate >= '2022-01-01' AND p.CreationDate < '2023-01-01' THEN '2022'
        WHEN p.CreationDate >= '2023-01-01' AND p.CreationDate < '2024-01-01' THEN '2023'
        ELSE 'Other'
    END AS CreationYear,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (2, 5, 8) THEN bh.Id END) AS BodyEdits,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (3, 6, 9) THEN bh.Id END) AS TagEdits,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (10, 11) THEN bh.Id END) AS CloseReopenEvents,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (12, 13) THEN bh.Id END) AS DeleteUndeleteEvents,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (14, 15) THEN bh.Id END) AS LockUnlockEvents,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (19, 20) THEN bh.Id END) AS ProtectUnprotectEvents,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (25, 31, 35, 36) THEN bh.Id END) AS MigrationEvents,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId = 50 THEN bh.Id END) AS CommunityBumpEvents,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId IN (52, 53) THEN bh.Id END) AS HotQuestionEvents,
    COUNT(DISTINCT CASE WHEN bh.PostHistoryTypeId = 66 THEN bh.Id END) AS WizardCreatedEvents,
    COUNT(DISTINCT CASE WHEN pl.Id IS NOT NULL THEN pl.Id END) AS LinkedPostsCount,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.Id END) AS DuplicateLinksCount
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory bh ON p.Id = bh.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN (
    SELECT PostId, STRING_AGG(TagName, ', ') AS TagName
    FROM (
        SELECT p.Id AS PostId, unnest(string_to_array(trim(p.Tags, '<>'), '><')) AS TagName
        FROM Posts p
        WHERE p.Tags IS NOT NULL AND p.Tags != ''
    ) t
    GROUP BY PostId
) t ON p.Id = t.PostId
WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= '2020-01-01'
    AND p.CreationDate < '2024-01-01'
    AND (p.Score > 0 OR p.ViewCount > 10)
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, 
    u.DisplayName, u.Reputation, p.PostTypeId, 
    p.ClosedDate, p.CommunityOwnedDate, p.AcceptedAnswerId,
    p.AnswerCount, p.FavoriteCount
HAVING 
    COUNT(DISTINCT c.Id) >= 0
    AND COUNT(DISTINCT v.Id) >= 0
    AND COUNT(DISTINCT bh.Id) >= 0
ORDER BY 
    p.Score DESC NULLS LAST,
    p.ViewCount DESC NULLS LAST,
    p.CreationDate DESC
LIMIT 10000;