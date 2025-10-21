-- {"query": "59077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 705} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerName,
    u.Reputation,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT v.Id) as VoteCount,
    COUNT(DISTINCT ph.Id) as HistoryCount,
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
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
    COALESCE(p.FavoriteCount, 0) as FavoriteCount,
    COALESCE(p.CommentCount, 0) as ActualCommentCount,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answer Accepted'
        ELSE 'Open'
    END as PostStatus,
    DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) as AgeInDays,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2,3) THEN v.UserId END) as UniqueVoters,
    AVG(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as UpvoteRatio,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2 AND p2.DeletedDate IS NULL) as ActiveAnswers
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN (
    SELECT PostId, UNNEST(string_to_array(Tags, '><')) as TagName
    FROM Posts
    WHERE Tags IS NOT NULL AND Tags != ''
) t ON p.Id = t.PostId
WHERE p.CreationDate >= DATEADD('year', -1, CURRENT_TIMESTAMP)
    AND p.PostTypeId IN (1, 2)
    AND p.Score >= 0
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, 
    u.DisplayName, u.Reputation, p.PostTypeId, 
    p.AnswerCount, p.FavoriteCount, p.CommentCount,
    p.ClosedDate, p.CommunityOwnedDate, p.AcceptedAnswerId
HAVING 
    COUNT(DISTINCT c.Id) >= 5
    AND COUNT(DISTINCT v.Id) >= 10
    AND COUNT(DISTINCT ph.Id) >= 3
ORDER BY 
    p.Score DESC,
    p.ViewCount DESC,
    p.CreationDate DESC
LIMIT 1000;