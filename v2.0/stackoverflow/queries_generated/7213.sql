-- {"query": "7213.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1733} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) as Questions,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) as Answers,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as QuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as AnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) as AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) as AvgAnswerScore,
    MAX(p.CreationDate) as LastPostDate,
    MIN(p.CreationDate) as FirstPostDate,
    COUNT(DISTINCT b.Id) as BadgesReceived,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COUNT(DISTINCT c.Id) as CommentsMade,
    COUNT(DISTINCT ph.Id) as EditHistoryCount,
    (
        SELECT COUNT(*) 
        FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id 
        AND p2.PostTypeId = 1 
        AND p2.CreationDate >= DATEADD(month, -6, GETDATE())
    ) as RecentQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p3 
        WHERE p3.OwnerUserId = u.Id 
        AND p3.PostTypeId = 2 
        AND p3.CreationDate >= DATEADD(month, -6, GETDATE())
    ) as RecentAnswers,
    (
        SELECT TOP 1 p4.Title 
        FROM Posts p4 
        WHERE p4.OwnerUserId = u.Id 
        AND p4.PostTypeId = 1 
        ORDER BY p4.Score DESC
    ) as HighestScoringQuestion,
    (
        SELECT TOP 1 p5.Title 
        FROM Posts p5 
        WHERE p5.OwnerUserId = u.Id 
        AND p5.PostTypeId = 2 
        ORDER BY p5.Score DESC
    ) as HighestScoringAnswer,
    ISNULL(
        (
            SELECT STRING_AGG(t.TagName, ', ') 
            FROM Posts p6 
            INNER JOIN STRING_SPLIT(p6.Tags, '><') AS tagSplit ON 1=1
            INNER JOIN Tags t ON t.TagName = LTRIM(RTRIM(tagSplit.value))
            WHERE p6.OwnerUserId = u.Id 
            AND p6.PostTypeId = 1
            GROUP BY p6.OwnerUserId
            HAVING COUNT(*) > 0
        ), 
        'No tags'
    ) as UserTags,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        INNER JOIN Posts p7 ON v.PostId = p7.Id 
        WHERE v.UserId = u.Id 
        AND v.VoteTypeId IN (2, 3)
        AND p7.CreationDate >= DATEADD(day, -30, GETDATE())
    ) as RecentVotes,
    (
        SELECT COUNT(DISTINCT PostId) 
        FROM PostLinks pl 
        WHERE pl.PostId IN (
            SELECT Id FROM Posts WHERE OwnerUserId = u.Id
        ) 
        AND pl.LinkTypeId = 3
    ) as DuplicateLinks,
    (
        SELECT COUNT(DISTINCT PostId) 
        FROM PostLinks pl 
        WHERE pl.RelatedPostId IN (
            SELECT Id FROM Posts WHERE OwnerUserId = u.Id
        ) 
        AND pl.LinkTypeId = 1
    ) as LinkedPosts,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 10 AND COUNT(DISTINCT b.Id) > 5 
        THEN 'Active Contributor' 
        WHEN COUNT(DISTINCT p.Id) > 5 AND COUNT(DISTINCT b.Id) > 2 
        THEN 'Regular Poster' 
        ELSE 'Occasional User' 
    END as UserCategory,
    DATEDIFF(day, u.CreationDate, GETDATE()) as AccountAgeDays,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph2 
        WHERE ph2.UserId = u.Id 
        AND ph2.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
        AND ph2.CreationDate >= DATEADD(month, -3, GETDATE())
    ) as RecentEdits,
    (
        SELECT COUNT(*) 
        FROM Posts p8 
        WHERE p8.OwnerUserId = u.Id 
        AND p8.PostTypeId = 1 
        AND p8.AnswerCount > 0
    ) as QuestionsWithAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p9 
        WHERE p9.OwnerUserId = u.Id 
        AND p9.PostTypeId = 2 
        AND p9.ParentId IS NOT NULL
    ) as AnsweredPosts,
    (
        SELECT AVG(p10.Score) 
        FROM Posts p10 
        WHERE p10.OwnerUserId = u.Id 
        AND p10.PostTypeId IN (1, 2)
        AND p10.Score IS NOT NULL
    ) as AveragePostScore,
    (
        SELECT 
            COUNT(DISTINCT pl2.Id) 
        FROM PostLinks pl2 
        INNER JOIN Posts p11 ON pl2.PostId = p11.Id
        WHERE p11.OwnerUserId = u.Id 
        AND pl2.CreationDate >= DATEADD(month, -1, GETDATE())
        AND pl2.LinkTypeId = 1
    ) as RecentLinkPosts
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
WHERE u.Id IN (
    SELECT DISTINCT u2.Id 
    FROM Users u2
    INNER JOIN Posts p2 ON u2.Id = p2.OwnerUserId
    INNER JOIN PostTypes pt ON p2.PostTypeId = pt.Id
    WHERE pt.Name IN ('Question', 'Answer')
    GROUP BY u2.Id
    HAVING COUNT(*) >= 2
)
AND (
    EXISTS (
        SELECT 1 
        FROM Posts p3 
        WHERE p3.OwnerUserId = u.Id 
        AND p3.PostTypeId = 1
        AND p3.ViewCount > 100
    ) OR EXISTS (
        SELECT 1 
        FROM Posts p4 
        WHERE p4.OwnerUserId = u.Id 
        AND p4.PostTypeId = 2
        AND p4.Score > 5
    )
)
GROUP BY 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    u.CreationDate
HAVING 
    COUNT(DISTINCT p.Id) > 0
    AND (
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) > 0 
        OR COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) > 0
    )
    AND (
        (COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) > 0 AND COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) > 0)
        OR (COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) > 0 AND COUNT(DISTINCT b.Id) > 3)
        OR (COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) > 0 AND COUNT(DISTINCT b.Id) > 3)
    )
ORDER BY 
    CASE 
        WHEN COUNT(DISTINCT b.Id) > 0 THEN COUNT(DISTINCT b.Id) 
        ELSE COUNT(DISTINCT p.Id) 
    END DESC,
    u.Reputation DESC,
    MAX(p.CreationDate) DESC
OFFSET 10 ROWS
FETCH NEXT 20 ROWS ONLY;