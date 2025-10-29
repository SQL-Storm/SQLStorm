-- {"query": "7333.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2510} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Expert'
            WHEN u.Reputation >= 100 THEN 'Novice'
            ELSE 'Beginner'
        END as ReputationTier,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        PERCENT_RANK() OVER (ORDER BY u.Reputation) as ReputationPercentile,
        AVG(p.Score) OVER (PARTITION BY u.Id) as AvgPostScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsersWithBadges AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.PostCount,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.BadgeCount,
        uas.ReputationTier,
        uas.ReputationRank,
        uas.ReputationPercentile,
        uas.AvgPostScore,
        ROW_NUMBER() OVER (PARTITION BY uas.ReputationTier ORDER BY uas.BadgeCount DESC) as TierBadgeRank,
        CASE 
            WHEN uas.BadgeCount >= 50 THEN 'Veteran'
            WHEN uas.BadgeCount >= 25 THEN 'Experienced'
            WHEN uas.BadgeCount >= 10 THEN 'Intermediate'
            ELSE 'Newbie'
        END as BadgeSeniority
    FROM UserActivityStats uas
    WHERE uas.PostCount > 0
),
ComplexPostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NULL THEN 'Unanswered'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostStatus,
        CASE 
            WHEN p.Score >= 100 THEN 'Popular'
            WHEN p.Score >= 10 THEN 'Moderate'
            WHEN p.Score >= 0 THEN 'Low'
            ELSE 'Negative'
        END as PopularityLevel,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0),
            0
        ) as PositiveComments,
        COALESCE(
            (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1, 4, 5)),
            p.CreationDate
        ) as LastEditDate,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2),
            0
        ) as UpvoteCount,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3),
            0
        ) as DownvoteCount,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                ARRAY_LENGTH(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'), 1)
            ELSE 0
        END as TagCount,
        (p.Score * COALESCE(p.ViewCount, 0)) / NULLIF(p.AnswerCount + 1, 0) as ScorePerViewRatio
    FROM Posts p
    WHERE p.Id IS NOT NULL
),
ComprehensiveUserAnalysis AS (
    SELECT 
        tuwb.UserId,
        tuwb.DisplayName,
        tuwb.Reputation,
        tuwb.PostCount,
        tuwb.QuestionCount,
        tuwb.AnswerCount,
        tuwb.BadgeCount,
        tuwb.ReputationTier,
        tuwb.ReputationRank,
        tuwb.ReputationPercentile,
        tuwb.BadgeSeniority,
        tuwb.TierBadgeRank,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = tuwb.UserId AND p.PostTypeId = 1) as UserQuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = tuwb.UserId AND p.PostTypeId = 2) as UserAnswerCount,
        (SELECT AVG(Score) FROM Posts p WHERE p.OwnerUserId = tuwb.UserId AND p.PostTypeId = 1) as UserAvgQuestionScore,
        COALESCE(
            (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = tuwb.UserId AND p.PostTypeId = 2),
            0
        ) as UserAvgAnswerScore
    FROM TopUsersWithBadges tuwb
    WHERE tuwb.UserId IS NOT NULL
),
FinalUserAnalysis AS (
    SELECT 
        cua.UserId,
        cua.DisplayName,
        cua.Reputation,
        cua.PostCount,
        cua.QuestionCount,
        cua.AnswerCount,
        cua.BadgeCount,
        cua.ReputationTier,
        cua.ReputationRank,
        cua.ReputationPercentile,
        cua.BadgeSeniority,
        cua.UserQuestionCount,
        cua.UserAnswerCount,
        cua.UserAvgQuestionScore,
        cua.UserAvgAnswerScore,
        CASE 
            WHEN cua.UserQuestionCount > 0 AND cua.UserAvgQuestionScore > 0 THEN 
                (cua.UserAnswerCount * 1.0 / cua.UserQuestionCount)
            ELSE 0
        END as AnswerToQuestionRatio,
        CASE 
            WHEN cua.UserAvgQuestionScore IS NOT NULL THEN 
                CASE 
                    WHEN cua.UserAvgQuestionScore >= 10 THEN 'High Value'
                    WHEN cua.UserAvgQuestionScore >= 5 THEN 'Medium Value'
                    WHEN cua.UserAvgQuestionScore >= 1 THEN 'Low Value'
                    ELSE 'Minimal Value'
                END
            ELSE 'No Questions'
        END as QuestionValueLevel,
        COUNT(*) OVER () as TotalUsers,
        RANK() OVER (ORDER BY cua.Reputation DESC) as OverallRank
    FROM ComprehensiveUserAnalysis cua
)
SELECT 
    fua.UserId,
    fua.DisplayName,
    fua.Reputation,
    fua.PostCount,
    fua.QuestionCount,
    fua.AnswerCount,
    fua.BadgeCount,
    fua.ReputationTier,
    fua.ReputationRank,
    fua.ReputationPercentile,
    fua.BadgeSeniority,
    fua.UserQuestionCount,
    fua.UserAnswerCount,
    fua.UserAvgQuestionScore,
    fua.UserAvgAnswerScore,
    fua.AnswerToQuestionRatio,
    fua.QuestionValueLevel,
    fua.TotalUsers,
    fua.OverallRank,
    CASE 
        WHEN fua.Reputation >= 10000 AND fua.BadgeCount >= 50 THEN 'Hall of Fame'
        WHEN fua.Reputation >= 5000 AND fua.BadgeCount >= 25 THEN 'Milestone'
        WHEN fua.Reputation >= 1000 AND fua.BadgeCount >= 10 THEN 'Achiever'
        ELSE 'Contributor'
    END as RecognitionLevel,
    ROW_NUMBER() OVER (ORDER BY fua.Reputation DESC) as RankByReputation,
    NTILE(10) OVER (ORDER BY fua.Reputation) as DecileRank,
    LAG(fua.Reputation, 1) OVER (ORDER BY fua.Reputation DESC) - fua.Reputation as ReputationDifferenceFromNext,
    CASE 
        WHEN fua.UserAvgQuestionScore IS NOT NULL AND fua.UserAvgAnswerScore IS NOT NULL THEN
            fua.UserAvgQuestionScore + fua.UserAvgAnswerScore
        ELSE 0
    END as CombinedAvgScore,
    fua.UserQuestionCount * 100.0 / NULLIF(fua.TotalUsers, 0) as QuestionPercentageOfAllUsers,
    CAST((fua.PostCount * 100.0 / fua.TotalUsers) AS DECIMAL(5,2)) as PostPercentageOfAllUsers,
    CASE 
        WHEN fua.Reputation > (SELECT AVG(Reputation) FROM Users WHERE Reputation IS NOT NULL) THEN 'Above Average'
        WHEN fua.Reputation < (SELECT AVG(Reputation) FROM Users WHERE Reputation IS NOT NULL) THEN 'Below Average'
        ELSE 'Average'
    END as ReputationComparisonToAverage,
    fua.AnswerToQuestionRatio > 1.5 as IsHighAnswerActivity,
    CAST(NULLIF(fua.UserAvgQuestionScore, 0) AS FLOAT) / NULLIF(fua.UserAvgAnswerScore, 0) as ScoreRatioIfBothExist,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = fua.UserId AND p.CreationDate >= '2020-01-01'),
        0
    ) as RecentPostsCount,
    COALESCE(
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = fua.UserId AND b.Date >= '2020-01-01'),
        0
    ) as RecentBadgesCount,
    CASE 
        WHEN fua.Reputation >= 10000 AND fua.QuestionCount >= 100 THEN 'Elite Questioner'
        WHEN fua.Reputation >= 1000 AND fua.QuestionCount >= 50 THEN 'Active Questioner'
        WHEN fua.Reputation >= 100 AND fua.QuestionCount >= 10 THEN 'Regular Questioner'
        ELSE 'Occasional Questioner'
    END as QuestionerStatus,
    CASE 
        WHEN fua.Reputation >= 10000 AND fua.AnswerCount >= 500 THEN 'Elite Answerer'
        WHEN fua.Reputation >= 1000 AND fua.AnswerCount >= 250 THEN 'Active Answerer'
        WHEN fua.Reputation >= 100 AND fua.AnswerCount >= 50 THEN 'Regular Answerer'
        ELSE 'Occasional Answerer'
    END as AnswererStatus,
    CASE 
        WHEN fua.BadgeCount >= 100 THEN 'Veteran Badge Holder'
        WHEN fua.BadgeCount >= 50 THEN 'Experienced Badge Holder'
        WHEN fua.BadgeCount >= 25 THEN 'Intermediate Badge Holder'
        ELSE 'New Badge Holder'
    END as BadgeStatus,
    (fua.PostCount * 100) / NULLIF(fua.TotalUsers, 0) as ActivityLevel
FROM FinalUserAnalysis fua
WHERE fua.UserId IS NOT NULL
ORDER BY fua.Reputation DESC
LIMIT 500;