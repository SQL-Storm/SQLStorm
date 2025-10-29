-- {"query": "7252.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1771} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as QuestionsWithAcceptedAnswer,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) THEN p.Id END) as AnsweredWithUpvotes,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) as ClosedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) as QuestionsWithAnswers,
    AVG(CAST(p.Score AS FLOAT)) as AvgPostScore,
    MAX(p.ViewCount) as MaxViewCount,
    STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Title END, ' | ') as QuestionTitles,
    STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 2 THEN SUBSTRING(p.Body, 1, 100) END, ' | ') as AnswerSnippets,
    COUNT(DISTINCT b.Id) as BadgeCount,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COALESCE(NULLIF(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) / NULLIF(COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END), 0), 0), 0) as AvgQuestionViews,
    COALESCE(NULLIF(SUM(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END) / NULLIF(COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END), 0), 0), 0) as AvgAnswerViews,
    COUNT(DISTINCT CASE 
        WHEN p.PostTypeId = 1 AND p.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) 
        THEN p.Id 
    END) as HighViewQuestions,
    COUNT(DISTINCT CASE 
        WHEN p.PostTypeId = 2 AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) 
        THEN p.Id 
    END) as HighScoreAnswers,
    COUNT(DISTINCT CASE 
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) 
        THEN p.Id 
    END) as DuplicateQuestions,
    COUNT(DISTINCT CASE 
        WHEN EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id) 
        THEN p.Id 
    END) as CommentedPosts,
    COUNT(DISTINCT CASE 
        WHEN EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3)) 
        THEN p.Id 
    END) as VotedPosts,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
    ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC) as ScoreRank,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) as PrevUserReputation,
    LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) as NextUserReputation,
    NTILE(10) OVER (ORDER BY COUNT(DISTINCT p.Id)) as PostDecile,
    PERCENT_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id)) as PostPercentile,
    COUNT(DISTINCT p.Id) - 
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1) as NonQuestionPosts,
    CASE 
        WHEN COUNT(DISTINCT p.Id) = 0 THEN 'No Posts'
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 AND 
             COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) = 0 THEN 'Only Questions'
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) = 0 AND 
             COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0 THEN 'Only Answers'
        ELSE 'Both Questions and Answers'
    END as ContributionType,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.CreationDate END) as LastQuestionDate,
    MAX(CASE WHEN p.PostTypeId = 2 THEN p.CreationDate END) as LastAnswerDate,
    DATEDIFF('day', MIN(p.CreationDate), MAX(p.CreationDate)) as ActiveDays,
    COUNT(DISTINCT CASE WHEN p.CreationDate >= DATEADD('month', -6, CURRENT_TIMESTAMP) THEN p.Id END) as RecentPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CreationDate >= DATEADD('month', -6, CURRENT_TIMESTAMP) THEN p.Id END) as RecentQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CreationDate >= DATEADD('month', -6, CURRENT_TIMESTAMP) THEN p.Id END) as RecentAnswers,
    COUNT(DISTINCT CASE 
        WHEN (EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10) 
              OR EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 11)) 
        THEN p.Id 
    END) as ClosedOrReopened,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
        THEN (COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100.0) / NULLIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END), 0)
        ELSE 0
    END as AnswerToQuestionRatio,
    AVG(DATEDIFF('day', p.CreationDate, p.LastActivityDate)) as AvgDaysSinceCreation,
    STRING_AGG(
        CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Title END, 
        ' -> ' 
    ) WITHIN GROUP (ORDER BY p.CreationDate) as QuestionChain,
    CASE 
        WHEN COUNT(DISTINCT b.Id) > 0 THEN 
            STRING_AGG(b.Name, ', ') WITHIN GROUP (ORDER BY b.Date)
        ELSE NULL 
    END as BadgeList
FROM Users u
OUTER APPLY (
    SELECT p.* 
    FROM Posts p 
    WHERE p.OwnerUserId = u.Id
) p
LEFT JOIN Badges b ON b.UserId = u.Id
WHERE u.Reputation > 100
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 5
    AND COALESCE(NULLIF(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) / NULLIF(COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END), 0), 0), 0) > 100
    AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) >= 2
    AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) >= 1
    AND (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) >= 1 OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) >= 1)
ORDER BY TotalPosts DESC, ScoreRank ASC
LIMIT 500
OFFSET 100
;