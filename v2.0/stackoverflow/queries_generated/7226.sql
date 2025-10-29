-- {"query": "7226.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1398} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as QuestionsWithAcceptedAnswers,
    COUNT(DISTINCT b.Id) as BadgesReceived,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COALESCE(SUM(p.Score), 0) as TotalScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as QuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as AnswerScore,
    AVG(CAST(p.Score AS FLOAT)) as AveragePostScore,
    MAX(p.CreationDate) as LatestPostDate,
    MIN(p.CreationDate) as FirstPostDate,
    DATEDIFF(day, MIN(p.CreationDate), MAX(p.CreationDate)) as DaysActive,
    COUNT(DISTINCT c.Id) as CommentsMade,
    COUNT(DISTINCT ph.Id) as PostHistoryActions,
    COUNT(DISTINCT pl.Id) as LinkedPosts,
    STRING_AGG(DISTINCT t.TagName, ', ') as TagsUsed,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighlyViewedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 10 THEN p.Id END) as QuestionsWithManyAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommentCount > 5 THEN p.Id END) as QuestionsWithManyComments,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END), 0) as TotalQuestionViews,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END), 0) as TotalAnswerViews,
    RANK() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) as ScoreRank,
    ROW_NUMBER() OVER (ORDER BY u.CreationDate ASC) as SeniorityRank,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate ASC) as PreviousUserReputation,
    CASE 
        WHEN u.Reputation > 10000 THEN 'Elite'
        WHEN u.Reputation > 5000 THEN 'Veteran'
        WHEN u.Reputation > 1000 THEN 'Experienced'
        ELSE 'Newbie'
    END as ReputationTier,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 1000 THEN 'Legendary'
        WHEN COUNT(DISTINCT p.Id) > 500 THEN 'Master'
        WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Expert'
        ELSE 'Regular'
    END as PostingLevel,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1 AND ParentId IS NULL AND CreationDate > DATEADD(year, -1, GETDATE())) as RecentQuestions,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2 AND CreationDate > DATEADD(year, -1, GETDATE())) as RecentAnswers,
    (SELECT STRING_AGG(Name, ', ') FROM Badges WHERE UserId = u.Id AND Date > DATEADD(year, -2, GETDATE())) as RecentBadges,
    AVG(CAST((SELECT COUNT(*) FROM Comments WHERE UserId = u.Id AND CreationDate > DATEADD(month, -6, GETDATE())) AS FLOAT)) OVER (ORDER BY u.Id ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as MovingAverageComments,
    (SELECT MAX(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) as HighestQuestionScore,
    (SELECT MAX(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) as HighestAnswerScore,
    COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15) THEN 1 ELSE 0 END), 0) as ModerationActions,
    COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId IN (35, 36) THEN 1 ELSE 0 END), 0) as MigrationActions,
    (SELECT COUNT(*) FROM Votes v INNER JOIN Posts p ON v.PostId = p.Id WHERE v.UserId = u.Id AND v.VoteTypeId = 2) as UpVotes,
    (SELECT COUNT(*) FROM Votes v INNER JOIN Posts p ON v.PostId = p.Id WHERE v.UserId = u.Id AND v.VoteTypeId = 3) as DownVotes
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.PostId
LEFT JOIN (
    SELECT DISTINCT PostId, TagName 
    FROM Posts p
    CROSS APPLY STRING_SPLIT(REPLACE(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' ', ''), '>')
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
) t ON p.Id = t.PostId
WHERE u.CreationDate > '2010-01-01'
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    u.CreationDate
HAVING 
    COUNT(DISTINCT p.Id) > 0 
    AND (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
         OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0)
ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC
LIMIT 1000;