-- {"query": "7202.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2480} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as AvgAnswerScore,
    MAX(p.CreationDate) as LastPostDate,
    COUNT(DISTINCT b.Id) as BadgeCount,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    STRING_AGG(DISTINCT t.TagName, ', ') as TagPreferences,
    COUNT(DISTINCT c.Id) as CommentCount,
    STRING_AGG(DISTINCT pv.Name, ', ') as VoteTypes,
    COUNT(DISTINCT ph.Id) as HistoryActions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN ph.Id END) as ClosedReopenedDeleted,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (14, 15) THEN ph.Id END) as LockedUnlocked,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate) as PreviousReputation,
    LAG(u.CreationDate, 1) OVER (ORDER BY u.CreationDate) as PreviousCreationDate,
    DATEDIFF(day, LAG(u.CreationDate, 1) OVER (ORDER BY u.CreationDate), u.CreationDate) as DaysSincePreviousJoin,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) * 100.0 / COUNT(DISTINCT p.Id))
        ELSE 0 
    END as QuestionPercentage,
    RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
    NTILE(10) OVER (ORDER BY u.Reputation DESC) as ReputationDecile,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM Posts p2 
            WHERE p2.OwnerUserId = u.Id 
            AND p2.PostTypeId = 1 
            AND p2.Score > 1000
        ) THEN 'HighImpactQuestionAuthor'
        WHEN EXISTS (
            SELECT 1 FROM Posts p3 
            WHERE p3.OwnerUserId = u.Id 
            AND p3.PostTypeId = 2 
            AND p3.Score > 1000
        ) THEN 'HighImpactAnswerAuthor'
        ELSE 'RegularUser'
    END as ExpertiseLevel,
    COALESCE(
        (SELECT TOP 1 t1.TagName 
         FROM Posts p4 
         JOIN Posts p5 ON p4.Id = p5.ParentId 
         JOIN Posts p6 ON p6.Id = p4.Id 
         JOIN Tags t1 ON t1.TagName = SUBSTRING(p6.Tags, 2, LEN(p6.Tags)-2)
         WHERE p4.OwnerUserId = u.Id 
         AND p4.PostTypeId = 2 
         AND p6.Tags IS NOT NULL
         GROUP BY t1.TagName 
         ORDER BY COUNT(*) DESC), 
        'NoTagSpecified'
    ) as PrimaryAnswerTag,
    COALESCE(
        (SELECT TOP 1 t2.TagName 
         FROM Posts p7 
         JOIN Tags t2 ON t2.TagName = SUBSTRING(p7.Tags, 2, LEN(p7.Tags)-2)
         WHERE p7.OwnerUserId = u.Id 
         AND p7.PostTypeId = 1 
         AND p7.Tags IS NOT NULL
         GROUP BY t2.TagName 
         ORDER BY COUNT(*) DESC), 
        'NoTagSpecified'
    ) as PrimaryQuestionTag,
    CASE 
        WHEN COUNT(DISTINCT ph.Id) > 100 THEN 'ActiveUser'
        WHEN COUNT(DISTINCT ph.Id) > 50 THEN 'ModeratelyActiveUser'
        WHEN COUNT(DISTINCT ph.Id) > 10 THEN 'OccasionalUser'
        ELSE 'InactiveUser'
    END as EngagementLevel,
    CASE 
        WHEN COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) > 0
        AND COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) = 0
        THEN 'QuestionFocused'
        WHEN COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) = 0
        AND COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) > 0
        THEN 'AnswerFocused'
        WHEN COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) > 0
        AND COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) > 0
        AND COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) > COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0)
        THEN 'QuestionDominant'
        WHEN COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) > 0
        AND COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) > 0
        AND COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) < COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0)
        THEN 'AnswerDominant'
        ELSE 'Balanced'
    END as ContributionStyle,
    (SELECT COUNT(*) FROM (
        SELECT DISTINCT ph1.PostId 
        FROM PostHistory ph1 
        WHERE ph1.UserId = u.Id 
        AND ph1.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 24)
        EXCEPT
        SELECT DISTINCT ph2.PostId 
        FROM PostHistory ph2 
        WHERE ph2.UserId = u.Id 
        AND ph2.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 25, 31, 33, 34, 35, 36, 37, 38, 50, 52, 53, 66)
    ) AS editedPosts) as EditedPostsCount,
    (SELECT COUNT(*) FROM (
        SELECT DISTINCT ph3.PostId 
        FROM PostHistory ph3 
        WHERE ph3.UserId = u.Id 
        AND ph3.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 25, 31, 33, 34, 35, 36, 37, 38, 50, 52, 53, 66)
        EXCEPT
        SELECT DISTINCT ph4.PostId 
        FROM PostHistory ph4 
        WHERE ph4.UserId = u.Id 
        AND ph4.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 24)
    ) AS moderationPosts) as ModerationPostsCount,
    (
        CASE WHEN u.Reputation > 10000 THEN 'HighReputation' 
             WHEN u.Reputation > 5000 THEN 'MediumReputation' 
             WHEN u.Reputation > 1000 THEN 'LowReputation' 
             ELSE 'VeryLowReputation' END
    ) as ReputationTier,
    (
        SELECT COUNT(*) 
        FROM Posts p8 
        WHERE p8.OwnerUserId = u.Id 
        AND p8.PostTypeId = 1 
        AND p8.AcceptedAnswerId IS NOT NULL
    ) as QuestionsWithAcceptedAnswers,
    (
        SELECT AVG(p10.Score) 
        FROM Posts p10 
        WHERE p10.OwnerUserId = u.Id 
        AND p10.PostTypeId = 2 
        AND p10.Score IS NOT NULL
    ) as AverageAnswerScoreForUser,
    (
        SELECT COUNT(*) 
        FROM Posts p9 
        WHERE p9.OwnerUserId = u.Id 
        AND p9.PostTypeId = 1 
        AND p9.ClosedDate IS NOT NULL
    ) as ClosedQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p11 
        WHERE p11.OwnerUserId = u.Id 
        AND p11.PostTypeId = 2 
        AND p11.ParentId IS NOT NULL
        AND EXISTS (
            SELECT 1 FROM Posts p12 
            WHERE p12.Id = p11.ParentId 
            AND p12.AcceptedAnswerId = p11.Id
        )
    ) as AnsweredAcceptedQuestions,
    (
        SELECT COUNT(*) 
        FROM Comments c2 
        WHERE c2.UserId = u.Id 
        AND c2.Score >= 5
    ) as HighScoringComments
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN VoteTypes pv ON pv.Id IN (
    SELECT DISTINCT VoteTypeId 
    FROM Votes v1 
    WHERE v1.UserId = u.Id
)
LEFT JOIN Tags t ON t.Id IN (
    SELECT DISTINCT TagId 
    FROM Posts p13 
    JOIN Posts p14 ON p14.Id = p13.Id 
    WHERE p13.OwnerUserId = u.Id 
    AND p13.PostTypeId = 1 
    AND p13.Tags IS NOT NULL
)
WHERE u.CreationDate >= DATEADD(year, -5, GETDATE()) 
GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
HAVING COUNT(DISTINCT p.Id) > 0 AND u.Reputation > 0
ORDER BY TotalPosts DESC, u.Reputation DESC
OFFSET 0 ROWS FETCH NEXT 1000 ROWS ONLY;