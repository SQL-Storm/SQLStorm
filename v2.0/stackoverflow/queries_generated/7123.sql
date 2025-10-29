-- {"query": "7123.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2308} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT b.Id) as Badges,
    COUNT(DISTINCT c.Id) as Comments,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) as AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) as AvgAnswerScore,
    MAX(p.CreationDate) as LatestPost,
    MIN(p.CreationDate) as FirstPost,
    DATEDIFF(CURRENT_TIMESTAMP, MAX(p.CreationDate)) as DaysSinceLastPost,
    COALESCE(SUM(p.ViewCount), 0) as TotalViews,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as AcceptedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN p.Id END) as AnsweredQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND (p.Tags LIKE '%python%' OR p.Tags LIKE '%java%') THEN p.Id END) as TechQuestions,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1 AND p2.Score > 100) as HighScoreQuestions,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = u.Id AND p3.PostTypeId = 2 AND p3.Score > 50) as HighScoreAnswers,
    (SELECT AVG(Score) FROM Posts p4 WHERE p4.OwnerUserId = u.Id AND p4.PostTypeId IN (1,2)) as AvgPostScore,
    (SELECT COUNT(DISTINCT CommentId) FROM (
        SELECT c.Id as CommentId, p.Id as PostId, 
               ROW_NUMBER() OVER (PARTITION BY c.UserId, p.Id ORDER BY c.CreationDate) as rn
        FROM Comments c
        INNER JOIN Posts p ON c.PostId = p.Id
        WHERE c.UserId = u.Id
        AND p.OwnerUserId = u.Id
    ) ranked WHERE rn = 1) as UniqueCommentsOnOwnPosts,
    (
        SELECT COUNT(*) 
        FROM Posts p5 
        WHERE p5.OwnerUserId = u.Id 
        AND p5.CreationDate >= DATEADD('month', -3, CURRENT_TIMESTAMP)
    ) as RecentPosts,
    COALESCE(
        (
            SELECT TOP 1 b2.Name 
            FROM Badges b2 
            WHERE b2.UserId = u.Id 
            GROUP BY b2.Name 
            ORDER BY COUNT(*) DESC
        ), 'None'
    ) as MostFrequentBadge,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 100 THEN 'Veteran'
        WHEN COUNT(DISTINCT p.Id) > 50 THEN 'Regular'
        WHEN COUNT(DISTINCT p.Id) > 10 THEN 'Contributor'
        ELSE 'Newbie'
    END as UserCategory,
    (
        SELECT COUNT(*) 
        FROM Posts p6 
        WHERE p6.OwnerUserId = u.Id 
        AND p6.ParentId IS NOT NULL
        AND p6.CreationDate < DATEADD('week', -2, CURRENT_TIMESTAMP)
    ) as OldAnsweredQuestions,
    (
        SELECT STRING_AGG(p7.Tags, ', ')
        FROM Posts p7 
        WHERE p7.OwnerUserId = u.Id 
        AND p7.PostTypeId = 1
        AND p7.Tags IS NOT NULL
        AND p7.Tags != ''
        AND LENGTH(p7.Tags) > 10
        ORDER BY p7.CreationDate DESC
        LIMIT 5
    ) as RecentQuestionTags,
    (
        SELECT COUNT(DISTINCT ph.Id)
        FROM PostHistory ph
        INNER JOIN Posts p8 ON ph.PostId = p8.Id
        WHERE p8.OwnerUserId = u.Id
        AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
        AND ph.CreationDate >= DATEADD('month', -6, CURRENT_TIMESTAMP)
    ) as RecentEdits,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.UserId = u.Id 
        AND v.VoteTypeId IN (2, 3)
        AND v.CreationDate >= DATEADD('year', -1, CURRENT_TIMESTAMP)
    ) as RecentVotes,
    (
        SELECT AVG(CASE 
            WHEN p9.Score > 0 THEN CAST(p9.Score AS FLOAT)
            ELSE 1.0
        END) 
        FROM Posts p9 
        WHERE p9.OwnerUserId = u.Id 
        AND p9.PostTypeId = 1
    ) as AvgQuestionScoreWeighted,
    (
        SELECT COUNT(DISTINCT p10.Id) 
        FROM Posts p10 
        WHERE p10.OwnerUserId = u.Id 
        AND p10.PostTypeId = 1
        AND p10.CreationDate BETWEEN DATEADD('day', -7, CURRENT_TIMESTAMP) AND CURRENT_TIMESTAMP
    ) as RecentQuestions,
    (COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM Users), 0)) as PostPercentageOfAllUsers,
    (
        SELECT COUNT(*)
        FROM (
            SELECT p11.OwnerUserId, COUNT(*) as PostCount
            FROM Posts p11 
            WHERE p11.OwnerUserId IS NOT NULL
            GROUP BY p11.OwnerUserId
            HAVING COUNT(*) > (
                SELECT AVG(PostCount) 
                FROM (
                    SELECT OwnerUserId, COUNT(*) as PostCount
                    FROM Posts 
                    WHERE OwnerUserId IS NOT NULL
                    GROUP BY OwnerUserId
                ) avg_posts
            )
        ) high_post_users
        WHERE OwnerUserId = u.Id
    ) as AboveAveragePostUser,
    (
        SELECT STRING_AGG(
            CONCAT('Tag: ', t.TagName, ' Count: ', t.Count), 
            '; '
        )
        FROM Tags t
        WHERE t.TagName IN (
            SELECT DISTINCT TRIM(SUBSTRING(p12.Tags, 
                CASE WHEN pos1 > 0 THEN pos1 + 1 ELSE 1 END, 
                CASE WHEN pos2 > 0 THEN pos2 - pos1 - 1 ELSE LENGTH(p12.Tags) END
            ))
            FROM Posts p12
            WHERE p12.OwnerUserId = u.Id 
            AND p12.Tags IS NOT NULL
            AND p12.PostTypeId = 1
            AND pos1 > 0
            FOR pos1 IN (1,2,3,4,5,6,7,8,9,10)
        )
        AND t.Count > (
            SELECT AVG(Count) 
            FROM Tags
        )
    ) as PopularTags,
    (
        SELECT COALESCE(
            STRING_AGG(
                CASE 
                    WHEN c1.Text LIKE '%thank%' OR c1.Text LIKE '%great%' OR c1.Text LIKE '%help%' 
                    THEN c1.Text
                    ELSE NULL 
                END, 
                ' '
            ), 
            'No helpful comments'
        )
        FROM Comments c1 
        WHERE c1.UserId = u.Id
    ) as HelpfulComments,
    CASE 
        WHEN (SELECT COUNT(*) FROM Votes v1 WHERE v1.UserId = u.Id AND v1.VoteTypeId = 2) > 0 
        THEN 'ActiveVoter' 
        ELSE 'InactiveVoter' 
    END as VotingStatus,
    (
        SELECT COUNT(DISTINCT p13.Id) * 100.0 / NULLIF(COUNT(*) * 100.0, 0)
        FROM Posts p13 
        INNER JOIN Users u2 ON p13.OwnerUserId = u2.Id
        WHERE p13.OwnerUserId = u.Id
        AND p13.PostTypeId = 1
        AND p13.Score > 0
    ) as PositiveScorePercentage,
    NULLIF(
        (SELECT AVG(v2.BountyAmount) FROM Votes v2 WHERE v2.UserId = u.Id AND v2.VoteTypeId = 8), 
        0
    ) as AvgBountyAmount,
    (
        SELECT COUNT(*) 
        FROM Posts p14 
        WHERE p14.OwnerUserId = u.Id
        AND p14.PostTypeId = 1
        AND (p14.AnswerCount IS NOT NULL AND p14.AnswerCount > 0)
    ) as QuestionsWithAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p15 
        WHERE p15.OwnerUserId = u.Id
        AND p15.PostTypeId = 1
        AND p15.AcceptedAnswerId IS NOT NULL
    ) as QuestionsWithAcceptedAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p16 
        WHERE p16.OwnerUserId = u.Id
        AND p16.PostTypeId = 1
        AND p16.CreationDate >= DATEADD('week', -1, CURRENT_TIMESTAMP)
    ) as RecentQuestionsThisWeek,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph2 
        WHERE ph2.UserId = u.Id
        AND ph2.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15)
        AND ph2.CreationDate >= DATEADD('month', -1, CURRENT_TIMESTAMP)
    ) as RecentModerationActions,
    (
        SELECT 
            CASE 
                WHEN COUNT(*) > 10 THEN 'FrequentEditor'
                WHEN COUNT(*) > 5 THEN 'RegularEditor'
                ELSE 'OccasionalEditor'
            END
        FROM PostHistory ph3 
        WHERE ph3.UserId = u.Id
        AND ph3.PostHistoryTypeId IN (2, 5, 6)
    ) as EditorFrequency
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
WHERE u.Reputation >= 100
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY TotalPosts DESC, Reputation DESC
LIMIT 1000
OPTION (MAXDOP 1)