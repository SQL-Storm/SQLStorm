-- {"query": "7837.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1618} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COALESCE(SUM(p.Score), 0) as TotalScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as QuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as AnswerScore,
    COUNT(DISTINCT b.Id) as BadgesCount,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COUNT(DISTINCT c.Id) as CommentsCount,
    COUNT(DISTINCT v.Id) as VotesCount,
    STRING_AGG(DISTINCT t.TagName, ', ') as UserTags,
    AVG(CAST(p.Score AS FLOAT)) as AvgPostScore,
    MAX(p.CreationDate) as LatestPostDate,
    MIN(p.CreationDate) as FirstPostDate,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1 AND p2.Score > 0) as HighScoreQuestions,
    (SELECT AVG(p3.Score) FROM Posts p3 WHERE p3.OwnerUserId = u.Id AND p3.PostTypeId = 2) as AvgAnswerScore,
    (SELECT COUNT(DISTINCT ph.Id) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)) as EditCount,
    (SELECT COUNT(*) FROM Posts p4 WHERE p4.OwnerUserId = u.Id AND p4.PostTypeId = 1 AND p4.AcceptedAnswerId IS NOT NULL) as AcceptedAnswersCount,
    (SELECT COUNT(DISTINCT ph2.PostId) FROM PostHistory ph2 WHERE ph2.UserId = u.Id AND ph2.PostHistoryTypeId IN (10, 11, 12, 13)) as PostActivityCount,
    (SELECT COUNT(DISTINCT pl.Id) FROM PostLinks pl WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)) as LinkedPostsCount,
    (SELECT COUNT(DISTINCT pl2.RelatedPostId) FROM PostLinks pl2 WHERE pl2.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)) as LinkedToPostsCount,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND((CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS FLOAT) / CAST(COUNT(DISTINCT p.Id) AS FLOAT)) * 100, 2)
        ELSE 0 
    END as AnswerPercentage,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 THEN 
            ROUND((CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score > 0 THEN p.Id END) AS FLOAT) / CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS FLOAT)) * 100, 2)
        ELSE 0 
    END as HighScoreQuestionPercentage,
    CASE 
        WHEN COUNT(DISTINCT b.Id) > 0 THEN 
            DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC)
        ELSE 0 
    END as BadgeRank,
    ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC, COUNT(DISTINCT p.Id) DESC) as UserRank,
    RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
    NTH_VALUE(u.DisplayName, 1) OVER (ORDER BY u.Reputation DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as TopReputationUser,
    CASE 
        WHEN u.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 'Above Average'
        WHEN u.Reputation < (SELECT AVG(Reputation) FROM Users) THEN 'Below Average'
        ELSE 'Average'
    END as ReputationLevel,
    COALESCE(
        (SELECT TOP 1 t2.TagName 
         FROM Posts p5 
         JOIN Tags t2 ON p5.Tags LIKE '%' + t2.TagName + '%'
         WHERE p5.OwnerUserId = u.Id 
         GROUP BY t2.TagName 
         ORDER BY COUNT(*) DESC),
        'No Tags'
    ) as MostActiveTag,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Id) as PreviousUserReputation,
    LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Id) as NextUserReputation,
    NTILE(100) OVER (ORDER BY u.Reputation DESC) as ReputationPercentile,
    PERCENT_RANK() OVER (ORDER BY u.Reputation) as ReputationPercentileRank,
    SUM(p.Score) OVER (ORDER BY u.Reputation DESC ROWS UNBOUNDED PRECEDING) as CumulativeScore,
    COUNT(DISTINCT p.Id) OVER (ORDER BY u.Reputation DESC ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) as RecentUserPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CreationDate >= DATEADD(DAY, -30, GETDATE()) THEN p.Id END) as RecentQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CreationDate >= DATEADD(DAY, -30, GETDATE()) THEN p.Id END) as RecentAnswers,
    (SELECT COUNT(DISTINCT p6.Id) FROM Posts p6 WHERE p6.OwnerUserId = u.Id AND p6.CreationDate >= DATEADD(DAY, -7, GETDATE())) as WeeklyActivity
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId 
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN Tags t ON p.Tags LIKE '%' + t.TagName + '%' OR (p.Tags IS NULL AND t.TagName IS NOT NULL)
WHERE 
    u.Id > 0 
    AND (p.Id IS NULL OR p.CreationDate >= DATEADD(YEAR, -2, GETDATE()))
    AND U.Reputation >= (SELECT AVG(Reputation) FROM Users) * 0.5
    AND (u.Reputation > 100 OR (COUNT(DISTINCT b.Id) > 0 AND COUNT(DISTINCT p.Id) > 0))
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 0
    OR COUNT(DISTINCT b.Id) > 0
    OR COUNT(DISTINCT c.Id) > 0
    OR COUNT(DISTINCT v.Id) > 0
ORDER BY 
    COALESCE(SUM(p.Score), 0) DESC,
    COUNT(DISTINCT p.Id) DESC,
    u.Reputation DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;