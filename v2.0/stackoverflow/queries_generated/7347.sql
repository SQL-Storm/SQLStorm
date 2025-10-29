-- {"query": "7347.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2440} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 10 THEN p.Id END) as HighScoreAnswers,
    COUNT(DISTINCT b.Id) as Badges,
    STRING_AGG(DISTINCT b.Name, ', ') as BadgeNames,
    MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as HasGoldBadge,
    MAX(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) as HasSilverBadge,
    MAX(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) as HasBronzeBadge,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT ph.Id) as HistoryCount,
    COUNT(DISTINCT pl.Id) as LinkCount,
    (
        SELECT COUNT(*) 
        FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id 
        AND p2.PostTypeId = 1 
        AND p2.AnswerCount > 0
    ) as QuestionWithAnswers,
    (
        SELECT COUNT(*) 
        FROM Posts p3 
        WHERE p3.OwnerUserId = u.Id 
        AND p3.PostTypeId = 1 
        AND p3.Score > 100
    ) as HighScoreQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p4 
        WHERE p4.OwnerUserId = u.Id 
        AND p4.PostTypeId = 2 
        AND p4.ParentId IN (
            SELECT Id FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1
        )
    ) as AnswerToOwnQuestions,
    (
        SELECT STRING_AGG(
            CASE 
                WHEN p5.PostTypeId = 1 THEN 'Q:' || p5.Title
                WHEN p5.PostTypeId = 2 THEN 'A:' || COALESCE(p5.Body, '')
                ELSE 'Other'
            END, ' | '
        ) 
        FROM Posts p5 
        WHERE p5.OwnerUserId = u.Id 
        ORDER BY p5.CreationDate DESC
        LIMIT 5
    ) as RecentPosts,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.UserId = u.Id 
        AND v.VoteTypeId IN (2, 3)
    ) as VoteCount,
    (
        SELECT AVG(v.Score) 
        FROM Votes v 
        JOIN Posts p6 ON v.PostId = p6.Id 
        WHERE v.UserId = u.Id 
        AND v.VoteTypeId IN (2, 3)
        AND p6.PostTypeId = 1
    ) as AvgQuestionScore,
    (
        SELECT STRING_AGG(
            t.TagName, 
            ' '
        ) 
        FROM Posts p7 
        JOIN (
            SELECT DISTINCT PostId, unnest(string_to_array(Tags, '>')) as TagName 
            FROM Posts 
            WHERE OwnerUserId = u.Id AND Tags IS NOT NULL
        ) t ON p7.Id = t.PostId
        WHERE p7.OwnerUserId = u.Id
        ORDER BY t.TagName
    ) as TagInterests,
    (
        SELECT MAX(
            CASE 
                WHEN p8.PostTypeId = 1 THEN p8.Score 
                ELSE 0 
            END
        ) 
        FROM Posts p8 
        WHERE p8.OwnerUserId = u.Id
    ) as MaxQuestionScore,
    (
        SELECT MAX(
            CASE 
                WHEN p9.PostTypeId = 2 THEN p9.Score 
                ELSE 0 
            END
        ) 
        FROM Posts p9 
        WHERE p9.OwnerUserId = u.Id
    ) as MaxAnswerScore,
    (
        SELECT COUNT(*) 
        FROM Posts p10 
        WHERE p10.OwnerUserId = u.Id 
        AND p10.CreationDate >= DATEADD('day', -30, CURRENT_TIMESTAMP)
    ) as RecentPostsLast30Days,
    (
        SELECT COUNT(*) 
        FROM Comments c2 
        WHERE c2.UserId = u.Id
    ) as CommentsInLast30Days,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph2 
        WHERE ph2.UserId = u.Id
    ) as HistoryEventsInLast30Days,
    (
        SELECT COUNT(DISTINCT ph3.PostId) 
        FROM PostHistory ph3 
        WHERE ph3.UserId = u.Id 
        AND ph3.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
    ) as EditedPosts,
    (
        SELECT COUNT(*) 
        FROM Users u2 
        WHERE u2.Reputation > u.Reputation
    ) as UsersWithHigherReputation,
    (
        SELECT STRING_AGG(
            CASE 
                WHEN p11.PostTypeId = 1 THEN 'Q'
                WHEN p11.PostTypeId = 2 THEN 'A'
                ELSE 'Other'
            END, 
            ''
        ) 
        FROM Posts p11 
        WHERE p11.OwnerUserId = u.Id
        ORDER BY p11.CreationDate
        LIMIT 10
    ) as PostTypeSequence,
    (
        SELECT AVG(
            DATEDIFF('second', p12.CreationDate, p12.LastActivityDate) / 86400.0
        ) 
        FROM Posts p12 
        WHERE p12.OwnerUserId = u.Id 
        AND p12.PostTypeId = 1
    ) as AvgDaysBetweenCreationAndActivity,
    (
        SELECT COUNT(DISTINCT p13.Id) 
        FROM Posts p13 
        WHERE p13.OwnerUserId = u.Id 
        AND p13.Tags IS NOT NULL
        AND p13.Tags LIKE '%<%'
    ) as QuestionsWithTags,
    (
        SELECT STRING_AGG(
            COALESCE(b2.Name, 'No Badge'), 
            ' | '
        ) 
        FROM (
            SELECT b2.Name, b2.Class
            FROM Badges b2
            WHERE b2.UserId = u.Id
            AND b2.Date >= DATEADD('year', -1, CURRENT_TIMESTAMP)
            ORDER BY b2.Date DESC
            LIMIT 5
        ) b2
    ) as RecentBadges,
    (
        SELECT COUNT(DISTINCT p14.Id) 
        FROM Posts p14
        LEFT JOIN (
            SELECT DISTINCT PostId 
            FROM PostLinks 
            WHERE LinkTypeId = 3
        ) pl2 ON p14.Id = pl2.PostId
        WHERE p14.OwnerUserId = u.Id AND pl2.PostId IS NOT NULL
    ) as DuplicateQuestions,
    (
        SELECT COUNT(DISTINCT ph4.Id) 
        FROM PostHistory ph4 
        WHERE ph4.UserId = u.Id 
        AND ph4.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15)
    ) as ModerationEvents,
    (
        SELECT STRING_AGG(
            CASE 
                WHEN ph5.PostHistoryTypeId = 1 THEN 'T'
                WHEN ph5.PostHistoryTypeId = 2 THEN 'B'
                WHEN ph5.PostHistoryTypeId = 3 THEN 'T'
                WHEN ph5.PostHistoryTypeId = 4 THEN 'T'
                WHEN ph5.PostHistoryTypeId = 5 THEN 'B'
                WHEN ph5.PostHistoryTypeId = 6 THEN 'T'
                ELSE 'O'
            END, 
            ''
        ) 
        FROM PostHistory ph5 
        WHERE ph5.UserId = u.Id
        ORDER BY ph5.CreationDate
        LIMIT 10
    ) as EditTypeSequence,
    (
        SELECT COUNT(DISTINCT p15.Id) 
        FROM Posts p15 
        WHERE p15.OwnerUserId = u.Id 
        AND p15.Score >= 0
        AND p15.Score <= 5
    ) as LowScorePosts,
    (
        SELECT COUNT(DISTINCT p16.Id) 
        FROM Posts p16 
        WHERE p16.OwnerUserId = u.Id 
        AND p16.Score >= 100
        AND p16.ViewCount >= 1000
    ) as HighlyRatedHighViewPosts,
    (
        SELECT COUNT(DISTINCT p17.Id) 
        FROM Posts p17 
        WHERE p17.OwnerUserId = u.Id 
        AND p17.ParentId IS NOT NULL
        AND p17.PostTypeId = 2
        AND (
            SELECT COUNT(*) 
            FROM Votes v2 
            WHERE v2.PostId = p17.Id 
            AND v2.VoteTypeId = 1
        ) > 0
    ) as AcceptedAnswers,
    (
        SELECT AVG(p18.Score) 
        FROM Posts p18 
        WHERE p18.OwnerUserId = u.Id 
        AND p18.PostTypeId = 2
        AND p18.Score > 0
    ) as AvgAnswerScore,
    (
        SELECT COUNT(*) 
        FROM (
            SELECT p19.OwnerUserId 
            FROM Posts p19 
            WHERE p19.OwnerUserId = u.Id
            GROUP BY p19.OwnerUserId
            HAVING COUNT(p19.Id) > 100
        ) sub1
    ) as HighActivityUser,
    (
        SELECT COUNT(DISTINCT p20.Id) 
        FROM Posts p20 
        WHERE p20.OwnerUserId = u.Id 
        AND p20.CreationDate BETWEEN DATEADD('month', -6, CURRENT_TIMESTAMP) AND CURRENT_TIMESTAMP
    ) as RecentPostsLast6Months,
    (
        SELECT COUNT(DISTINCT p21.Id) 
        FROM Posts p21 
        WHERE p21.OwnerUserId = u.Id 
        AND p21.CreationDate BETWEEN DATEADD('month', -12, CURRENT_TIMESTAMP) AND CURRENT_TIMESTAMP
    ) as RecentPostsLastYear,
    (
        SELECT STRING_AGG(
            COALESCE(p22.Title, 'No Title'), 
            ' && '
        ) 
        FROM Posts p22 
        WHERE p22.OwnerUserId = u.Id 
        AND p22.PostTypeId = 1
        ORDER BY p22.CreationDate DESC
        LIMIT 3
    ) as RecentQuestionTitles
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON u.Id = (
    SELECT UserId 
    FROM Posts 
    WHERE Id = pl.PostId
)
WHERE u.Id > 0
AND u.Reputation > 0
AND (
    SELECT COUNT(*) 
    FROM Posts p23 
    WHERE p23.OwnerUserId = u.Id
) >= 1
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) >= 5
ORDER BY u.Reputation DESC
LIMIT 100;