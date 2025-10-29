-- {"query": "7814.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1345} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT b.Id) as Badges,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) as AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) as AvgAnswerScore,
    MAX(p.CreationDate) as LatestPostDate,
    STRING_AGG(DISTINCT 
        CASE 
            WHEN p.PostTypeId = 1 AND p.Tags IS NOT NULL THEN 
                TRIM(BOTH '<>' FROM SPLIT_PART(p.Tags, '><', 1))
            ELSE NULL 
        END, ', ') as FirstTag,
    COUNT(DISTINCT CASE WHEN p.ViewCount > 1000 THEN p.Id END) as HighViewPosts,
    COUNT(DISTINCT CASE WHEN p.Score > 10 THEN p.Id END) as HighScorePosts,
    COUNT(DISTINCT CASE WHEN p.CommentCount > 10 THEN p.Id END) as ManyCommentPosts,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
    PERCENT_RANK() OVER (ORDER BY u.Reputation DESC) as ReputationPercentile,
    LAG(u.Reputation, 1) OVER (ORDER BY u.Reputation DESC) as PreviousReputation,
    LEAD(u.Reputation, 1) OVER (ORDER BY u.Reputation DESC) as NextReputation,
    NTILE(100) OVER (ORDER BY u.Reputation DESC) as ReputationQuartile,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.Score > 1000) THEN 'HighlyRanked'
        WHEN EXISTS (SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.Score > 100) THEN 'Moderate'
        ELSE 'Low'
    END as UserEngagementTier,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.UserId = u.Id 
         AND v.VoteTypeId IN (2,3)
         AND v.CreationDate > u.CreationDate),
        0
    ) as TotalVotes,
    COALESCE(
        (SELECT COUNT(*) 
         FROM PostHistory ph 
         WHERE ph.UserId = u.Id 
         AND ph.PostHistoryTypeId IN (4,5,6)
         AND ph.CreationDate > u.CreationDate),
        0
    ) as Edits,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.UserId = u.Id 
         AND c.CreationDate > u.CreationDate),
        0
    ) as Comments,
    COALESCE(
        (SELECT SUM(v.BountyAmount) 
         FROM Votes v 
         WHERE v.UserId = u.Id 
         AND v.VoteTypeId = 8),
        0
    ) as TotalBounties,
    EXISTS (
        SELECT 1 
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND p.CreationDate > u.CreationDate 
        AND p.Tags IS NOT NULL 
        AND LENGTH(p.Tags) > 100
    ) as HasLongTaggedPosts,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM Tags t 
            WHERE t.ExcerptPostId IN (
                SELECT Id FROM Posts WHERE OwnerUserId = u.Id
            )
        ) THEN 'HasTagExcerpts'
        ELSE 'NoTagExcerpts'
    END as TagExcerptStatus,
    COALESCE(
        (SELECT AVG(DATEDIFF('day', p.CreationDate, p.LastActivityDate)) 
         FROM Posts p 
         WHERE p.OwnerUserId = u.Id 
         AND p.CreationDate IS NOT NULL 
         AND p.LastActivityDate IS NOT NULL),
        0
    ) as AvgPostLifespan,
    LAG(COUNT(DISTINCT p.Id), 1, 0) OVER (ORDER BY u.CreationDate) as PreviousDayPosts,
    ROW_NUMBER() OVER (ORDER BY u.CreationDate) as SequentialUserNumber,
    u.CreationDate,
    u.LastAccessDate,
    EXTRACT(YEAR FROM CURRENT_DATE) - EXTRACT(YEAR FROM u.CreationDate) as YearsContributing
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Posts p2 ON p2.ParentId = p.Id AND p2.PostTypeId = 2
LEFT JOIN Votes v ON v.PostId = p.Id
LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.UserId = u.Id
LEFT JOIN Comments c ON c.PostId = p.Id AND c.UserId = u.Id
WHERE u.CreationDate >= '2008-01-01'::timestamp
AND u.Reputation >= 100
AND (
    p.PostTypeId IN (1,2) 
    OR p IS NULL 
    OR p.Id IS NULL
)
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    u.CreationDate, 
    u.LastAccessDate
HAVING 
    COUNT(DISTINCT p.Id) > 0
    AND COUNT(DISTINCT b.Id) >= 0
    AND (
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) >= 0
        OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) >= 0
    )
ORDER BY 
    CASE WHEN COUNT(DISTINCT p.Id) > 100 THEN 1 ELSE 2 END,
    u.Reputation DESC,
    u.CreationDate ASC
LIMIT 1000;