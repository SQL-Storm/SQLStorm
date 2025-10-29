SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 10 THEN p.Id END) as HighScoreAnswers,
    COUNT(DISTINCT b.Id) as BadgeCount,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    ROUND(AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END), 2) as AvgQuestionViews,
    ROUND(AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END), 2) as AvgAnswerScore,
    MAX(p.CreationDate) as LatestPostDate,
    MIN(p.CreationDate) as FirstPostDate,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - MIN(p.CreationDate))) / 86400 as DaysActive,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(p.Id), 0), 0) as QuestionPercentage,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(p.Id), 0), 0) as AnswerPercentage,
    (
        SELECT COUNT(*) 
        FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id 
        AND p2.PostTypeId = 1 
        AND p2.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    ) as QuestionsLastYear,
    (
        SELECT COUNT(*) 
        FROM Posts p3 
        WHERE p3.OwnerUserId = u.Id 
        AND p3.PostTypeId = 2 
        AND p3.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    ) as AnswersLastYear,
    (
        SELECT COUNT(DISTINCT ph.PostId) 
        FROM PostHistory ph 
        WHERE ph.UserId = u.Id 
        AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 14, 15, 19, 20, 35, 36)
        AND ph.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    ) as EditsLastYear,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) as QuestionsWithAnswers,
    (
        SELECT STRING_AGG(t.TagName, ', ')
        FROM (
            SELECT DISTINCT t.TagName
            FROM Posts p4
            JOIN Posts p5 ON p5.ParentId = p4.Id
            JOIN Tags t ON t.TagName = TRIM(BOTH '<>' FROM SUBSTRING(p4.Tags FROM 2 FOR (CHAR_LENGTH(p4.Tags) - 2)))
            WHERE p4.OwnerUserId = u.Id
            AND p4.PostTypeId = 1
            AND p4.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 year')
        ) t
    ) as RecentTags,
    CASE 
        WHEN u.Reputation >= 1000000 THEN 'Elite'
        WHEN u.Reputation >= 100000 THEN 'Master'
        WHEN u.Reputation >= 10000 THEN 'Expert'
        WHEN u.Reputation >= 1000 THEN 'Advanced'
        WHEN u.Reputation >= 100 THEN 'Intermediate'
        ELSE 'Beginner'
    END as ReputationTier,
    (
        SELECT COUNT(*) 
        FROM Votes v
        JOIN Posts p6 ON p6.Id = v.PostId
        WHERE v.UserId = u.Id 
        AND v.VoteTypeId IN (2, 3, 5)
        AND v.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    ) as RecentVotes,
    (
        SELECT COUNT(DISTINCT p7.Id)
        FROM Posts p7
        WHERE p7.OwnerUserId = u.Id 
        AND p7.PostTypeId = 1
        AND p7.Score > 0
        AND EXISTS (
            SELECT 1 
            FROM Comments c
            WHERE c.PostId = p7.Id
            AND c.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 month')
        )
    ) as QuestionsWithRecentComments,
    (
        SELECT COUNT(DISTINCT p8.Id)
        FROM Posts p8
        WHERE p8.OwnerUserId = u.Id 
        AND p8.PostTypeId = 1
        AND p8.Score > 50
        AND p8.ViewCount > 1000
    ) as HighImpactQuestions,
    (
        SELECT COUNT(*) 
        FROM Badges b2
        WHERE b2.UserId = u.Id
        AND b2.Date >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    ) as BadgesLastYear,
    (
        SELECT COUNT(DISTINCT p9.Id)
        FROM Posts p9
        JOIN PostHistory ph2 ON ph2.PostId = p9.Id
        WHERE p9.OwnerUserId = u.Id
        AND ph2.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
        AND ph2.PostHistoryTypeId = 5
    ) as BodiesEdited,
    (
        SELECT AVG(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1.0 ELSE 0.0 END)
        FROM Votes v
        JOIN Posts p10 ON p10.Id = v.PostId
        WHERE p10.OwnerUserId = u.Id
        AND v.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    ) as VoteRate,
    (
        SELECT MAX(p11.Score)
        FROM Posts p11
        WHERE p11.OwnerUserId = u.Id
        AND p11.PostTypeId = 1
    ) as MaxQuestionScore,
    (
        SELECT MIN(p12.ViewCount)
        FROM Posts p12
        WHERE p12.OwnerUserId = u.Id
        AND p12.PostTypeId = 1
    ) as MinQuestionViews,
    (
        SELECT COUNT(DISTINCT p13.Id)
        FROM Posts p13
        WHERE p13.OwnerUserId = u.Id
        AND p13.PostTypeId = 1
        AND p13.Score >= p13.ViewCount / 10.0
    ) as ModeratelyPopularQuestions
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
WHERE 
    u.Reputation > 100
    AND u.Id > 0
    AND (
        EXISTS (SELECT 1 FROM Posts p4 WHERE p4.OwnerUserId = u.Id AND p4.PostTypeId = 1)
        OR EXISTS (SELECT 1 FROM Posts p5 WHERE p5.OwnerUserId = u.Id AND p5.PostTypeId = 2)
        OR EXISTS (SELECT 1 FROM Badges b2 WHERE b2.UserId = u.Id)
    )
    AND (
        u.CreationDate <= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
        OR u.CreationDate IS NULL
    )
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) >= 10
    AND (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0
         OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0)
ORDER BY 
    u.Reputation DESC,
    TotalPosts DESC,
    LatestPostDate DESC
LIMIT 1000
OFFSET 0;