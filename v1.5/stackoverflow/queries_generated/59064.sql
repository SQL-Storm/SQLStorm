-- {"query": "59064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 1505} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerName,
    u.Reputation,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
        WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
        WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
    END as PostType,
    COALESCE(p.AnswerCount, 0) as AnswerCount,
    COALESCE(p.CommentCount, 0) as CommentCount,
    COALESCE(p.FavoriteCount, 0) as FavoriteCount,
    CONCAT('https://stackoverflow.com/questions/', p.Id) as PostUrl,
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
    STRING_AGG(DISTINCT b.Name, ', ') as Badges,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT v.Id) as VoteCount,
    COUNT(DISTINCT ph.Id) as HistoryCount,
    COUNT(DISTINCT pl.Id) as LinkCount,
    MAX(ph.CreationDate) as LastHistoryDate,
    MAX(v.CreationDate) as LastVoteDate,
    MAX(c.CreationDate) as LastCommentDate,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answer Accepted'
        ELSE 'Open'
    END as PostStatus,
    DATEDIFF(DAY, p.CreationDate, GETDATE()) as AgeInDays,
    CASE 
        WHEN p.Score >= 100 THEN 'Gold'
        WHEN p.Score >= 50 THEN 'Silver'
        WHEN p.Score >= 10 THEN 'Bronze'
        ELSE 'None'
    END as ScoreCategory,
    CONCAT('https://stackoverflow.com/users/', u.Id) as UserUrl,
    COALESCE(u.Views, 0) as UserViews,
    COALESCE(u.UpVotes, 0) as UserUpVotes,
    COALESCE(u.DownVotes, 0) as UserDownVotes,
    CASE 
        WHEN p.Score > 0 AND p.ViewCount > 0 THEN CAST(p.Score AS FLOAT) / CAST(p.ViewCount AS FLOAT)
        ELSE 0
    END as ScoreToViewRatio,
    STRING_AGG(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN 'UpVote' WHEN v.VoteTypeId = 3 THEN 'DownVote' END, ', ') as VoteTypes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as UpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as DownVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) as FavoriteVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 8 THEN v.Id END) as BountyStartVotes,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN ph.Id END) as StatusChangeEvents,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN ph.Id END) as EditEvents,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (14, 15, 19, 20) THEN ph.Id END) as ModerationEvents,
    COUNT(DISTINCT CASE WHEN p.Tags IS NOT NULL AND LEN(p.Tags) > 2 THEN 1 END) as HasTags,
    CASE 
        WHEN LEN(p.Body) > 1000 THEN 'Long'
        WHEN LEN(p.Body) > 500 THEN 'Medium'
        WHEN LEN(p.Body) > 100 THEN 'Short'
        ELSE 'Very Short'
    END as BodyLengthCategory,
    ROUND(AVG(CAST(p.Score AS FLOAT)), 2) as AvgScore,
    MAX(p.Score) as MaxScore,
    MIN(p.Score) as MinScore,
    COUNT(*) over() as TotalPosts
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN (
    SELECT Id, TagName 
    FROM Tags 
    WHERE TagName IN (
        SELECT DISTINCT TRIM(SUBSTRING(p.Tags, n.number + 1, CHARINDEX('><', p.Tags, n.number + 1) - n.number - 1)) 
        FROM Posts p 
        CROSS JOIN (
            SELECT 0 as number UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL 
            SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL 
            SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL 
            SELECT 9 UNION ALL SELECT 10 UNION ALL SELECT 11 UNION ALL 
            SELECT 12 UNION ALL SELECT 13 UNION ALL SELECT 14 UNION ALL 
            SELECT 15 UNION ALL SELECT 16 UNION ALL SELECT 17 UNION ALL 
            SELECT 18 UNION ALL SELECT 19 UNION ALL SELECT 20
        ) n
        WHERE p.Tags IS NOT NULL AND p.Tags LIKE '%><%'
        AND n.number < (LEN(p.Tags) - 1)
        AND SUBSTRING(p.Tags, n.number, 1) = '<'
    )
) t ON 1=1
WHERE p.PostTypeId IN (1, 2) 
    AND p.CreationDate >= DATEADD(YEAR, -1, GETDATE())
    AND (p.Score > 0 OR p.ViewCount > 0)
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, 
    u.DisplayName, u.Reputation, p.PostTypeId, p.AnswerCount, 
    p.CommentCount, p.FavoriteCount, 
    p.ClosedDate, p.CommunityOwnedDate, 
    p.AcceptedAnswerId, p.Tags, p.Body, u.Id, u.Views, u.UpVotes, u.DownVotes
HAVING 
    COUNT(DISTINCT v.Id) > 0
    OR COUNT(DISTINCT c.Id) > 0
    OR COUNT(DISTINCT ph.Id) > 0
ORDER BY 
    p.Score DESC, 
    p.ViewCount DESC,
    p.CreationDate DESC
LIMIT 10000;