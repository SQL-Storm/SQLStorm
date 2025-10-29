-- {"query": "7750.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3296} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as UpvotesReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as DownvotesReceived,
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF(day, u.CreationDate, GETDATE()) as AccountAgeDays,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostActivityRank,
        AVG(CAST(p.Score AS FLOAT)) as AvgPostScore,
        STRING_AGG(CASE WHEN p.PostTypeId = 1 THEN p.Title ELSE NULL END, '; ') as QuestionTitles
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount, u.UpVotes, u.DownVotes, u.CreationDate
),
TopQuestions AS (
    SELECT 
        p.Id as QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.Tags,
        STRING_AGG(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE NULL END, '') as UpvoteCounts,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as UpvoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as DownvoteCount,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) as AnswerCountWithDeleted,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2 AND a.DeletedDate IS NULL) as AnswerCountActive,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCountForQuestion,
        DATEDIFF(day, p.CreationDate, GETDATE()) as DaysSinceCreation,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END as Status
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 1 
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.CreationDate, p.OwnerUserId, u.DisplayName, p.Tags, p.ClosedDate
),
UserBadgesWithRanking AS (
    SELECT 
        b.UserId,
        b.Name as BadgeName,
        b.Date,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) as BadgeRank,
        COUNT(*) OVER (PARTITION BY b.UserId) as TotalBadges,
        CASE 
            WHEN b.Class = 1 THEN 'Gold'
            WHEN b.Class = 2 THEN 'Silver'
            WHEN b.Class = 3 THEN 'Bronze'
            ELSE 'Unknown'
        END as BadgeTier,
        DENSE_RANK() OVER (ORDER BY b.Class, b.Date) as BadgeSequence
    FROM Badges b
    WHERE b.TagBased = 0
),
TagPerformance AS (
    SELECT 
        t.TagName,
        t.Count as TagUsageCount,
        t.ExcerptPostId,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' + t.TagName + '%') as RelatedPostCount,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' + t.TagName + '%') as AvgScoreForTag,
        (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.Tags LIKE '%' + t.TagName + '%') as LastUsedTagDate,
        CASE 
            WHEN t.Count > 500 THEN 'High'
            WHEN t.Count > 100 THEN 'Medium'
            WHEN t.Count > 10 THEN 'Low'
            ELSE 'Very Low'
        END as UsageLevel
    FROM Tags t
    WHERE t.TagName IS NOT NULL AND t.TagName != ''
),
RecentActivity AS (
    SELECT 
        p.Id,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        DATEDIFF(day, p.CreationDate, GETDATE()) as DaysOld
    FROM Posts p
    WHERE p.CreationDate >= DATEADD(day, -30, GETDATE())
),
TagBasedBadges AS (
    SELECT 
        b.UserId,
        b.Name as BadgeName,
        b.Date as BadgeDate,
        t.TagName,
        ROW_NUMBER() OVER (PARTITION BY b.UserId, t.TagName ORDER BY b.Date DESC) as BadgeRowNumber
    FROM Badges b
    JOIN Tags t ON b.Name = t.TagName
    WHERE b.TagBased = 1
),
ComplexAnalysis AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.PostCount,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.CommentCount,
        uas.BadgeCount,
        uas.UpvotesReceived,
        uas.DownvotesReceived,
        uas.AccountAgeDays,
        uas.ReputationRank,
        uas.PostActivityRank,
        uas.AvgPostScore,
        uas.QuestionTitles,
        COALESCE(tq.Title, 'No Top Questions') as TopQuestionTitle,
        COALESCE(tq.Score, 0) as TopQuestionScore,
        tq.AnswerCount as TopQuestionAnswerCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tq.QuestionId AND v.VoteTypeId IN (2,3)) as TotalVotesOnTopQuestion,
        (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = tq.QuestionId) as LastVoteOnTopQuestion,
        (SELECT AVG(DATEDIFF(day, p.CreationDate, p.LastActivityDate)) FROM Posts p WHERE p.ParentId = tq.QuestionId AND p.PostTypeId = 2) as AvgAnswerAge,
        CASE 
            WHEN (uas.PostCount * 1.0 / uas.AccountAgeDays) > 0.1 THEN 'High Activity'
            WHEN (uas.PostCount * 1.0 / uas.AccountAgeDays) > 0.05 THEN 'Moderate Activity'
            ELSE 'Low Activity'
        END as ActivityLevel,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = uas.UserId AND ph.PostHistoryTypeId = 1 AND ph.CreationDate >= DATEADD(DAY, -7, GETDATE())) as RecentEditsInLastWeek,
        (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.UserId = uas.UserId AND ph.PostHistoryTypeId IN (10, 11, 12) AND ph.CreationDate >= DATEADD(DAY, -30, GETDATE())) as RecentPostActionCount,
        (SELECT STRING_AGG(b.BadgeName, ', ') FROM UserBadgesWithRanking b WHERE b.UserId = uas.UserId AND b.BadgeRank <= 3) as Top3Badges,
        (SELECT COUNT(*) FROM UserBadgesWithRanking b WHERE b.UserId = uas.UserId AND b.Class = 1) as GoldBadgeCount,
        (SELECT COUNT(*) FROM UserBadgesWithRanking b WHERE b.UserId = uas.UserId AND b.Class = 2) as SilverBadgeCount,
        (SELECT COUNT(*) FROM UserBadgesWithRanking b WHERE b.UserId = uas.UserId AND b.Class = 3) as BronzeBadgeCount,
        CASE 
            WHEN uas.QuestionCount > 0 AND (uas.AnswerCount * 1.0 / uas.QuestionCount) > 2 THEN 'Active Helper'
            WHEN uas.QuestionCount > 0 AND (uas.AnswerCount * 1.0 / uas.QuestionCount) > 1 THEN 'Regular Contributor'
            ELSE 'Occasional Poster'
        END as ContributorType,
        COALESCE(
            (SELECT MAX(t.TagUsageCount) FROM TagPerformance t WHERE t.TagName IN (
                SELECT DISTINCT SUBSTRING(p.Tags, CHARINDEX('<', p.Tags) + 1, CHARINDEX('>', p.Tags, CHARINDEX('<', p.Tags)) - CHARINDEX('<', p.Tags) - 1)
                FROM Posts p
                WHERE p.OwnerUserId = uas.UserId AND p.Tags IS NOT NULL AND p.Tags != ''
            )), 0) as MaxTagUsage,
        (SELECT AVG(v.Score) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = uas.UserId) as AvgVoteScoreReceived,
        (SELECT STRING_AGG(CONCAT(ph.Comment, ': ', ph.Text), '; ') 
         FROM PostHistory ph 
         WHERE ph.UserId = uas.UserId 
         AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) 
         AND ph.CreationDate >= DATEADD(DAY, -14, GETDATE())
        ) as RecentEditComments,
        (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.UserId = uas.UserId AND ph.PostHistoryTypeId IN (10,11,12,13) AND DATEDIFF(DAY, ph.CreationDate, GETDATE()) <= 7) as RecentPostChanges,
        (SELECT TOP 1 t.UsageLevel FROM TagPerformance t 
         JOIN Posts p ON p.Tags LIKE '%' + t.TagName + '%'
         WHERE p.OwnerUserId = uas.UserId AND t.TagName IS NOT NULL
         ORDER BY t.Count DESC) as MostUsedTagLevel
    FROM UserActivityStats uas
    LEFT JOIN TopQuestions tq ON uas.QuestionCount > 0 AND tq.UpvoteCount = (SELECT MAX(UpvoteCount) FROM TopQuestions WHERE OwnerUserId = uas.UserId)
    WHERE uas.PostCount > 0
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.PostCount,
    ca.QuestionCount,
    ca.AnswerCount,
    ca.CommentCount,
    ca.BadgeCount,
    ca.UpvotesReceived,
    ca.DownvotesReceived,
    ca.ActivityLevel,
    ca.ContributorType,
    ca.TopQuestionTitle,
    ca.TopQuestionScore,
    ca.TopQuestionAnswerCount,
    ca.RecentEditsInLastWeek,
    ca.TotalVotesOnTopQuestion,
    ca.MaxTagUsage,
    ca.GoldBadgeCount,
    ca.SilverBadgeCount,
    ca.BronzeBadgeCount,
    ca.Top3Badges,
    (CASE WHEN ca.GoldBadgeCount > 0 THEN 'Gold Badge Holder' ELSE 'No Gold Badges' END) as GoldBadgeStatus,
    CASE WHEN ca.Reputation > 100000 THEN 'Elite' 
         WHEN ca.Reputation > 50000 THEN 'Veteran' 
         WHEN ca.Reputation > 10000 THEN 'Expert' 
         ELSE 'Newbie' END as ReputationTier,
    COALESCE(ca.MostUsedTagLevel, 'None') as TopTagUsageLevel,
    (SELECT COUNT(*) FROM TagBasedBadges tb WHERE tb.UserId = ca.UserId) as TagBasedBadgesCount,
    (SELECT TOP 1 tb.TagName FROM TagBasedBadges tb WHERE tb.UserId = ca.UserId ORDER BY tb.BadgeDate DESC) as LastTagBadgeTag,
    (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.UserId = ca.UserId AND ph.PostHistoryTypeId IN (10,11,12,13) AND DATEDIFF(DAY, ph.CreationDate, GETDATE()) <= 30) as RecentPostActions30Days,
    (SELECT MAX(rh.CreationDate) FROM PostHistory rh WHERE rh.UserId = ca.UserId) as LastActionDate,
    DATEDIFF(DAY, (SELECT MIN(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = ca.UserId), GETDATE()) as LifetimeActiveDays,
    -- Complex calculation with NULL handling
    ISNULL(ca.AvgPostScore * 1.0 / NULLIF(ca.PostCount, 0), 0) as ScorePerPostRatio,
    (SELECT STRING_AGG(CONCAT(u.DisplayName, '(', u.Id, ')'), ', ') 
     FROM Users u 
     WHERE u.Id IN (
         SELECT DISTINCT p.OwnerUserId 
         FROM Posts p 
         WHERE p.ParentId IN (
             SELECT Id FROM Posts WHERE OwnerUserId = ca.UserId AND PostTypeId = 1
         )
     )
    ) as QuestionsAskedByOthersOnUsersAnswers,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ca.UserId AND b.Class = 1 AND b.Date >= DATEADD(YEAR, -1, GETDATE())) as GoldBadgesLastYear,
    (SELECT STRING_AGG(CONCAT(t.TagName, ': ', t.Count), '; ') 
     FROM TagPerformance t 
     WHERE t.TagUsageCount > (SELECT AVG(TagUsageCount) FROM TagPerformance) * 1.5
    ) as AboveAverageTagUsage,
    CASE 
        WHEN ca.QuestionCount > 0 AND (ca.AnswerCount * 1.0 / ca.QuestionCount) > 3 THEN 'Overachiever'
        WHEN ca.QuestionCount > 0 AND (ca.AnswerCount * 1.0 / ca.QuestionCount) > 1 THEN 'Contributor'
        ELSE 'Supporter'
    END as CommunityRole,
    -- Window function with partition
    RANK() OVER (ORDER BY ca.Reputation DESC, ca.PostCount DESC) as OverallRank,
    -- Set operator equivalent with UNION ALL and filtering
    (SELECT COUNT(*) FROM (
        SELECT 1 FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.PostTypeId = 1
        UNION ALL
        SELECT 1 FROM Posts p WHERE p.OwnerUserId = ca.UserId AND p.PostTypeId = 2
    ) x) as TotalPostsAndAnswers
FROM ComplexAnalysis ca
WHERE ca.Reputation > 0
AND ca.PostCount > 0
AND (ca.Reputation > 1000 OR ca.BadgeCount > 5 OR ca.PostCount > 10 OR ca.QuestionCount > 0)
ORDER BY ca.Reputation DESC, ca.PostCount DESC, ca.ReputationRank ASC
OFFSET 0 ROWS
FETCH NEXT 10000 ROWS ONLY;