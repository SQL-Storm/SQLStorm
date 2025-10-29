-- {"query": "7008.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3877} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT c.Id) as Comments,
    COALESCE(SUM(p.Score), 0) as TotalScore,
    COALESCE(AVG(p.Score), 0) as AvgScore,
    MAX(p.CreationDate) as LastPostDate,
    COUNT(DISTINCT b.Id) as BadgesCount,
    STRING_AGG(DISTINCT b.Name, ', ') as BadgeNames,
    STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Title END, ' | ') as QuestionTitles,
    STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 2 THEN SUBSTRING(p.Body, 1, 100) END, ' | ') as AnswerSnippets,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 10 THEN p.Id END) as HighScoreAnswers,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.CreationDate > u.CreationDate + INTERVAL '1 year') as PostsAfterOneYear,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND((COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100.0 / COUNT(DISTINCT p.Id)), 2)
        ELSE 0 
    END as AnswerPercentage,
    ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) as RankByScore,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as RankByReputation,
    NTILE(10) OVER (ORDER BY u.Reputation DESC) as ReputationDecile,
    LAG(u.Reputation, 1) OVER (ORDER BY u.Reputation DESC) as PreviousReputation,
    LEAD(u.Reputation, 1) OVER (ORDER BY u.Reputation DESC) as NextReputation,
    FIRST_VALUE(u.Reputation) OVER (ORDER BY u.Reputation DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as MaxReputation,
    LAST_VALUE(u.Reputation) OVER (ORDER BY u.Reputation DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as MinReputation,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = u.Id 
     AND p3.CreationDate BETWEEN u.CreationDate AND u.CreationDate + INTERVAL '30 days') as PostsInFirstMonth,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND((COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) * 1.0 / COUNT(DISTINCT p.Id)), 2)
        ELSE 0 
    END as QuestionRatio,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId IN (2,3)) as VoteCount,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as QuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as AnswerScore,
    (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.UserId = u.Id) as EditCount,
    COALESCE(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END), 0) as AvgAnswerScore,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) as QuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommentCount > 0 THEN p.Id END) as QuestionWithComments,
    (SELECT COUNT(*) FROM Posts p4 WHERE p4.OwnerUserId = u.Id AND p4.ClosedDate IS NOT NULL) as ClosedQuestions,
    (SELECT COUNT(*) FROM Posts p5 WHERE p5.OwnerUserId = u.Id AND p5.CommunityOwnedDate IS NOT NULL) as CommunityOwnedPosts,
    (SELECT MIN(p6.CreationDate) FROM Posts p6 WHERE p6.OwnerUserId = u.Id) as FirstPostDate,
    (SELECT MAX(p7.CreationDate) FROM Posts p7 WHERE p7.OwnerUserId = u.Id) as LatestPostDate,
    ROUND(AVG(EXTRACT(DAY FROM (p8.LastEditDate - p8.CreationDate))), 2) as AvgEditDurationDays,
    CASE WHEN COUNT(DISTINCT b.Id) > 0 THEN 'Has Badges' ELSE 'No Badges' END as BadgeStatus,
    CASE 
        WHEN u.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 
            (u.Reputation - (SELECT AVG(Reputation) FROM Users))
        ELSE 0 
    END as RepAboveAvg,
    ROUND(COUNT(DISTINCT p.Id) * 1.0 / NULLIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END), 0), 2) as AnswersPerQuestion,
    (SELECT COUNT(*) FROM Posts p9 WHERE p9.OwnerUserId = u.Id AND p9.ViewCount >= 10000) as HighlyViewedPosts,
    CASE WHEN COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) > 0 THEN 'Gold' ELSE 'No Gold' END as HasGold,
    CASE WHEN COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) > 0 THEN 'Silver' ELSE 'No Silver' END as HasSilver,
    CASE WHEN COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) > 0 THEN 'Bronze' ELSE 'No Bronze' END as HasBronze,
    STRING_AGG(DISTINCT u.Location, ', ') as Locations,
    STRING_AGG(DISTINCT u.WebsiteUrl, ', ') as Websites,
    (SELECT COUNT(*) FROM PostHistory ph2 WHERE ph2.UserId = u.Id AND ph2.PostHistoryTypeId = 1) as TitleEdits,
    (SELECT COUNT(*) FROM PostHistory ph3 WHERE ph3.UserId = u.Id AND ph3.PostHistoryTypeId IN (5, 6, 8, 9)) as BodyTagEdits,
    (SELECT AVG(p10.Score) FROM Posts p10 WHERE p10.OwnerUserId = u.Id AND p10.PostTypeId = 1) as AvgQuestionScore,
    (SELECT AVG(p11.Score) FROM Posts p11 WHERE p11.OwnerUserId = u.Id AND p11.PostTypeId = 2) as AvgAnswerScore,
    (SELECT COUNT(*) FROM Comments c2 WHERE c2.UserId = u.Id AND c2.CreationDate > u.CreationDate + INTERVAL '1 day') as CommentsInFirstDay,
    (SELECT STRING_AGG(DISTINCT t.TagName, ', ') FROM Tags t 
     INNER JOIN Posts p12 ON p12.Tags LIKE '%' || t.TagName || '%' 
     WHERE p12.OwnerUserId = u.Id AND p12.PostTypeId = 1) as TaggedTopics,
    (SELECT COUNT(DISTINCT p13.Id) FROM Posts p13 
     WHERE p13.OwnerUserId = u.Id AND p13.PostTypeId = 1 
     AND EXISTS (SELECT 1 FROM Posts p14 WHERE p14.ParentId = p13.Id AND p14.Score > 10)) as QuestionsWithHighScoreAnswers
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON c.UserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN PostHistory ph ON ph.UserId = u.Id
LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
WHERE u.CreationDate > '2010-01-01'
GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
HAVING 
    COUNT(DISTINCT p.Id) > 0 
    AND 
    (
        (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0) 
        OR 
        (COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0)
    )
ORDER BY TotalScore DESC, u.Reputation DESC
LIMIT 100
EXCEPT
SELECT 
    u2.Id as UserId,
    u2.DisplayName,
    u2.Reputation,
    COUNT(DISTINCT p2.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p2.PostTypeId = 1 THEN p2.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p2.PostTypeId = 2 THEN p2.Id END) as Answers,
    COUNT(DISTINCT c2.Id) as Comments,
    COALESCE(SUM(p2.Score), 0) as TotalScore,
    COALESCE(AVG(p2.Score), 0) as AvgScore,
    MAX(p2.CreationDate) as LastPostDate,
    COUNT(DISTINCT b2.Id) as BadgesCount,
    STRING_AGG(DISTINCT b2.Name, ', ') as BadgeNames,
    STRING_AGG(DISTINCT CASE WHEN p2.PostTypeId = 1 THEN p2.Title END, ' | ') as QuestionTitles,
    STRING_AGG(DISTINCT CASE WHEN p2.PostTypeId = 2 THEN SUBSTRING(p2.Body, 1, 100) END, ' | ') as AnswerSnippets,
    COUNT(DISTINCT CASE WHEN p2.PostTypeId = 1 AND p2.ViewCount > 1000 THEN p2.Id END) as HighViewQuestions,
    COUNT(DISTINCT CASE WHEN p2.PostTypeId = 2 AND p2.Score > 10 THEN p2.Id END) as HighScoreAnswers,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = u2.Id AND p3.CreationDate > u2.CreationDate + INTERVAL '1 year') as PostsAfterOneYear,
    CASE 
        WHEN COUNT(DISTINCT p2.Id) > 0 THEN 
            ROUND((COUNT(DISTINCT CASE WHEN p2.PostTypeId = 2 THEN p2.Id END) * 100.0 / COUNT(DISTINCT p2.Id)), 2)
        ELSE 0 
    END as AnswerPercentage,
    ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p2.Score), 0) DESC) as RankByScore,
    DENSE_RANK() OVER (ORDER BY u2.Reputation DESC) as RankByReputation,
    NTILE(10) OVER (ORDER BY u2.Reputation DESC) as ReputationDecile,
    LAG(u2.Reputation, 1) OVER (ORDER BY u2.Reputation DESC) as PreviousReputation,
    LEAD(u2.Reputation, 1) OVER (ORDER BY u2.Reputation DESC) as NextReputation,
    FIRST_VALUE(u2.Reputation) OVER (ORDER BY u2.Reputation DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as MaxReputation,
    LAST_VALUE(u2.Reputation) OVER (ORDER BY u2.Reputation DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) as MinReputation,
    (SELECT COUNT(*) FROM Posts p4 WHERE p4.OwnerUserId = u2.Id 
     AND p4.CreationDate BETWEEN u2.CreationDate AND u2.CreationDate + INTERVAL '30 days') as PostsInFirstMonth,
    CASE 
        WHEN COUNT(DISTINCT p2.Id) > 0 THEN 
            ROUND((COUNT(DISTINCT CASE WHEN p2.PostTypeId = 1 THEN p2.Id END) * 1.0 / COUNT(DISTINCT p2.Id)), 2)
        ELSE 0 
    END as QuestionRatio,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u2.Id AND v.VoteTypeId IN (2,3)) as VoteCount,
    COALESCE(SUM(CASE WHEN p2.PostTypeId = 1 THEN p2.Score ELSE 0 END), 0) as QuestionScore,
    COALESCE(SUM(CASE WHEN p2.PostTypeId = 2 THEN p2.Score ELSE 0 END), 0) as AnswerScore,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u2.Id) as EditCount,
    COALESCE(AVG(CASE WHEN p2.PostTypeId = 2 THEN p2.Score END), 0) as AvgAnswerScore,
    COUNT(DISTINCT CASE WHEN p2.PostTypeId = 1 AND p2.AnswerCount > 0 THEN p2.Id END) as QuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN p2.PostTypeId = 1 AND p2.CommentCount > 0 THEN p2.Id END) as QuestionWithComments,
    (SELECT COUNT(*) FROM Posts p5 WHERE p5.OwnerUserId = u2.Id AND p5.ClosedDate IS NOT NULL) as ClosedQuestions,
    (SELECT COUNT(*) FROM Posts p6 WHERE p6.OwnerUserId = u2.Id AND p6.CommunityOwnedDate IS NOT NULL) as CommunityOwnedPosts,
    (SELECT MIN(p7.CreationDate) FROM Posts p7 WHERE p7.OwnerUserId = u2.Id) as FirstPostDate,
    (SELECT MAX(p8.CreationDate) FROM Posts p8 WHERE p8.OwnerUserId = u2.Id) as LatestPostDate,
    ROUND(AVG(EXTRACT(DAY FROM (p9.LastEditDate - p9.CreationDate))), 2) as AvgEditDurationDays,
    CASE WHEN COUNT(DISTINCT b2.Id) > 0 THEN 'Has Badges' ELSE 'No Badges' END as BadgeStatus,
    CASE 
        WHEN u2.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 
            (u2.Reputation - (SELECT AVG(Reputation) FROM Users))
        ELSE 0 
    END as RepAboveAvg,
    ROUND(COUNT(DISTINCT p2.Id) * 1.0 / NULLIF(COUNT(DISTINCT CASE WHEN p2.PostTypeId = 1 THEN p2.Id END), 0), 2) as AnswersPerQuestion,
    (SELECT COUNT(*) FROM Posts p10 WHERE p10.OwnerUserId = u2.Id AND p10.ViewCount >= 10000) as HighlyViewedPosts,
    CASE WHEN COUNT(DISTINCT CASE WHEN b2.Class = 1 THEN b2.Id END) > 0 THEN 'Gold' ELSE 'No Gold' END as HasGold,
    CASE WHEN COUNT(DISTINCT CASE WHEN b2.Class = 2 THEN b2.Id END) > 0 THEN 'Silver' ELSE 'No Silver' END as HasSilver,
    CASE WHEN COUNT(DISTINCT CASE WHEN b2.Class = 3 THEN b2.Id END) > 0 THEN 'Bronze' ELSE 'No Bronze' END as HasBronze,
    STRING_AGG(DISTINCT u2.Location, ', ') as Locations,
    STRING_AGG(DISTINCT u2.WebsiteUrl, ', ') as Websites,
    (SELECT COUNT(*) FROM PostHistory ph2 WHERE ph2.UserId = u2.Id AND ph2.PostHistoryTypeId = 1) as TitleEdits,
    (SELECT COUNT(*) FROM PostHistory ph3 WHERE ph3.UserId = u2.Id AND ph3.PostHistoryTypeId IN (5, 6, 8, 9)) as BodyTagEdits,
    (SELECT AVG(p11.Score) FROM Posts p11 WHERE p11.OwnerUserId = u2.Id AND p11.PostTypeId = 1) as AvgQuestionScore,
    (SELECT AVG(p12.Score) FROM Posts p12 WHERE p12.OwnerUserId = u2.Id AND p12.PostTypeId = 2) as AvgAnswerScore,
    (SELECT COUNT(*) FROM Comments c3 WHERE c3.UserId = u2.Id AND c3.CreationDate > u2.CreationDate + INTERVAL '1 day') as CommentsInFirstDay,
    (SELECT STRING_AGG(DISTINCT t2.TagName, ', ') FROM Tags t2 
     INNER JOIN Posts p13 ON p13.Tags LIKE '%' || t2.TagName || '%' 
     WHERE p13.OwnerUserId = u2.Id AND p13.PostTypeId = 1) as TaggedTopics,
    (SELECT COUNT(DISTINCT p14.Id) FROM Posts p14 
     WHERE p14.OwnerUserId = u2.Id AND p14.PostTypeId = 1 
     AND EXISTS (SELECT 1 FROM Posts p15 WHERE p15.ParentId = p14.Id AND p15.Score > 10)) as QuestionsWithHighScoreAnswers
FROM Users u2
LEFT JOIN Posts p2 ON p2.OwnerUserId = u2.Id
LEFT JOIN Comments c2 ON c2.UserId = u2.Id
LEFT JOIN Badges b2 ON b2.UserId = u2.Id
LEFT JOIN PostHistory ph ON ph.UserId = u2.Id
LEFT JOIN Tags t2 ON p2.Tags LIKE '%' || t2.TagName || '%'
WHERE u2.CreationDate > '2015-01-01' AND u2.Reputation < 500
GROUP BY u2.Id, u2.DisplayName, u2.Reputation, u2.CreationDate
HAVING 
    COUNT(DISTINCT p2.Id) > 0 
    AND 
    (
        (COUNT(DISTINCT CASE WHEN p2.PostTypeId = 1 THEN p2.Id END) > 0) 
        OR 
        (COUNT(DISTINCT CASE WHEN p2.PostTypeId = 2 THEN p2.Id END) > 0)
    )
ORDER BY TotalScore DESC, u2.Reputation DESC
LIMIT 100;