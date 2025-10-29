-- {"query": "4218.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1032}
WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT ph.Id) AS PostHistoryCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS ReputationRank,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS PreviousReputation,
        LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS NextReputation,
        CAST(EXTRACT(YEAR FROM u.CreationDate) AS INTEGER) AS UserCreationYear
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE u.Id BETWEEN 1 AND 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
QuestionDetails AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Score,
        p.CreationDate AS PostCreationDate,
        u.DisplayName AS OwnerDisplayName,
        CAST(DATE_PART('day', (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate)) AS INTEGER) AS DaysSinceCreation,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AnswerCount >= 5 AND p.FavoriteCount >= 10 THEN 'Popular'
            WHEN p.Score > 100 THEN 'Highly Scored'
            ELSE 'Standard'
        END AS PostStatusCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PreviousPostScore,
        p.OwnerUserId
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.Id BETWEEN 1 AND 50000
)
SELECT
    'Performance Benchmark Query' AS QueryDescription,
    rua.UserId,
    rua.DisplayName AS UserName,
    rua.Reputation,
    rua.ReputationRank,
    rua.PreviousReputation,
    rua.NextReputation,
    rua.UserCreationYear,
    rua.QuestionCount,
    rua.AnswerCount,
    rua.PostHistoryCount,
    qd.PostId,
    qd.Title,
    qd.Tags,
    qd.PostStatusCategory,
    qd.DaysSinceCreation,
    qd.UserPostRank,
    qd.PreviousPostScore,
    CAST(
        COALESCE(
            (
                SELECT SUM(v.VoteTypeId)
                FROM Votes v
                WHERE v.PostId = qd.PostId
                  AND v.VoteTypeId IN (2, 3)
            ),
            0
        ) AS REAL
    ) AS TotalVoteValue,
    CASE
        WHEN qd.AnswerCount > 0 THEN CAST(qd.Score AS REAL) / qd.AnswerCount
        ELSE 0.0
    END AS ScorePerAnswerRatio,
    CHAR_LENGTH(qd.Title) AS TitleLength,
    (rua.DisplayName || ' (' || qd.PostStatusCategory || ')') AS UserAndCategory,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = qd.PostId AND c.UserId IS NOT NULL) AS CommentCountForPost,
    CASE WHEN qd.Tags LIKE '%<sql>%' THEN 'SQL Tagged' ELSE 'Other Tagged' END AS HasSqlTag
FROM RankedUserActivity rua
FULL OUTER JOIN QuestionDetails qd ON rua.UserId = qd.OwnerUserId
WHERE (rua.Reputation > 1000 OR qd.Score > 50)
   OR (rua.UserCreationYear < 2015 AND qd.DaysSinceCreation > 3650)
ORDER BY rua.Reputation DESC, qd.Score DESC
LIMIT 1000;