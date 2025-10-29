-- {"query": "7686.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 5192} 
WITH UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) as TotalPosts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) as QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) as AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) as AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) as AvgAnswerScore,
        MAX(p.CreationDate) as LatestPostDate,
        MIN(p.CreationDate) as FirstPostDate,
        CASE 
            WHEN COUNT(p.Id) > 0 THEN DATEDIFF(day, MIN(p.CreationDate), MAX(p.CreationDate))
            ELSE 0 
        END as DaysActive,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) as GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) as SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) as BronzeBadges,
        STRING_AGG(
            CASE 
                WHEN p.PostTypeId = 1 THEN CONCAT('Q:', p.Title, ' (', p.Score, ')')
                WHEN p.PostTypeId = 2 THEN CONCAT('A:', SUBSTRING(p.Body, 1, 50), '...')
            END, 
            '; '
        ) as RecentActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
QuestionStats AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        u.DisplayName as OwnerName,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) as DaysSinceLastActivity,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END as Status,
        CASE 
            WHEN p.AnswerCount > 0 THEN 
                (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.Score > 0) * 100.0 / p.AnswerCount
            ELSE 0 
        END as PositiveAnswerPercentage,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) - 
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as NetVotes,
        STRING_AGG(
            CASE WHEN v.VoteTypeId IN (2, 3) THEN 
                CONCAT(v.UserId, ':', CASE WHEN v.VoteTypeId = 2 THEN 'Up' ELSE 'Down' END)
            END, 
            ', '
        ) as VoteActivity,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as ScoreRank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, 
             p.CreationDate, p.OwnerUserId, p.Tags, u.DisplayName, p.LastActivityDate, 
             p.ClosedDate, p.CommunityOwnedDate
),
AnswerStats AS (
    SELECT 
        a.Id as AnswerId,
        a.ParentId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        u.DisplayName as OwnerName,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 2) as Upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 3) as Downvotes,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) as RankInQuestion,
        CASE 
            WHEN a.Score > 0 THEN 'Positive'
            WHEN a.Score < 0 THEN 'Negative'
            ELSE 'Neutral'
        END as ScoreCategory,
        DATEDIFF(day, a.CreationDate, GETDATE()) as DaysOld,
        CAST(LEN(a.Body) AS FLOAT) / 100 as BodyLength,
        CASE 
            WHEN a.OwnerUserId IS NOT NULL THEN 'User'
            ELSE 'Community'
        END as AnswerType
    FROM Posts a
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.Count * 100.0 / (SELECT SUM(Count) FROM Tags) as PercentageOfAllTags,
        CASE 
            WHEN t.Count > 500 THEN 'High'
            WHEN t.Count > 100 THEN 'Medium'
            WHEN t.Count > 10 THEN 'Low'
            ELSE 'Very Low'
        END as PopularityLevel,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' + t.TagName + '%') as QuestionsUsingTag,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' + t.TagName + '%') as AvgScoreForTag,
        STRING_AGG(
            (SELECT TOP 1 p.Title FROM Posts p WHERE p.Tags LIKE '%' + t.TagName + '%' AND p.PostTypeId = 1 ORDER BY p.CreationDate DESC),
            '; '
        ) as RecentQuestions
    FROM Tags t
    GROUP BY t.TagName, t.Count
)
SELECT TOP 100
    'User Performance Report' as ReportType,
    u.DisplayName as UserName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    ups.TotalPosts,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.TotalQuestionScore,
    ups.TotalAnswerScore,
    ups.AvgQuestionScore,
    ups.AvgAnswerScore,
    ups.GoldBadges,
    ups.SilverBadges,
    ups.BronzeBadges,
    ups.DaysActive,
    ups.LatestPostDate,
    ups.FirstPostDate,
    CASE 
        WHEN ups.TotalPosts > 0 THEN ups.DaysActive / ups.TotalPosts
        ELSE 0 
    END as AvgPostsPerDay,
    CASE 
        WHEN ups.TotalQuestionScore + ups.TotalAnswerScore > 0 THEN 
            (ups.TotalQuestionScore - ups.TotalAnswerScore) * 100.0 / (ups.TotalQuestionScore + ups.TotalAnswerScore)
        ELSE 0 
    END as ScoreDifferencePercentage,
    CASE 
        WHEN ups.TotalQuestionScore > 0 THEN (ups.TotalQuestionScore * 100.0) / ups.GoldBadges
        ELSE 0 
    END as ScorePerGoldBadge,
    CASE 
        WHEN ups.TotalAnswerScore > 0 AND ups.AnswerCount > 0 THEN ups.TotalAnswerScore / ups.AnswerCount
        ELSE 0 
    END as AvgAnswerScorePerAnswer,
    SUBSTRING(ups.RecentActivity, 1, 200) as RecentActivitySample,
    CASE 
        WHEN ups.QuestionCount > 0 AND ups.AnswerCount > 0 THEN 
            CAST(ups.AnswerCount AS FLOAT) / CAST(ups.QuestionCount AS FLOAT)
        ELSE 0 
    END as AnswersPerQuestion,
    (SELECT MAX(qs.Score) FROM QuestionStats qs WHERE qs.OwnerUserId = u.Id) as HighestQuestionScore,
    (SELECT MIN(qs.Score) FROM QuestionStats qs WHERE qs.OwnerUserId = u.Id) as LowestQuestionScore,
    (SELECT AVG(qs.Score) FROM QuestionStats qs WHERE qs.OwnerUserId = u.Id) as AverageQuestionScore,
    (SELECT COUNT(*) FROM QuestionStats qs WHERE qs.OwnerUserId = u.Id AND qs.DaysSinceLastActivity <= 1) as RecentlyActiveQuestions,
    STRING_AGG(
        CASE 
            WHEN q.Title IS NOT NULL THEN 
                CONCAT(q.Title, ' (Score:', q.Score, ')')
        END, 
        '; '
    ) as RecentQuestions,
    STRING_AGG(
        CASE 
            WHEN a.Id IS NOT NULL THEN 
                CONCAT('Answer for Q', a.ParentId, ' (Score:', a.Score, ')')
        END, 
        '; '
    ) as RecentAnswers,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId IN (2, 3)) as TotalVoteActivity,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) as CommentCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Date > DATEADD(year, -1, GETDATE())) as RecentBadges,
    CASE 
        WHEN u.EmailHash IS NOT NULL THEN 'Email Provided'
        ELSE 'No Email'
    END as EmailStatus,
    CASE 
        WHEN u.WebsiteUrl IS NOT NULL THEN 'Website Provided'
        ELSE 'No Website'
    END as WebsiteStatus,
    CASE 
        WHEN u.Location IS NOT NULL AND LEN(u.Location) > 0 THEN 'Location Provided'
        ELSE 'No Location'
    END as LocationStatus,
    COALESCE(u.AboutMe, 'No Bio') as BiographicalInfo,
    CASE 
        WHEN u.AccountId < 0 THEN 'Deleted User'
        ELSE 'Active User'
    END as AccountStatus,
    CASE 
        WHEN UPS.TotalPosts > 100 THEN 'High Activity'
        WHEN UPS.TotalPosts > 20 THEN 'Medium Activity'
        WHEN UPS.TotalPosts > 0 THEN 'Low Activity'
        ELSE 'No Posts'
    END as ActivityLevel,
    CASE 
        WHEN UPS.GoldBadges > 5 THEN 'Elite Contributor'
        WHEN UPS.GoldBadges > 2 THEN 'Seasoned Contributor'
        WHEN UPS.GoldBadges > 0 THEN 'New Contributor'
        ELSE 'Beginner'
    END as ContributionTier,
    CASE 
        WHEN u.Reputation > 10000 THEN 'Expert'
        WHEN u.Reputation > 1000 THEN 'Advanced'
        WHEN u.Reputation > 100 THEN 'Intermediate'
        ELSE 'Beginner'
    END as ReputationTier,
    (SELECT COUNT(DISTINCT p.OwnerUserId) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.CreationDate > DATEADD(month, -6, GETDATE())) as RecentActivityLast6Months,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.CreationDate > DATEADD(month, -3, GETDATE())) as AvgScore3Months,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.CreationDate > DATEADD(year, -1, GETDATE())) as QuestionsLastYear,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2 AND p.CreationDate > DATEADD(year, -1, GETDATE())) as AnswersLastYear,
    (SELECT MAX(p.ViewCount) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) as MaxQuestionViews,
    (SELECT MAX(p.ViewCount) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) as MaxAnswerViews,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id) as VoteCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) as UpvotesReceived,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) as DownvotesReceived,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 4) as OffensiveVotes,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.LastEditDate > p.CreationDate) as EditedPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.CommentCount > 0) as CommentedPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.AcceptedAnswerId IS NOT NULL) as AcceptedAnswers,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.AnswerCount > 0) as AnsweredQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.Score >= 10) as HighScorePosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.Score < 0) as NegativeScorePosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.ViewCount > 10000) as HighlyViewedPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.ViewCount BETWEEN 1000 AND 10000) as IntermediateViewedPosts,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.ViewCount < 1000) as LowViewedPosts,
    (
        SELECT COUNT(*) FROM Posts p 
        LEFT JOIN Votes v ON p.Id = v.PostId 
        WHERE p.OwnerUserId = u.Id 
        AND v.VoteTypeId IN (2, 3)
        AND v.CreationDate > DATEADD(day, -30, GETDATE())
    ) as RecentVotingActivity,
    (SELECT MAX(DATEDIFF(day, p.CreationDate, GETDATE())) FROM Posts p WHERE p.OwnerUserId = u.Id) as MaxPostAgeDays,
    (SELECT AVG(DATEDIFF(day, p.CreationDate, GETDATE())) FROM Posts p WHERE p.OwnerUserId = u.Id) as AvgPostAgeDays,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1 AND b.Date > DATEADD(month, -6, GETDATE())) as RecentGoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2 AND b.Date > DATEADD(month, -6, GETDATE())) as RecentSilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3 AND b.Date > DATEADD(month, -6, GETDATE())) as RecentBronzeBadges,
    (SELECT 
        STRING_AGG(CONCAT('Badge:', b.Name, ' Date:', CONVERT(VARCHAR, b.Date, 101)), ', ')
        FROM Badges b 
        WHERE b.UserId = u.Id 
        AND b.Date > DATEADD(year, -2, GETDATE())
        ORDER BY b.Date DESC
        OFFSET 0 ROWS 
        FETCH NEXT 5 ROWS ONLY
    ) as RecentBadgesList,
    (SELECT STRING_AGG(
        CASE 
            WHEN p.ViewCount > 5000 THEN 
                CONCAT('VIEWS:', p.ViewCount, ' TITLE:', LEFT(p.Title, 50))
        END, 
        ' | '
    ) FROM Posts p WHERE p.OwnerUserId = u.Id) as PopularPostsSample,
    (SELECT STRING_AGG(
        CASE 
            WHEN p.Score > 5 THEN 
                CONCAT('SCORE:', p.Score, ' TITLE:', LEFT(p.Title, 50))
        END, 
        ' | '
    ) FROM Posts p WHERE p.OwnerUserId = u.Id) as HighScorePostsSample,
    (SELECT STRING_AGG(
        CASE 
            WHEN p.CommentCount > 5 THEN 
                CONCAT('COMMENTS:', p.CommentCount, ' TITLE:', LEFT(p.Title, 50))
        END, 
        ' | '
    ) FROM Posts p WHERE p.OwnerUserId = u.Id) as CommentedPostsSample,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, ups.TotalPosts DESC) as Ranking,
    CAST(NEWID() AS VARCHAR(36)) as UniqueIdentifier,
    GETDATE() as ReportGenerationTime,
    'Generated for Analysis' as ReportContext,
    CASE 
        WHEN ups.TotalPosts > 0 AND ups.QuestionCount = 0 THEN 'Answer focused'
        WHEN ups.TotalPosts > 0 AND ups.AnswerCount = 0 THEN 'Question focused'
        ELSE 'Mixed focus'
    END as FocusArea,
    CASE 
        WHEN ups.DaysActive > 365 THEN 'Long term contributor'
        WHEN ups.DaysActive > 180 THEN 'Regular contributor'
        WHEN ups.DaysActive > 30 THEN 'Active contributor'
        ELSE 'New contributor'
    END as ContributionDuration,
    CASE 
        WHEN (ups.GoldBadges + ups.SilverBadges + ups.BronzeBadges) > 10 THEN 'Achievement oriented'
        WHEN (ups.GoldBadges + ups.SilverBadges + ups.BronzeBadges) > 5 THEN 'Regular achiever'
        ELSE 'Occasional achiever'
    END as BadgeAchievementStyle,
    CASE 
        WHEN ups.TotalQuestionScore > 1000 THEN 'High scoring questioner'
        WHEN ups.TotalQuestionScore > 100 THEN 'Moderate scoring questioner'
        ELSE 'Low scoring questioner'
    END as QuestioningStyle,
    CASE 
        WHEN ups.TotalAnswerScore > 1000 THEN 'High scoring answerer'
        WHEN ups.TotalAnswerScore > 100 THEN 'Moderate scoring answerer'
        ELSE 'Low scoring answerer'
    END as AnsweringStyle,
    (SELECT COUNT(*) FROM Posts p 
     WHERE p.OwnerUserId = u.Id AND p.CreationDate >= DATEADD(day, -7, GETDATE())) as RecentPostsLast7Days,
    (SELECT COUNT(*) FROM Posts p 
     WHERE p.OwnerUserId = u.Id AND p.CreationDate >= DATEADD(day, -30, GETDATE())) as RecentPostsLast30Days,
    (SELECT COUNT(*) FROM Posts p 
     WHERE p.OwnerUserId = u.Id AND p.CreationDate >= DATEADD(month, -3, GETDATE())) as RecentPostsLast3Months,
    (SELECT COUNT(*) FROM Posts p 
     WHERE p.OwnerUserId = u.Id AND p.CreationDate >= DATEADD(year, -1, GETDATE())) as RecentPostsLastYear,
    (SELECT COUNT(*) FROM Votes v 
     WHERE v.UserId = u.Id AND v.CreationDate >= DATEADD(day, -7, GETDATE())) as RecentVotesLast7Days,
    (SELECT COUNT(*) FROM Votes v 
     WHERE v.UserId = u.Id AND v.CreationDate >= DATEADD(day, -30, GETDATE())) as RecentVotesLast30Days,
    (SELECT COUNT(*) FROM Votes v 
     WHERE v.UserId = u.Id AND v.CreationDate >= DATEADD(month, -3, GETDATE())) as RecentVotesLast3Months,
    (SELECT COUNT(*) FROM Comments c 
     WHERE c.UserId = u.Id AND c.CreationDate >= DATEADD(day, -7, GETDATE())) as RecentCommentsLast7Days,
    (SELECT COUNT(*) FROM Comments c 
     WHERE c.UserId = u.Id AND c.CreationDate >= DATEADD(day, -30, GETDATE())) as RecentCommentsLast30Days,
    (SELECT AVG(v.BountyAmount) FROM Votes v 
     WHERE v.UserId = u.Id AND v.BountyAmount IS NOT NULL) as AvgBountyAmount,
    (SELECT MAX(v.BountyAmount) FROM Votes v 
     WHERE v.UserId = u.Id AND v.BountyAmount IS NOT NULL) as MaxBountyAmount,
    (SELECT COUNT(*) FROM Tags t 
     WHERE t.Count > 100 AND t.TagName IN (
         SELECT TRIM(value) 
         FROM STRING_SPLIT(
             (SELECT STRING_AGG(p.Tags, ' ') FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1), 
             '<'
         ) 
         WHERE value LIKE '%>%'
     )) as PopularTagCount,
    (SELECT TOP 1 
        CASE 
            WHEN t.Count > 100 THEN t.TagName
            ELSE NULL
        END 
    FROM Tags t 
    WHERE t.Count IN (
        SELECT TOP 5 MAX(t2.Count) 
        FROM Tags t2 
        WHERE t2.TagName IN (
            SELECT TRIM(value) 
            FROM STRING_SPLIT(
                (SELECT STRING_AGG(p.Tags, ' ') FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1), 
                '<'
            ) 
            WHERE value LIKE '%>%'
        )
        GROUP BY t2.TagName
    )
    ORDER BY t.Count DESC) as TopTag,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.Tags IS NOT NULL AND p.Tags LIKE '%<%') THEN 'Uses Tagging'
        ELSE 'Does Not Use Tagging'
    END as TaggingUsage,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.Body LIKE '%code%') THEN 'Code Focused'
        ELSE 'Text Focused'
    END as ContentFocus,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.Tags IS NOT NULL AND p.Tags LIKE '%discussion%') THEN 'Discussion Focused'
        ELSE 'Not Discussion Focused'
    END as DiscussionFocus,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.Tags IS NOT NULL AND p.Tags LIKE '%help%') THEN 'Help Focused'
        ELSE 'Not Help Focused'
    END as HelpFocus,
    (SELECT AVG(p.ViewCount) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) as AvgQuestionViews,
    (SELECT AVG(p.ViewCount) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) as AvgAnswerViews,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) as AvgQuestionScore,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) as AvgAnswerScore,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.ViewCount > 100) as PopularQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2 AND p.ViewCount > 100) as PopularAnswers,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.CommentCount > 5) as HighlyCommentedQuestions,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2 AND p.CommentCount > 5) as HighlyCommentedAnswers,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.AnswerCount > 10) as QuestionsWithManyAnswers,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2 AND p.Score > 100) as HighScoreAnswers,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Score > 100) as HighScoreQuestions
FROM Users u
INNER JOIN UserPostStats ups ON u.Id = ups.UserId
LEFT JOIN QuestionStats q ON u.Id = q.OwnerUserId
LEFT JOIN AnswerStats a ON u.Id = a.OwnerUserId
WHERE u.Id IS NOT NULL
    AND u.Reputation > 0
    AND ups.TotalPosts > 0
    AND ups.DaysActive > 0
ORDER BY u.Reputation DESC, ups.TotalPosts DESC, ups.TotalQuestionScore DESC, ups.TotalAnswerScore DESC;