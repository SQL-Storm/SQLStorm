-- {"query": "7048.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1393} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) AS HighViewQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 10 THEN p.Id END) AS HighScoreAnswers,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS TotalQuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS TotalAnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadgeCount,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadgeCount,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadgeCount,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS Upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS Downvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS FavoriteCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswer,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) AS QuestionsWithAnswers,
    (SELECT COUNT(*) FROM Posts p2 
     WHERE p2.OwnerUserId = u.Id 
     AND p2.PostTypeId = 1 
     AND p2.CreationDate > u.CreationDate 
     AND p2.CreationDate < DATEADD(DAY, 30, u.CreationDate)) AS NewQuestionsInFirstMonth,
    (SELECT COUNT(*) FROM Posts p3 
     WHERE p3.OwnerUserId = u.Id 
     AND p3.PostTypeId = 2 
     AND p3.CreationDate > u.CreationDate 
     AND p3.CreationDate < DATEADD(DAY, 30, u.CreationDate)) AS NewAnswersInFirstMonth,
    (SELECT COUNT(DISTINCT ph.PostId) 
     FROM PostHistory ph 
     WHERE ph.UserId = u.Id 
     AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
     AND ph.CreationDate > u.CreationDate) AS EditCount,
    (SELECT COUNT(DISTINCT pl.Id) 
     FROM PostLinks pl 
     WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1)
     AND pl.LinkTypeId = 1) AS LinkedQuestions,
    (SELECT COUNT(DISTINCT pl.Id) 
     FROM PostLinks pl 
     WHERE pl.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1)
     AND pl.LinkTypeId = 3) AS DuplicateQuestions,
    (SELECT COUNT(DISTINCT p4.Id) 
     FROM Posts p4 
     WHERE p4.OwnerUserId = u.Id 
     AND p4.PostTypeId = 1 
     AND p4.ClosedDate IS NOT NULL) AS ClosedQuestions,
    (SELECT COUNT(DISTINCT p5.Id) 
     FROM Posts p5 
     WHERE p5.OwnerUserId = u.Id 
     AND p5.PostTypeId = 1 
     AND p5.CommunityOwnedDate IS NOT NULL) AS CommunityOwnedQuestions,
    (SELECT STRING_AGG(t.TagName, ', ') 
     FROM Posts p6 
     JOIN STRING_SPLIT(p6.Tags, '<>') AS t ON 1=1 
     WHERE p6.OwnerUserId = u.Id AND p6.PostTypeId = 1
     GROUP BY u.Id) AS FavoriteTags,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 100 THEN 'High Activity'
        WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Medium Activity'
        WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Low Activity'
        ELSE 'Very Low Activity'
    END AS ActivityLevel,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS UserRankByPostCount,
    ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) DESC) AS UserRankByQuestionScore,
    PERCENT_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id)) AS PostCountPercentile,
    NTILE(10) OVER (ORDER BY COUNT(DISTINCT p.Id)) AS PostCountDecile,
    LAG(COUNT(DISTINCT p.Id), 1, 0) OVER (ORDER BY u.Reputation DESC) AS PreviousUserPostCount,
    LEAD(COUNT(DISTINCT p.Id), 1, 0) OVER (ORDER BY u.Reputation DESC) AS NextUserPostCount,
    AVG(COUNT(DISTINCT p.Id)) OVER (ORDER BY u.Reputation ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS MovingAvgPostCount
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
WHERE u.Reputation > 100
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0
AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) >= 1
ORDER BY COUNT(DISTINCT p.Id) DESC, u.Reputation DESC
OFFSET 100 ROWS
FETCH NEXT 100 ROWS ONLY