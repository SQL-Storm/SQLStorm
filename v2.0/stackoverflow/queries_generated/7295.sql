-- {"query": "7295.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2839} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        STRING_AGG(DISTINCT p.Title, ' | ') AS PostTitles,
        STRING_AGG(DISTINCT t.TagName, ', ') AS TagsUsed,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id END) AS PositiveScorePosts,
        COUNT(DISTINCT CASE WHEN p.Score < 0 THEN p.Id END) AS NegativeScorePosts,
        COUNT(DISTINCT CASE WHEN p.Score = 0 THEN p.Id END) AS ZeroScorePosts,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN (COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id END) * 100.0) / COUNT(DISTINCT p.Id)
            ELSE 0 
        END AS PositiveScorePercentage,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswers,
        AVG(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN (p.Score - COALESCE((SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2), 0)) END) AS AvgScoreDiffWithAcceptedAnswer
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p2 ON p.Id = p2.ParentId AND p2.PostTypeId = 2
    LEFT JOIN (
        SELECT DISTINCT PostId, TagName 
        FROM Posts p
        JOIN LATERAL (
            SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS TagName 
            WHERE p.Tags IS NOT NULL
        ) AS t ON TRUE
        WHERE p.PostTypeId = 1
    ) AS t ON p.Id = t.PostId
    WHERE u.CreationDate >= '2010-01-01 00:00:00'
      AND u.Id IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE CreationDate >= '2010-01-01 00:00:00')
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        ua.*,
        ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC, ua.PostCount DESC) AS ReputationRank,
        ROW_NUMBER() OVER (ORDER BY ua.PostCount DESC, ua.Reputation DESC) AS ActivityRank,
        NTILE(5) OVER (ORDER BY ua.Reputation DESC) AS ReputationQuintile
    FROM UserActivity ua
    WHERE ua.PostCount >= 50
),
PostStats AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        COALESCE(p.Tags, 'No Tags') AS TagsOrDefault,
        CASE 
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 1 THEN 'Question'
            ELSE 'Other'
        END AS PostTypeDescription,
        COALESCE((SELECT AVG(Score) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2), 0) AS AvgAnswerScore,
        (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2 AND Score > 0) AS PositiveAnswers,
        (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2 AND Score < 0) AS NegativeAnswers,
        (SELECT COUNT(*) FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2 AND Score = 0) AS ZeroScoreAnswers,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId IN (2,3)) AS TotalVotes,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(*) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 3) AS DownVotes,
        EXISTS(SELECT 1 FROM Posts WHERE ParentId = p.Id AND PostTypeId = 2 AND Score > 5) AS HasHighScoringAnswer,
        EXISTS(SELECT 1 FROM Comments WHERE PostId = p.Id AND Score > 5) AS HasHighScoringComment,
        (p.CreationDate - LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate)) AS TimeSinceLastPost,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS ScoreRankWithinUser,
        PERCENT_RANK() OVER (ORDER BY p.Score) AS ScorePercentile,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = p.OwnerUserId AND p2.Score > p.Score) AS MorePopularPosts,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND OwnerUserId = p.OwnerUserId) THEN 'AboveAvg'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND OwnerUserId = p.OwnerUserId) THEN 'BelowAvg'
            ELSE 'Avg'
        END AS ScoreComparisonToUserAvg
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) 
      AND p.CreationDate >= '2020-01-01 00:00:00'
      AND COALESCE(p.ParentId, 0) > 0
),
UserPostComparison AS (
    SELECT 
        ut.UserId,
        ut.DisplayName,
        ut.Reputation,
        ut.PostCount,
        ut.QuestionCount,
        ut.AnswerCount,
        ut.PositiveScorePercentage,
        COUNT(DISTINCT ps.PostId) AS UserPostCount,
        AVG(ps.Score) AS AvgPostScore,
        AVG(ps.ViewCount) AS AvgViewCount,
        MAX(ps.CreationDate) AS LatestPost,
        STRING_AGG(DISTINCT ps.PostTypeDescription, ', ') AS PostTypes,
        MAX(CASE WHEN ps.PostTypeDescription = 'Question' THEN ps.PostCount ELSE 0 END) AS NumQuestions,
        MAX(CASE WHEN ps.PostTypeDescription = 'Answer' THEN ps.PostCount ELSE 0 END) AS NumAnswers,
        COUNT(DISTINCT ps.ParentId) AS UniqueQuestionsAnswered,
        SUM(CASE WHEN ps.Score > 0 THEN 1 ELSE 0 END) AS NumPositivePosts,
        SUM(CASE WHEN ps.Score < 0 THEN 1 ELSE 0 END) AS NumNegativePosts
    FROM TopUsers ut
    LEFT JOIN PostStats ps ON ut.UserId = ps.OwnerUserId
    WHERE (ps.PostTypeId = 1 OR ps.PostTypeId = 2) 
      AND ps.CreationDate >= '2020-01-01'
    GROUP BY ut.UserId, ut.DisplayName, ut.Reputation, ut.PostCount, ut.QuestionCount, ut.AnswerCount, ut.PositiveScorePercentage
)
SELECT 
    upc.*,
    CASE 
        WHEN upc.Reputation > 10000 THEN 'Elite'
        WHEN upc.Reputation > 5000 THEN 'Expert'
        WHEN upc.Reputation > 1000 THEN 'Advanced'
        ELSE 'Beginner'
    END AS ReputationTier,
    CASE 
        WHEN upc.UserPostCount > 100 THEN 'Highly Active'
        WHEN upc.UserPostCount > 50 THEN 'Active'
        WHEN upc.UserPostCount > 10 THEN 'Regular'
        ELSE 'Occasional'
    END AS ActivityLevel,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = upc.UserId AND PostTypeId = 1) AS QuestionPostsCount,
    (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = upc.UserId AND PostTypeId = 2) AS AnswerPostsCount,
    (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = upc.UserId AND PostTypeId = 1) AS AvgQuestionScore,
    (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = upc.UserId AND PostTypeId = 2) AS AvgAnswerScore,
    ROUND((upc.NumPositivePosts * 100.0 / NULLIF(upc.UserPostCount, 0)), 2) AS PositivePostRate,
    ROUND((upc.NumNegativePosts * 100.0 / NULLIF(upc.UserPostCount, 0)), 2) AS NegativePostRate,
    COALESCE(upc.NumQuestions, 0) + COALESCE(upc.NumAnswers, 0) AS TotalPosts,
    CASE 
        WHEN upc.UniqueQuestionsAnswered > 0 THEN 
            ROUND((upc.UserPostCount * 100.0 / NULLIF(upc.UniqueQuestionsAnswered, 0)), 2)
        ELSE NULL 
    END AS AnswerRate,
    CASE 
        WHEN upc.AnswerPostsCount > 0 THEN 
            ROUND((upc.NumPositivePosts * 100.0 / NULLIF(upc.AnswerPostsCount, 0)), 2)
        ELSE NULL 
    END AS AnswerPositiveRate,
    (
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = upc.UserId AND PostTypeId = 1 AND Score > 5)
        - 
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = upc.UserId AND PostTypeId = 1 AND Score <= 5)
    ) AS PositiveMinusNegativeQuestions,
    (
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = upc.UserId AND PostTypeId = 2 AND Score > 5)
        - 
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = upc.UserId AND PostTypeId = 2 AND Score <= 5)
    ) AS PositiveMinusNegativeAnswers,
    -- Complex calculated column with nested subqueries and CASE expressions
    CASE 
        WHEN upc.ReputationLevel > 8000 AND 
             upc.UserPostCount > 30 AND 
             upc.PositivePostRate > 70 AND 
             upc.AnswerRate > 50 
        THEN 'Top Performer'
        WHEN upc.ReputationLevel BETWEEN 2000 AND 8000 AND 
             upc.UserPostCount > 15 AND 
             upc.PositivePostRate > 40 AND 
             upc.AnswerRate > 30 
        THEN 'Active Contributor'
        WHEN upc.ReputationLevel BETWEEN 500 AND 2000 AND 
             upc.UserPostCount > 5 AND 
             upc.PositivePostRate > 30 
        THEN 'Regular Participant'
        ELSE 'New Participant'
    END AS PerformanceCategory,
    -- Window function analysis
    ROW_NUMBER() OVER (ORDER BY upc.UserPostCount DESC) AS UserRank,
    RANK() OVER (ORDER BY upc.AvgPostScore DESC) AS AvgScoreRank,
    DENSE_RANK() OVER (ORDER BY upc.Reputation DESC) AS ReputationRank,
    -- Set operator usage with UNION ALL
    (
        SELECT 'Post Type Distribution' UNION ALL
        SELECT 'Question Distribution' UNION ALL 
        SELECT 'Answer Distribution'
    ) AS ReportMetadata,
    -- String concatenation with complex expressions
    CONCAT(
        'User ', upc.DisplayName, ' (ID:', upc.UserId, ') ', 
        'with ', upc.UserPostCount, ' posts, ', 
        'avg score of ', ROUND(upc.AvgPostScore, 2), ', ', 
        'reputation ', upc.Reputation, ' (' , upc.ReputationTier, ')'
    ) AS UserProfileSummary
FROM UserPostComparison upc
INNER JOIN (
    SELECT 
        ut.UserId, 
        ut.DisplayName,
        ut.Reputation AS ReputationLevel,
        ut.PostCount AS TotalUserPosts,
        MAX(ut.ReputationRank) AS MaxReputationRank,
        MAX(ut.ActivityRank) AS MaxActivityRank
    FROM TopUsers ut
    WHERE ut.PostCount >= 30
    GROUP BY ut.UserId, ut.DisplayName, ut.Reputation, ut.PostCount
    HAVING COUNT(*) >= 1
) AS filtered_users 
ON upc.UserId = filtered_users.UserId
WHERE upc.UserPostCount > 0
  AND (upc.ReputationTier IN ('Elite', 'Expert') OR upc.UserRank <= 30)
ORDER BY upc.UserPostCount DESC, upc.Reputation DESC
LIMIT 50;