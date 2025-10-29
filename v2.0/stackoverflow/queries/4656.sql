-- {"query": "4656.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1407}
WITH RECURSIVE PostHierarchy AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Title,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        1 AS Level
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ParentId IS NULL

    UNION ALL

    SELECT
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Title,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        ph.Level + 1 AS Level
    FROM Posts p
    JOIN PostHierarchy ph ON p.ParentId = ph.Id
    WHERE p.PostTypeId = 2
),
UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(CASE WHEN PostTypeId = 1 THEN Id END) AS QuestionCount,
        COUNT(CASE WHEN PostTypeId = 2 THEN Id END) AS AnswerCount,
        SUM(CASE WHEN Score > 0 THEN 1 ELSE 0 END) AS PositiveScorePosts,
        MAX(CreationDate) AS LastPostDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND OwnerUserId <> -1
    GROUP BY OwnerUserId
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(upc.QuestionCount, 0) AS TotalQuestions,
        COALESCE(upc.AnswerCount, 0) AS TotalAnswers,
        COALESCE(upc.PositiveScorePosts, 0) AS PostsWithPositiveScore,
        CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.CreationDate)) / 86400 AS INTEGER) AS DaysSinceCreation,
        CASE
            WHEN u.LastAccessDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365 day') THEN 'Inactive'
            WHEN u.LastAccessDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '90 day') THEN 'Moderately Active'
            ELSE 'Active'
        END AS ActivityStatus
    FROM Users u
    LEFT JOIN UserPostCounts upc ON u.Id = upc.OwnerUserId
),
QuestionDetails AS (
    SELECT
        ph.Id AS QuestionId,
        ph.Title,
        ph.CreationDate AS QuestionCreationDate,
        ph.Score AS QuestionScore,
        ph.AnswerCount AS QuestionAnswerCount,
        ph.FavoriteCount AS QuestionFavoriteCount,
        ua.DisplayName AS QuestionOwnerDisplayName,
        ua.Reputation AS QuestionOwnerReputation,
        CASE
            WHEN ph.ClosedDate IS NOT NULL THEN CAST(EXTRACT(EPOCH FROM (ph.ClosedDate - ph.CreationDate)) / 3600 AS INTEGER)
            ELSE NULL
        END AS HoursToClose,
        ROW_NUMBER() OVER (PARTITION BY ph.Id ORDER BY ph.Level) AS RowNum,
        ph.PostTypeId,
        ph.Level,
        ph.OwnerUserId,
        ph.ClosedDate
    FROM PostHierarchy ph
    JOIN UserActivity ua ON ph.OwnerUserId = ua.UserId
    WHERE ph.PostTypeId = 1 AND ph.Level = 1
),
AnswerDetails AS (
    SELECT
        ph.Id AS AnswerId,
        ph.ParentId AS QuestionId,
        ph.Score AS AnswerScore,
        ph.CreationDate AS AnswerCreationDate,
        ua.DisplayName AS AnswerOwnerDisplayName,
        ua.Reputation AS AnswerOwnerReputation,
        CASE WHEN ph.Score > qd.QuestionScore THEN 'HigherScoreThanQuestion' ELSE 'LowerScoreThanQuestion' END AS ScoreComparison,
        DENSE_RANK() OVER (PARTITION BY ph.ParentId ORDER BY ph.Score DESC, ph.CreationDate ASC) AS RankByScore,
        ph.PostTypeId,
        ph.ParentId AS ParentId_for_group,
        ph.OwnerUserId AS OwnerUserId_for_group
    FROM PostHierarchy ph
    JOIN UserActivity ua ON ph.OwnerUserId = ua.UserId
    JOIN QuestionDetails qd ON ph.ParentId = qd.QuestionId
    WHERE ph.PostTypeId = 2
)
SELECT
    qd.QuestionId,
    qd.Title,
    qd.QuestionCreationDate,
    qd.QuestionScore,
    qd.QuestionAnswerCount,
    qd.QuestionFavoriteCount,
    qd.QuestionOwnerDisplayName,
    qd.QuestionOwnerReputation,
    qd.HoursToClose,
    ad.AnswerId,
    ad.AnswerScore,
    ad.AnswerCreationDate,
    ad.AnswerOwnerDisplayName,
    ad.AnswerOwnerReputation,
    ad.ScoreComparison,
    CASE
        WHEN ad.RankByScore = 1 THEN 'BestAnswer'
        WHEN ad.RankByScore <= 5 THEN 'Top5Answer'
        ELSE 'OtherAnswer'
    END AS AnswerRank,
    CASE
        WHEN qd.QuestionOwnerReputation > 10000 AND ad.AnswerOwnerReputation > 5000 THEN 'HighReputationInteraction'
        WHEN qd.QuestionOwnerReputation < 1000 AND ad.AnswerOwnerReputation < 500 THEN 'LowReputationInteraction'
        ELSE 'StandardInteraction'
    END AS ReputationInteractionLevel,
    CAST(SUBSTRING(qd.Title FROM 1 FOR 10) AS VARCHAR(10)) AS FirstTenCharsOfTitle,
    TIMESTAMP '2024-10-01 12:34:56' AS QueryExecutionTimestamp
FROM QuestionDetails qd
FULL OUTER JOIN AnswerDetails ad ON qd.QuestionId = ad.QuestionId
WHERE COALESCE(qd.QuestionAnswerCount, 0) > 0
  AND (qd.QuestionScore > ad.AnswerScore OR ad.AnswerScore IS NULL)
  AND (qd.ClosedDate IS NULL OR qd.ClosedDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 day'))
  AND qd.QuestionOwnerReputation > 100
  AND ad.AnswerOwnerReputation IS NOT NULL
  AND EXISTS (
        SELECT 1
        FROM PostLinks pl
        WHERE pl.PostId = qd.QuestionId AND pl.LinkTypeId = 3
    )
GROUP BY
    qd.QuestionId,
    qd.Title,
    qd.QuestionCreationDate,
    qd.QuestionScore,
    qd.QuestionAnswerCount,
    qd.QuestionFavoriteCount,
    qd.QuestionOwnerDisplayName,
    qd.QuestionOwnerReputation,
    qd.HoursToClose,
    qd.RowNum,
    qd.PostTypeId,
    qd.Level,
    qd.OwnerUserId,
    qd.ClosedDate,
    ad.AnswerId,
    ad.AnswerScore,
    ad.AnswerCreationDate,
    ad.AnswerOwnerDisplayName,
    ad.AnswerOwnerReputation,
    ad.ScoreComparison,
    ad.RankByScore,
    ad.PostTypeId,
    ad.ParentId_for_group,
    ad.OwnerUserId_for_group
ORDER BY qd.QuestionScore DESC, qd.QuestionAnswerCount DESC
LIMIT 1000;