-- {"query": "59016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 666} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as QuestionsWithAcceptedAnswers,
    COUNT(DISTINCT b.Id) as Badges,
    COUNT(DISTINCT v.Id) as Votes,
    COUNT(DISTINCT c.Id) as Comments,
    COUNT(DISTINCT ph.Id) as PostHistoryEntries,
    COUNT(DISTINCT pl.Id) as PostLinks,
    COUNT(DISTINCT CASE WHEN u.CreationDate >= '2023-01-01' THEN u.Id END) as NewUsersThisYear,
    AVG(CAST(p.Score AS FLOAT)) as AveragePostScore,
    MAX(p.ViewCount) as MaxViewCount,
    SUM(p.FavoriteCount) as TotalFavorites,
    COUNT(DISTINCT CASE WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN p.Id END) as TaggedPosts,
    COUNT(DISTINCT CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN p.Id END) as CommunityOwnedPosts,
    COUNT(DISTINCT CASE WHEN p.ClosedDate IS NOT NULL THEN p.Id END) as ClosedPosts,
    COUNT(DISTINCT CASE WHEN p.AnswerCount > 0 THEN p.Id END) as QuestionWithAnswers,
    COUNT(DISTINCT CASE WHEN p.CommentCount > 0 THEN p.Id END) as PostsWithComments,
    CONCAT('User_', u.Id) as UserIdentifier,
    DATE_PART('year', u.CreationDate) as UserCreationYear,
    DATE_PART('month', u.CreationDate) as UserCreationMonth,
    CASE 
        WHEN u.Reputation > 100000 THEN 'Elite'
        WHEN u.Reputation > 10000 THEN 'Expert'
        WHEN u.Reputation > 1000 THEN 'Advanced'
        WHEN u.Reputation > 100 THEN 'Intermediate'
        ELSE 'Beginner'
    END as ReputationLevel,
    STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTagsUsed
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.PostId
WHERE u.CreationDate >= '2020-01-01'
GROUP BY u.Id, u.DisplayName, u.Reputation, DATE_PART('year', u.CreationDate), DATE_PART('month', u.CreationDate)
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC
LIMIT 1000;