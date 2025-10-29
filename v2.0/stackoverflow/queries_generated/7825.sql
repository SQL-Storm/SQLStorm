-- {"query": "7825.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1812} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 10 THEN p.Id END) as HighScoreAnswers,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score END), 0) as TotalQuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score END), 0) as TotalAnswerScore,
    COUNT(DISTINCT b.Id) as BadgesCount,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COUNT(DISTINCT c.Id) as CommentsMade,
    COUNT(DISTINCT ph.Id) as PostHistoryActions,
    AVG(COALESCE(p.Score, 0)) as AvgPostScore,
    MAX(p.CreationDate) as LastPostDate,
    MAX(ph.CreationDate) as LastHistoryActionDate,
    (
        SELECT COUNT(*) 
        FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id 
        AND p2.PostTypeId = 1 
        AND p2.CreationDate > DATEADD(day, -30, GETDATE())
    ) as RecentQuestionsLast30Days,
    (
        SELECT AVG(CAST(DATEDIFF(day, p3.CreationDate, p3.LastActivityDate) AS FLOAT))
        FROM Posts p3
        WHERE p3.OwnerUserId = u.Id
        AND p3.PostTypeId = 1
    ) as AvgDaysToFirstActivity,
    (
        SELECT COUNT(*) 
        FROM Posts p4 
        WHERE p4.OwnerUserId = u.Id 
        AND p4.PostTypeId = 1 
        AND p4.AcceptedAnswerId IS NOT NULL
    ) as QuestionsWithAcceptedAnswer,
    (
        SELECT TOP 1 p5.Title 
        FROM Posts p5 
        WHERE p5.OwnerUserId = u.Id 
        AND p5.PostTypeId = 1 
        ORDER BY p5.CreationDate DESC
    ) as MostRecentQuestionTitle,
    (
        SELECT COUNT(*) 
        FROM Badges b2 
        WHERE b2.UserId = u.Id 
        AND b2.Date > DATEADD(month, -6, GETDATE())
    ) as RecentBadgesLast6Months,
    (
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) * 100.0 / NULLIF(COUNT(*), 0)
    ) as QuestionPercentage,
    CASE 
        WHEN u.Reputation >= 10000 THEN 'Elite'
        WHEN u.Reputation >= 1000 THEN 'Expert'
        WHEN u.Reputation >= 100 THEN 'Novice'
        ELSE 'Beginner'
    END as ReputationTier,
    (
        SELECT STRING_AGG(TagName, ', ')
        FROM Tags t1
        INNER JOIN (
            SELECT DISTINCT SUBSTRING(p6.Tags, 2, LEN(p6.Tags)-2) as TagsArray
            FROM Posts p6
            WHERE p6.OwnerUserId = u.Id AND p6.PostTypeId = 1
        ) t2 ON CHARINDEX('|' + t1.TagName + '|', '|' + t2.TagsArray + '|') > 0
        WHERE t1.TagName IS NOT NULL
    ) as UserTagsUsed,
    (
        SELECT COUNT(*) 
        FROM Posts p7 
        WHERE p7.ParentId = u.Id
    ) as AnswersAsParent,
    (
        SELECT COUNT(*) 
        FROM Posts p8 
        WHERE p8.OwnerUserId = u.Id 
        AND p8.CreationDate BETWEEN DATEADD(day, -7, GETDATE()) AND GETDATE()
    ) as RecentPostsLastWeek,
    ROW_NUMBER() OVER(ORDER BY u.Reputation DESC) as RankedByReputation,
    RANK() OVER(PARTITION BY CASE WHEN u.Reputation > 1000 THEN 1 ELSE 0 END ORDER BY u.Reputation DESC) as ReputationRankPartitioned,
    DENSE_RANK() OVER(ORDER BY u.Reputation DESC) as DenseReputationRank,
    (
        SELECT STRING_AGG(LOWER(vote_type.Name), ', ')
        FROM Votes v
        INNER JOIN VoteTypes vote_type ON v.VoteTypeId = vote_type.Id
        WHERE v.UserId = u.Id
    ) as VoteTypesUsed,
    NTILE(4) OVER(ORDER BY u.Reputation DESC) as ReputationQuartile,
    LAG(u.Reputation, 1, 0) OVER(ORDER BY u.Reputation DESC) as PreviousUserReputation,
    LEAD(u.Reputation, 1, 0) OVER(ORDER BY u.Reputation DESC) as NextUserReputation,
    (
        SELECT COUNT(*)
        FROM (
            SELECT p9.Id
            FROM Posts p9
            WHERE p9.OwnerUserId = u.Id
            GROUP BY p9.Id, p9.Score, p9.PostTypeId
            HAVING COUNT(*) > 1
        ) dups
    ) as DuplicatePosts,
    (
        SELECT COUNT(*) 
        FROM Posts p10 
        WHERE p10.OwnerUserId = u.Id 
        AND p10.PostTypeId = 1 
        AND p10.AnswerCount > 0
    ) as QuestionWithAnswers,
    (
        SELECT COUNT(*)
        FROM Posts p11
        WHERE p11.OwnerUserId = u.Id
        AND p11.PostTypeId = 1
        AND p11.ClosedDate IS NOT NULL
    ) as ClosedQuestions,
    (
        SELECT COUNT(*)
        FROM Posts p12
        WHERE p12.OwnerUserId = u.Id
        AND p12.PostTypeId = 2
        AND p12.Score = (
            SELECT MAX(p13.Score)
            FROM Posts p13
            WHERE p13.OwnerUserId = u.Id
            AND p13.PostTypeId = 2
        )
    ) as MaxScoreAnswers,
    (
        SELECT COUNT(*)
        FROM Posts p14
        WHERE p14.OwnerUserId = u.Id
        AND (
            LENGTH(p14.Title) > 50 
            OR LENGTH(p14.Body) > 2000
        )
    ) as LongPosts,
    (
        SELECT COUNT(*)
        FROM Comments c2
        WHERE c2.UserId = u.Id
        AND c2.CreationDate > DATEADD(month, -3, GETDATE())
    ) as RecentComments,
    (
        SELECT COUNT(*)
        FROM Badges b3
        WHERE b3.UserId = u.Id
        AND b3.Date > DATEADD(year, -1, GETDATE())
        AND b3.Class = 1
    ) as RecentGoldBadges,
    COALESCE(STRING_AGG(DISTINCT p15.Tags, '; '), 'No Tags') as UserPostTagsCombined
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN Posts p15 ON u.Id = p15.OwnerUserId AND p15.PostTypeId = 1
WHERE u.Id IN (
    SELECT DISTINCT u2.Id
    FROM Users u2
    INNER JOIN Posts p16 ON u2.Id = p16.OwnerUserId
    WHERE p16.CreationDate > DATEADD(year, -2, GETDATE())
    GROUP BY u2.Id
    HAVING COUNT(DISTINCT p16.Id) >= 50
)
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) >= 10
ORDER BY u.Reputation DESC, COUNT(DISTINCT p.Id) DESC
OFFSET 100 ROWS
FETCH NEXT 50 ROWS ONLY;