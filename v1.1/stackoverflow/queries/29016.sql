WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags)-2)), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate >= TIMESTAMP '2010-01-01'
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
TopUsers AS (
    SELECT 
        UserId,
        Reputation,
        DisplayName,
        PostCount,
        BadgeCount,
        CommentCount,
        VoteCount,
        AvgPostScore,
        LastPostDate,
        AllTags,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) as RankByReputation,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC) as RankByPostCount,
        ROW_NUMBER() OVER (ORDER BY BadgeCount DESC) as RankByBadgeCount
    FROM UserStats
),
UserActivity AS (
    SELECT 
        tu.UserId,
        tu.Reputation,
        tu.DisplayName,
        tu.PostCount,
        tu.BadgeCount,
        tu.CommentCount,
        tu.VoteCount,
        tu.AvgPostScore,
        tu.LastPostDate,
        tu.AllTags,
        tu.RankByReputation,
        tu.RankByPostCount,
        tu.RankByBadgeCount,
        CASE 
            WHEN tu.Reputation >= 100000 THEN 'Grandmaster'
            WHEN tu.Reputation >= 50000 THEN 'Master'
            WHEN tu.Reputation >= 10000 THEN 'Expert'
            WHEN tu.Reputation >= 1000 THEN 'Intermediate'
            WHEN tu.Reputation >= 100 THEN 'Beginner'
            ELSE 'Newbie'
        END as ReputationTier,
        CASE 
            WHEN tu.PostCount > 1000 AND tu.BadgeCount > 100 THEN 'Elite'
            WHEN tu.PostCount > 500 AND tu.BadgeCount > 50 THEN 'Pro'
            WHEN tu.PostCount > 100 THEN 'Regular'
            ELSE 'Casual'
        END as ActivityLevel,
        CAST(
          (EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - tu.LastPostDate)) / 86400)
          AS INTEGER
        ) as DaysSinceLastPost,
        COALESCE((SELECT COUNT(*) FROM Posts WHERE OwnerUserId = tu.UserId AND PostTypeId = 1), 0) as QuestionCount,
        COALESCE((SELECT COUNT(*) FROM Posts WHERE OwnerUserId = tu.UserId AND PostTypeId = 2), 0) as AnswerCount
    FROM TopUsers tu
    GROUP BY
        tu.UserId, tu.Reputation, tu.DisplayName, tu.PostCount, tu.BadgeCount, tu.CommentCount, tu.VoteCount,
        tu.AvgPostScore, tu.LastPostDate, tu.AllTags, tu.RankByReputation, tu.RankByPostCount, tu.RankByBadgeCount
),
ComplexQueryResults AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        ua.DisplayName,
        ua.PostCount,
        ua.BadgeCount,
        ua.CommentCount,
        ua.VoteCount,
        ua.AvgPostScore,
        ua.LastPostDate,
        ua.AllTags,
        ua.RankByReputation,
        ua.RankByPostCount,
        ua.RankByBadgeCount,
        ua.ReputationTier,
        ua.ActivityLevel,
        ua.DaysSinceLastPost,
        ua.QuestionCount,
        ua.AnswerCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.Score > 100) as HighScorePosts,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.CommentCount > 50) as HighlyCommentedPosts,
        (SELECT STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags)-2)), ', ') 
         FROM Posts p 
         WHERE p.OwnerUserId = ua.UserId AND p.PostTypeId = 1) as QuestionTags,
        (SELECT COUNT(DISTINCT ph.PostId) 
         FROM PostHistory ph 
         WHERE ph.UserId = ua.UserId AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)) as EditCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.ViewCount > 10000) as PopularPosts,
        CASE 
            WHEN ua.ReputationTier = 'Grandmaster' AND ua.PostCount > 1000 AND ua.BadgeCount > 100 THEN 'Supreme Contributor'
            WHEN ua.ReputationTier = 'Master' AND ua.PostCount > 500 THEN 'Veteran Contributor'
            WHEN ua.ReputationTier = 'Expert' AND ua.PostCount > 100 THEN 'Experienced Contributor'
            ELSE 'Regular Contributor'
        END as ContributionLevel,
        ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC, ua.PostCount DESC) as OverallRank,
        PERCENT_RANK() OVER (ORDER BY ua.Reputation) as ReputationPercentile,
        AVG(ua.Reputation) OVER (ORDER BY ua.Reputation ROWS BETWEEN 5 PRECEDING AND 5 FOLLOWING) as ReputationMA,
        LAG(ua.Reputation, 1) OVER (ORDER BY ua.Reputation DESC) as PrevReputation,
        LEAD(ua.Reputation, 1) OVER (ORDER BY ua.Reputation DESC) as NextReputation,
        CASE 
            WHEN ua.DaysSinceLastPost IS NULL THEN 'No Posts'
            WHEN ua.DaysSinceLastPost > 365 THEN 'Inactive'
            WHEN ua.DaysSinceLastPost > 30 THEN 'Inactive (Monthly)'
            WHEN ua.DaysSinceLastPost > 7 THEN 'Inactive (Weekly)'
            ELSE 'Active'
        END as UserStatus,
        CASE 
            WHEN ua.QuestionCount > 0 THEN CAST(ua.AnswerCount AS DOUBLE PRECISION) / CAST(ua.QuestionCount AS DOUBLE PRECISION)
            ELSE NULL 
        END as AnswerToQuestionRatio,
        (ua.PostCount + ua.BadgeCount + ua.CommentCount + ua.VoteCount) as TotalActivityScore,
        CASE 
            WHEN ua.Reputation > 100000 THEN 'Very High'
            WHEN ua.Reputation > 10000 THEN 'High'
            WHEN ua.Reputation > 1000 THEN 'Medium'
            ELSE 'Low'
        END as ReputationCategory,
        CASE 
            WHEN ua.AllTags IS NOT NULL AND LENGTH(ua.AllTags) > 0 
            THEN LENGTH(ua.AllTags) - LENGTH(REPLACE(ua.AllTags, ',', '')) + 1
            ELSE 0 
        END as TagCount,
        COALESCE((SELECT COUNT(*) FROM PostHistory ph 
                  WHERE ph.UserId = ua.UserId AND ph.PostHistoryTypeId = 10), 0) as CloseVotes,
        (ua.VoteCount - COALESCE((SELECT COUNT(*) FROM Votes v WHERE v.UserId = ua.UserId AND v.VoteTypeId IN (1, 2, 3)), 0)) as NetVotes,
        ABS(ua.PostCount - COALESCE((SELECT AVG(PostCount) FROM UserActivity), 0)) as PostCountDeviation,
        CASE 
            WHEN ua.BadgeCount > 100 AND ua.Reputation > 50000 THEN 'Award Winning'
            WHEN ua.BadgeCount > 50 THEN 'Achievement Focused'
            WHEN ua.QuestionCount > 100 THEN 'Question Master'
            WHEN ua.AnswerCount > 100 THEN 'Answer Expert'
            ELSE 'Regular Member'
        END as UserType,
        (SELECT COUNT(DISTINCT p.Id) 
         FROM Posts p 
         WHERE p.OwnerUserId = ua.UserId 
         AND EXISTS (SELECT 1 FROM Comments c WHERE c.PostId = p.Id AND c.UserId = ua.UserId)) as SelfCommentedPosts,
        (SELECT COUNT(DISTINCT p.Id) 
         FROM Posts p 
         WHERE p.OwnerUserId = ua.UserId 
         AND EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.UserId = ua.UserId)) as EditedPosts
    FROM UserActivity ua
    GROUP BY
        ua.UserId, ua.Reputation, ua.DisplayName, ua.PostCount, ua.BadgeCount, ua.CommentCount, ua.VoteCount,
        ua.AvgPostScore, ua.LastPostDate, ua.AllTags, ua.RankByReputation, ua.RankByPostCount, ua.RankByBadgeCount,
        ua.ReputationTier, ua.ActivityLevel, ua.DaysSinceLastPost, ua.QuestionCount, ua.AnswerCount
)
SELECT 
    UserId,
    Reputation,
    DisplayName,
    PostCount,
    BadgeCount,
    CommentCount,
    VoteCount,
    AvgPostScore,
    LastPostDate,
    AllTags,
    RankByReputation,
    RankByPostCount,
    RankByBadgeCount,
    ReputationTier,
    ActivityLevel,
    DaysSinceLastPost,
    QuestionCount,
    AnswerCount,
    HighScorePosts,
    HighlyCommentedPosts,
    QuestionTags,
    EditCount,
    PopularPosts,
    ContributionLevel,
    OverallRank,
    ReputationPercentile,
    ReputationMA,
    PrevReputation,
    NextReputation,
    UserStatus,
    AnswerToQuestionRatio,
    TotalActivityScore,
    ReputationCategory,
    TagCount,
    CloseVotes,
    NetVotes,
    PostCountDeviation,
    UserType,
    SelfCommentedPosts,
    EditedPosts
FROM ComplexQueryResults
WHERE Reputation > 10000
  AND PostCount > 100
  AND (ReputationTier = 'Master' OR ReputationTier = 'Grandmaster')
  AND (ActivityLevel = 'Elite' OR ActivityLevel = 'Pro')
  AND DaysSinceLastPost <= 365
  AND ContributionLevel IN ('Veteran Contributor', 'Supreme Contributor')
  AND OverallRank <= 1000
  AND (HighScorePosts >= 5 OR PopularPosts >= 10 OR CloseVotes >= 5)
  AND NOT (ReputationPercentile BETWEEN 0.1 AND 0.2)
ORDER BY Reputation DESC, PostCount DESC, OverallRank ASC
LIMIT 500;