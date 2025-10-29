-- {"query": "7282.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1702} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as AcceptedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.OwnerUserId = u.Id THEN p.Id END) as OwnedAnswers,
    COUNT(DISTINCT c.Id) as Comments,
    SUM(COALESCE(p.Score, 0)) as TotalScore,
    AVG(CAST(COALESCE(p.Score, 0) AS FLOAT)) as AvgScore,
    MAX(p.CreationDate) as LatestActivity,
    COUNT(DISTINCT b.Id) as Badges,
    STRING_AGG(DISTINCT b.Name, ', ') as BadgeTypes,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as PopularQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.ViewCount > 100 THEN p.Id END) as PopularAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) as QuestionWithAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN p.Id END) as QuestionWithoutAnswers,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1 AND CreationDate > '2022-01-01') as Questions2022,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2 AND CreationDate > '2022-01-01') as Answers2022,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1 AND Score > 100) as HighScoringQuestions,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2 AND Score > 10) as HighScoringAnswers,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(p.Id), 0), 0) as QuestionPercentage,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(p.Id), 0), 0) as AnswerPercentage,
    (SELECT AVG(CAST(Score AS FLOAT)) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1) as AvgQuestionScore,
    (SELECT AVG(CAST(Score AS FLOAT)) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2) as AvgAnswerScore,
    (SELECT COUNT(DISTINCT PostId) FROM Comments WHERE UserId = u.Id) as CommentedPosts,
    (SELECT COUNT(*) FROM Votes WHERE UserId = u.Id AND VoteTypeId IN (2,3) AND CreationDate > '2022-01-01') as RecentVotes,
    ROW_NUMBER() OVER (ORDER BY SUM(COALESCE(p.Score, 0)) DESC) as RankByScore,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as RankByPostCount,
    NTILE(10) OVER (ORDER BY SUM(COALESCE(p.Score, 0)) DESC) as ScoreDecile,
    LAG(u.Reputation, 1) OVER (ORDER BY u.Reputation DESC) as PrevUserReputation,
    LEAD(u.Reputation, 1) OVER (ORDER BY u.Reputation DESC) as NextUserReputation,
    FIRST_VALUE(u.DisplayName) OVER (ORDER BY u.Reputation DESC) as TopUser,
    LAG(COUNT(DISTINCT p.Id), 1) OVER (ORDER BY u.Reputation DESC) as PrevUserPostCount,
    CASE WHEN COUNT(DISTINCT p.Id) > 100 THEN 'High Activity' 
         WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Medium Activity' 
         ELSE 'Low Activity' END as ActivityLevel,
    COALESCE((SELECT COUNT(*) FROM Posts p2 JOIN Votes v ON p2.Id = v.PostId 
              WHERE p2.OwnerUserId = u.Id AND v.VoteTypeId = 2 AND v.CreationDate > '2023-01-01'), 0) as RecentUpvotes,
    COALESCE((SELECT COUNT(*) FROM Posts p2 
              WHERE p2.OwnerUserId = u.Id AND p2.ViewCount > 10000), 0) as ViralPosts,
    DATEDIFF('DAY', u.CreationDate, MAX(p.CreationDate)) as ActiveDays,
    ROUND(COUNT(DISTINCT p.Id) * 1.0 / NULLIF(DATEDIFF('DAY', u.CreationDate, GETDATE()), 0), 4) as PostsPerDay,
    (SELECT COUNT(DISTINCT postId) 
     FROM PostHistory ph 
     JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id 
     WHERE ph.UserId = u.Id AND pht.Name = 'Edit Title') as TitleEdits,
    (SELECT COUNT(DISTINCT postId) 
     FROM PostHistory ph 
     JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id 
     WHERE ph.UserId = u.Id AND pht.Name LIKE '%Edit%') as AllEdits,
    (SELECT COUNT(*) FROM Posts p3 
     JOIN PostLinks pl ON p3.Id = pl.PostId 
     WHERE p3.OwnerUserId = u.Id AND pl.LinkTypeId = 1) as LinkedPosts,
    (SELECT COUNT(*) FROM Posts p4 
     JOIN PostLinks pl2 ON p4.Id = pl2.PostId 
     WHERE p4.OwnerUserId = u.Id AND pl2.LinkTypeId = 3) as DuplicateLinks,
    (SELECT COUNT(*) FROM Posts p5 
     WHERE p5.OwnerUserId = u.Id AND p5.ClosedDate IS NOT NULL) as ClosedPosts,
    (SELECT COUNT(*) FROM Posts p6 
     WHERE p6.OwnerUserId = u.Id AND p6.CommunityOwnedDate IS NOT NULL) as CommunityOwnedPosts,
    (SELECT STRING_AGG(DISTINCT p7.TagName, ', ')
     FROM Posts p8 
     JOIN Tags p7 ON p8.Tags LIKE '%' + p7.TagName + '%' 
     WHERE p8.OwnerUserId = u.Id AND p8.PostTypeId = 1) as TagsUsed,
    CASE WHEN COUNT(DISTINCT p.Id) > 0 THEN 
        (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) * 100.0 / 
         NULLIF(COUNT(DISTINCT p.Id), 0)) 
    ELSE 0 END as QuestionRatio,
    (SELECT AVG(CAST(p9.Score AS FLOAT)) 
     FROM Posts p9 
     WHERE p9.OwnerUserId = u.Id 
     AND p9.PostTypeId IN (1,2)
     AND p9.CreationDate BETWEEN '2022-01-01' AND '2022-12-31') as AvgScore2022
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE u.Id BETWEEN 1 AND 10000
GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY SUM(COALESCE(p.Score, 0)) DESC
LIMIT 100;