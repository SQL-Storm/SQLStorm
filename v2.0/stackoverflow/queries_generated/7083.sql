-- {"query": "7083.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1725} 
WITH UserStats AS (
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
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC) as ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000 AND u.Views > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        Views,
        PostCount,
        CommentCount,
        BadgeCount,
        ReputationRank,
        CASE 
            WHEN Reputation > 100000 THEN 'Elite'
            WHEN Reputation > 50000 THEN 'Expert'
            WHEN Reputation > 10000 THEN 'Advanced'
            WHEN Reputation > 1000 THEN 'Beginner'
            ELSE 'Newbie'
        END as ReputationLevel
    FROM UserStats
    WHERE ReputationRank <= 100
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
        CASE 
            WHEN p.Score > 10 THEN 'HighlyVoted'
            WHEN p.Score > 5 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'LowVoted'
            ELSE 'NoVotes'
        END as VoteCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as UserQuestionRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ViewCount > 100
),
AnswerStats AS (
    SELECT 
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        p.Body,
        CASE 
            WHEN p.Score > 10 THEN 'ExcellentAnswer'
            WHEN p.Score > 5 THEN 'GoodAnswer'
            WHEN p.Score > 0 THEN 'BasicAnswer'
            ELSE 'LowValueAnswer'
        END as AnswerQuality,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) as QuestionAnswerRank
    FROM Posts p
    WHERE p.PostTypeId = 2
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'PopularTag'
            WHEN t.Count > 100 THEN 'ModerateTag'
            WHEN t.Count > 10 THEN 'NicheTag'
            ELSE 'RareTag'
        END as TagPopularity
    FROM Tags t
    WHERE t.Count > 0
)
SELECT 
    tu.ReputationLevel,
    COUNT(DISTINCT tu.UserId) as UserCount,
    COUNT(DISTINCT qs.QuestionId) as QuestionCount,
    COUNT(DISTINCT asa.AnswerId) as AnswerCount,
    COUNT(DISTINCT ta.TagName) as TagCount,
    AVG(tu.Reputation) as AvgReputation,
    AVG(qs.ViewCount) as AvgQuestionViews,
    AVG(qs.Score) as AvgQuestionScore,
    AVG(asa.Score) as AvgAnswerScore,
    STRING_AGG(CONCAT(tu.DisplayName, ' (', tu.Reputation, ')'), ', ') as TopUsers,
    STRING_AGG(CONCAT(qs.Title, ' (', qs.ViewCount, ')'), '; ') as TopQuestions,
    STRING_AGG(CONCAT(ta.TagName, ' (', ta.TagCount, ')'), ', ') as PopularTags,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.PostTypeId = 1 
        AND p.CreationDate > '2020-01-01' 
        AND p.Score > 10
        AND EXISTS (
            SELECT 1 
            FROM Posts p2 
            WHERE p2.ParentId = p.Id 
            AND p2.PostTypeId = 2 
            AND p2.Score > 5
        )
    ) as RecentHighQualityQuestions,
    (
        SELECT STRING_AGG(
            CONCAT(p.Title, ' - ', 
                CASE 
                    WHEN EXISTS (SELECT 1 FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.Score > 10) THEN 'HasExcellentAnswers'
                    WHEN EXISTS (SELECT 1 FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.Score > 5) THEN 'HasGoodAnswers'
                    ELSE 'NoHighScoringAnswers'
                END
            ), ' | '
        )
        FROM Posts p
        WHERE p.PostTypeId = 1 
        AND p.CreationDate > '2020-01-01' 
        AND p.Score > 5
        GROUP BY p.Id
        HAVING COUNT(*) > 0
    ) as QualityQuestionAnalysis,
    (
        SELECT 
            CASE 
                WHEN COUNT(*) > 0 THEN 
                    CONCAT('Avg Score: ', CAST(AVG(p.Score) AS VARCHAR(10)), ', Count: ', COUNT(*))
                ELSE 'No Records'
            END
        FROM Posts p
        WHERE p.PostTypeId = 1 
        AND p.CreationDate > '2020-01-01' 
        AND p.ViewCount > 1000
    ) as HighViewQuestions,
    (
        SELECT 
            STRING_AGG(
                CONCAT('Answer Quality: ', asa.AnswerQuality, ' - ', COUNT(*), ' answers'),
                '; '
            ) 
        FROM AnswerStats asa
        WHERE asa.CreationDate > '2020-01-01'
        GROUP BY asa.AnswerQuality
    ) as AnswerQualityDistribution,
    (
        SELECT 
            CASE 
                WHEN COUNT(*) > 0 THEN 
                    CONCAT('Avg Score per Tag: ', CAST(AVG(ta.TagCount) AS VARCHAR(10)), ', TotalTags: ', COUNT(*))
                ELSE 'No Tags'
            END
        FROM TagAnalysis ta
        WHERE ta.TagCount > 100
    ) as PopularTagAnalysis,
    (
        SELECT 
            STRING_AGG(
                CONCAT('User: ', tu.DisplayName, ' (Reputation: ', tu.Reputation, ') - Questions: ', tu.PostCount),
                ' | '
            )
        FROM TopUsers tu
        WHERE EXISTS (
            SELECT 1 
            FROM Posts p 
            WHERE p.OwnerUserId = tu.UserId 
            AND p.PostTypeId = 1 
            AND p.Score > 10
        )
    ) as TopScoringAuthors,
    (
        SELECT 
            STRING_AGG(
                CONCAT('Question: ', qs.Title, ' - Answers: ', qs.AnswerCount),
                ' | '
            )
        FROM QuestionStats qs
        WHERE qs.AnswerCount > 10
    ) as QuestionWithManyAnswers
FROM TopUsers tu
LEFT JOIN QuestionStats qs ON tu.UserId = qs.OwnerUserId
LEFT JOIN AnswerStats asa ON tu.UserId = asa.OwnerUserId
LEFT JOIN TagAnalysis ta ON ta.TagCount > 100
GROUP BY tu.ReputationLevel
HAVING COUNT(DISTINCT tu.UserId) > 0
ORDER BY 
    CASE tu.ReputationLevel 
        WHEN 'Elite' THEN 1
        WHEN 'Expert' THEN 2
        WHEN 'Advanced' THEN 3
        WHEN 'Beginner' THEN 4
        ELSE 5
    END
LIMIT 10;