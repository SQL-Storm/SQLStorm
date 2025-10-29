-- {"query": "7786.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1917} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        SUM(COALESCE(p.Score, 0)) as TotalScore,
        AVG(COALESCE(p.Score, 0)) as AvgScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        LastPostDate,
        LastCommentDate,
        QuestionCount,
        AnswerCount,
        TotalScore,
        AvgScore,
        AllTags,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC) as ScoreRank,
        ROW_NUMBER() OVER (ORDER BY PostCount DESC) as PostRank,
        RANK() OVER (ORDER BY Reputation DESC) as RepRank
    FROM UserActivityStats
),
UserTagAnalysis AS (
    SELECT 
        t.UserId,
        t.TagName,
        t.Count as TagCount,
        AVG(t.Count) OVER (PARTITION BY t.UserId) as AvgTagCountPerUser,
        PERCENT_RANK() OVER (ORDER BY t.Count) as TagCountPercentile,
        CASE 
            WHEN t.Count > (SELECT AVG(Count) FROM Tags) THEN 'AboveAverage'
            WHEN t.Count < (SELECT AVG(Count) FROM Tags) THEN 'BelowAverage'
            ELSE 'Average'
        END as TagPerformance
    FROM (
        SELECT 
            u.Id as UserId,
            UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '<')) as TagName,
            COUNT(*) as Count
        FROM Users u
        JOIN Posts p ON u.Id = p.OwnerUserId
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags != ''
        GROUP BY u.Id, TagName
    ) t
)
SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.CommentCount,
    tu.BadgeCount,
    tu.LastPostDate,
    tu.LastCommentDate,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.TotalScore,
    tu.AvgScore,
    tu.AllTags,
    tu.ScoreRank,
    tu.PostRank,
    tu.RepRank,
    COALESCE(uta.TagName, 'No Tags') as MostActiveTag,
    COALESCE(uta.TagCount, 0) as TagActivityCount,
    CASE 
        WHEN uta.TagCount > uta.AvgTagCountPerUser THEN 'Highly Active'
        WHEN uta.TagCount < uta.AvgTagCountPerUser THEN 'Less Active'
        ELSE 'Average Activity'
    END as ActivityLevel,
    uta.TagCountPercentile,
    uta.TagPerformance,
    CASE 
        WHEN tu.Reputation > 10000 AND tu.PostCount > 100 THEN 'Elite Contributor'
        WHEN tu.Reputation > 5000 AND tu.QuestionCount > 50 THEN 'Active Contributor'
        WHEN tu.PostCount > 50 THEN 'Regular Participant'
        ELSE 'Occasional Participant'
    END as ParticipantLevel,
    CASE 
        WHEN tu.BadgeCount > 50 THEN 'Award Winning'
        WHEN tu.BadgeCount > 25 THEN 'Well Recognized'
        WHEN tu.BadgeCount > 10 THEN 'Recognized'
        ELSE 'Newcomer'
    END as RecognitionLevel,
    (tu.TotalScore - LAG(tu.TotalScore) OVER (ORDER BY tu.ScoreRank)) as ScoreDifferenceFromPrevious,
    LAG(tu.DisplayName) OVER (ORDER BY tu.ScoreRank) as PreviousTopScorer,
    (SELECT COUNT(*) FROM Users u2 WHERE u2.Reputation > tu.Reputation) as RepRankingAbove,
    (SELECT COUNT(*) FROM TopUsers tu2 WHERE tu2.ScoreRank < tu.ScoreRank) as UsersAboveInScoreRank,
    DENSE_RANK() OVER (ORDER BY tu.Reputation) as ReputationRank,
    NTILE(4) OVER (ORDER BY tu.Reputation) as ReputationQuartile,
    CONCAT('User #', tu.UserId, ': ', tu.DisplayName) as UserIdentifier,
    CASE 
        WHEN tu.LastPostDate >= CURRENT_TIMESTAMP - INTERVAL '30 days' THEN 'Active Last Month'
        WHEN tu.LastPostDate >= CURRENT_TIMESTAMP - INTERVAL '90 days' THEN 'Active Last Quarter'
        WHEN tu.LastPostDate >= CURRENT_TIMESTAMP - INTERVAL '1 year' THEN 'Active Last Year'
        ELSE 'Inactive'
    END as ActivityStatus,
    ROUND((tu.QuestionCount * 100.0 / NULLIF(tu.PostCount, 0)), 2) as QuestionPercentage,
    ROUND((tu.AnswerCount * 100.0 / NULLIF(tu.PostCount, 0)), 2) as AnswerPercentage,
    CASE 
        WHEN tu.PostCount > 0 THEN (tu.AnswerCount * 100.0 / tu.PostCount)
        ELSE 0
    END as AnswerToPostRatio,
    (tu.BadgeCount * 1.0 / NULLIF(tu.PostCount, 0)) as BadgePerPostRatio,
    NULLIF(STRING_AGG(DISTINCT uta.TagName, ', '), '') as TagList,
    COUNT(*) OVER () as TotalUsersInAnalysis,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = tu.UserId AND p2.PostTypeId = 1) as QuestionCountForUser,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = tu.UserId AND p3.PostTypeId = 2) as AnswerCountForUser,
    (SELECT SUM(p4.Score) FROM Posts p4 WHERE p4.OwnerUserId = tu.UserId AND p4.PostTypeId = 1) as TotalQuestionScore,
    (SELECT SUM(p5.Score) FROM Posts p5 WHERE p5.OwnerUserId = tu.UserId AND p5.PostTypeId = 2) as TotalAnswerScore,
    CASE 
        WHEN tu.QuestionCount > 0 THEN (tu.AnswerCount * 1.0 / tu.QuestionCount)
        ELSE NULL
    END as AnswerToQuestionRatio,
    COALESCE(
        (SELECT STRING_AGG(DISTINCT SUBSTRING(ut2.Tags, 2, LENGTH(ut2.Tags)-2), ', ') 
         FROM Posts ut2 
         WHERE ut2.OwnerUserId = tu.UserId 
         AND ut2.PostTypeId = 1 
         AND ut2.Tags IS NOT NULL 
         AND ut2.Tags != ''), 
        ''
    ) as UserQuestionTags,
    (SELECT COUNT(*) FROM Posts p6 WHERE p6.OwnerUserId = tu.UserId AND p6.Score = (SELECT MAX(p7.Score) FROM Posts p7 WHERE p7.OwnerUserId = tu.UserId)) as PostsWithMaxScore,
    (SELECT COUNT(*) FROM Posts p8 WHERE p8.OwnerUserId = tu.UserId AND p8.CreationDate <= CURRENT_TIMESTAMP - INTERVAL '1 year') as OldPostsCount,
    (CASE WHEN tu.PostCount > 0 THEN 
        (SELECT AVG(p9.Score) FROM Posts p9 WHERE p9.OwnerUserId = tu.UserId AND p9.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '30 days')
     ELSE NULL END) as AvgScoreLast30Days
FROM TopUsers tu
LEFT JOIN (
    SELECT 
        UserId,
        TagName,
        TagCount,
        AvgTagCountPerUser,
        TagCountPercentile,
        TagPerformance,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagCount DESC) as rn
    FROM UserTagAnalysis
) uta ON tu.UserId = uta.UserId AND uta.rn = 1
WHERE tu.RepRank <= 100
  AND (uta.TagName IS NULL OR uta.TagName NOT IN ('javascript', 'python', 'java', 'c++'))
  AND (tu.Reputation > 1000 OR tu.PostCount > 10 OR tu.BadgeCount > 5)
  AND (tu.ScoreRank <= 50 OR tu.PostRank <= 50 OR tu.RepRank <= 30)
ORDER BY tu.ScoreRank, tu.RepRank, tu.PostCount DESC
LIMIT 100;