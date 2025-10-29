-- {"query": "7043.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1878} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score > 10 THEN p.Id END) AS HighScoringQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 5 THEN p.Id END) AS HighScoringAnswers,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) / NULLIF(COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END), 0), 0) AS AvgQuestionViews,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END) / NULLIF(COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END), 0), 0) AS AvgAnswerViews,
    COUNT(DISTINCT b.Id) AS BadgesReceived,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
    MAX(b.Date) AS LastBadgeDate,
    COUNT(DISTINCT c.Id) AS CommentsMade,
    COUNT(DISTINCT v.Id) AS VotesGiven,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2, 3) THEN v.Id END) AS VoteActivity,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS Upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS Downvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS Bookmarks,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 8 THEN v.Id END) AS BountyStarts,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 9 THEN v.Id END) AS BountyCloses,
    (SELECT COUNT(*) 
     FROM Posts p2 
     WHERE p2.OwnerUserId = u.Id 
     AND p2.PostTypeId = 1 
     AND p2.CreationDate >= DATEADD(MONTH, -6, GETDATE())) AS RecentQuestions,
    (SELECT COUNT(*) 
     FROM Posts p2 
     WHERE p2.OwnerUserId = u.Id 
     AND p2.PostTypeId = 2 
     AND p2.CreationDate >= DATEADD(MONTH, -6, GETDATE())) AS RecentAnswers,
    (SELECT COUNT(DISTINCT ph.PostId)
     FROM PostHistory ph
     WHERE ph.UserId = u.Id 
     AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
     AND ph.CreationDate >= DATEADD(DAY, -30, GETDATE())) AS RecentEdits,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS QuestionScoreTotal,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS AnswerScoreTotal,
    COALESCE(AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END), 0) AS AvgQuestionScore,
    COALESCE(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END), 0) AS AvgAnswerScore,
    STRING_AGG(CASE WHEN b.Class = 1 THEN b.Name END, ', ') WITHIN GROUP (ORDER BY b.Date) AS GoldBadgeNames,
    STRING_AGG(CASE WHEN b.Class = 2 THEN b.Name END, ', ') WITHIN GROUP (ORDER BY b.Date) AS SilverBadgeNames,
    STRING_AGG(CASE WHEN b.Class = 3 THEN b.Name END, ', ') WITHIN GROUP (ORDER BY b.Date) AS BronzeBadgeNames,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND(CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS FLOAT) * 100 / NULLIF(COUNT(DISTINCT p.Id), 0), 2)
        ELSE 0 
    END AS AnswerPercentage,
    ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) DESC) AS QuestionScoreRank,
    ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) DESC) AS AnswerScoreRank,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
    RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) AS BadgeCountRank,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS PreviousReputation,
    LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS NextReputation,
    PERCENT_RANK() OVER (ORDER BY u.Reputation) AS ReputationPercentile,
    NTILE(100) OVER (ORDER BY u.Reputation) AS ReputationQuintile,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM Posts p3 
            INNER JOIN Votes v2 ON v2.PostId = p3.Id 
            WHERE p3.OwnerUserId = u.Id 
            AND v2.VoteTypeId = 2 
            AND v2.CreationDate >= DATEADD(DAY, -7, GETDATE())
        ) THEN 'Active in Last Week' 
        ELSE 'Inactive' 
    END AS RecentActivityIndicator,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CreationDate >= DATEADD(MONTH, -1, GETDATE()) THEN p.Id END) > 0 
        THEN 'Monthly Question Poster' 
        ELSE 'Not Monthly Question Poster' 
    END AS MonthlyQuestionPoster,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CreationDate >= DATEADD(MONTH, -1, GETDATE()) THEN p.Id END) > 0 
        THEN 'Monthly Answer Poster' 
        ELSE 'Not Monthly Answer Poster' 
    END AS MonthlyAnswerPoster,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 1000 AND u.Reputation > 100000 
        THEN 'Elite' 
        WHEN COUNT(DISTINCT p.Id) > 500 AND u.Reputation > 50000 
        THEN 'Veteran' 
        WHEN COUNT(DISTINCT p.Id) > 100 AND u.Reputation > 10000 
        THEN 'Experienced' 
        ELSE 'Regular' 
    END AS UserTier,
    (SELECT COUNT(*) FROM Posts p4 WHERE p4.OwnerUserId = u.Id AND p4.PostTypeId = 1 AND p4.AnswerCount > 0) / NULLIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END), 0) AS AvgAnswersPerQuestion,
    ROUND(AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END), 2) AS AvgQuestionScoreRounded,
    CAST(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS FLOAT) / NULLIF(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS AvgQuestionViewsFloat
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
WHERE u.Id IS NOT NULL
  AND u.Reputation >= 100
  AND u.CreationDate <= DATEADD(YEAR, -1, GETDATE())
  AND (p.Id IS NULL OR p.PostTypeId IN (1, 2))
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) >= 1
   AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) >= 1
   AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) >= 0
ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC
OFFSET 0 ROWS FETCH NEXT 1000 ROWS ONLY;