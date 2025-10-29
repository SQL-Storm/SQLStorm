-- {"query": "4624.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1335} 

WITH RankedAnswers AS (
    SELECT
        ROW_NUMBER() OVER (PARTITION BY ParentId ORDER BY Score DESC, CreationDate ASC) as rn,
        Id,
        ParentId,
        OwnerUserId,
        Score,
        CreationDate
    FROM Posts
    WHERE PostTypeId = 2 -- Answers
),
TopQuestions AS (
    SELECT
        Id,
        OwnerUserId,
        Title,
        CreationDate,
        Score,
        AnswerCount,
        FavoriteCount,
        ROW_NUMBER() OVER (ORDER BY FavoriteCount DESC, Score DESC, AnswerCount DESC) as q_rn
    FROM Posts
    WHERE PostTypeId = 1 -- Questions
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0 -- Exclude community user
    GROUP BY u.Id, u.DisplayName
),
QuestionAnswerStats AS (
    SELECT
        tq.Id AS QuestionId,
        tq.Title,
        tq.OwnerUserId AS QuestionOwnerUserId,
        tq.Score AS QuestionScore,
        tq.AnswerCount AS TotalAnswers,
        ra.rn AS RankOfBestAnswer,
        ra.Id AS BestAnswerId,
        ra.OwnerUserId AS BestAnswerOwnerUserId,
        ra.Score AS BestAnswerScore,
        ra.CreationDate AS BestAnswerCreationDate,
        COALESCE(ua.DisplayName, 'Unknown User') AS QuestionOwnerDisplayName,
        ua.Reputation AS QuestionOwnerReputation,
        ua.GoldBadges AS QuestionOwnerGoldBadges,
        ua.SilverBadges AS QuestionOwnerSilverBadges,
        ua.BronzeBadges AS QuestionOwnerBronzeBadges,
        LAG(tq.Score, 1, 0) OVER (ORDER BY tq.CreationDate) AS PreviousQuestionScore
    FROM TopQuestions tq
    LEFT JOIN RankedAnswers ra ON tq.Id = ra.ParentId AND ra.rn = 1
    LEFT JOIN UserActivity ua ON tq.OwnerUserId = ua.UserId
    WHERE tq.q_rn BETWEEN 1 AND 100 -- Consider top 100 questions by popularity
)
SELECT
    qas.QuestionId,
    qas.Title,
    qas.QuestionOwnerDisplayName,
    qas.QuestionOwnerReputation,
    qas.QuestionScore,
    qas.TotalAnswers,
    qas.RankOfBestAnswer,
    CASE
        WHEN qas.BestAnswerId IS NULL THEN 'No accepted answer'
        WHEN qas.BestAnswerScore > qas.QuestionScore THEN 'Answer outscored question'
        WHEN qas.BestAnswerScore <= 0 THEN 'Low score answer'
        ELSE 'Standard answer'
    END AS AnswerQualityCategory,
    qas.BestAnswerScore,
    qas.BestAnswerCreationDate,
    CASE
        WHEN qas.QuestionOwnerGoldBadges > 5 THEN 'Elite Contributor'
        WHEN qas.QuestionOwnerSilverBadges > 10 THEN 'Active Member'
        ELSE 'Regular User'
    END AS UserTier,
    (qas.QuestionScore * 1.0 / NULLIF(qas.TotalAnswers, 0)) AS ScorePerAnswerRatio,
    qas.PreviousQuestionScore,
    UPPER(SUBSTRING(qas.Title, 1, 3)) || '-' || LOWER(REPLACE(qas.Title, ' ', '_')) AS ProcessedTitle,
    CASE WHEN qas.QuestionOwnerReputation > 10000 THEN TRUE ELSE FALSE END AS IsHighReputationOwner,
    'QueryExecutionTime:' || CAST(EXTRACT(EPOCH FROM NOW()) AS VARCHAR) AS BenchmarkMarker
FROM QuestionAnswerStats qas
WHERE qas.QuestionOwnerReputation > 500 -- Filter for users with some reputation
  AND qas.BestAnswerScore IS NOT NULL -- Ensure we have a best answer
  AND qas.TotalAnswers > 0 -- Ensure the question has answers
UNION ALL
SELECT
    NULL, -- Placeholder for QuestionId
    'Summary Row',
    NULL, -- Placeholder for QuestionOwnerDisplayName
    AVG(CAST(QuestionOwnerReputation AS DECIMAL)),
    AVG(CAST(QuestionScore AS DECIMAL)),
    AVG(CAST(TotalAnswers AS DECIMAL)),
    AVG(CAST(RankOfBestAnswer AS DECIMAL)),
    NULL, -- Placeholder for AnswerQualityCategory
    AVG(CAST(BestAnswerScore AS DECIMAL)),
    NULL, -- Placeholder for BestAnswerCreationDate
    NULL, -- Placeholder for UserTier
    AVG((qas.QuestionScore * 1.0 / NULLIF(qas.TotalAnswers, 0))),
    AVG(CAST(PreviousQuestionScore AS DECIMAL)),
    NULL, -- Placeholder for ProcessedTitle
    NULL, -- Placeholder for IsHighReputationOwner
    'QueryExecutionTime:' || CAST(EXTRACT(EPOCH FROM NOW()) AS VARCHAR)
FROM QuestionAnswerStats qas
WHERE qas.QuestionOwnerReputation > 500
  AND qas.BestAnswerScore IS NOT NULL
  AND qas.TotalAnswers > 0;
