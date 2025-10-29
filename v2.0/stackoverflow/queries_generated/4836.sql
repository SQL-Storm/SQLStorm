-- {"query": "4836.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 981} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.CreationDate ASC) AS FirstPostFlag
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE u.DisplayName IS NOT NULL AND u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostScoreAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        pt.Name AS PostType,
        p.Score,
        p.CreationDate,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS LatestRevisionOrder,
        AVG(CAST(c.Score AS FLOAT)) OVER (PARTITION BY p.Id) AS AverageCommentScore,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS NextPostScore,
        COALESCE(p.FavoriteCount, 0) AS SafeFavoriteCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.Score IS NOT NULL AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.ReputationRank,
    ue.TotalPosts,
    ue.TotalComments,
    ue.TotalVotes,
    ue.QuestionCount,
    ue.AnswerCount,
    psa.PostId,
    psa.Title,
    psa.PostType,
    psa.Score,
    psa.AverageCommentScore,
    psa.PostStatus,
    psa.SafeFavoriteCount,
    CASE
        WHEN psa.Score > 1000 AND psa.AverageCommentScore > 3 THEN 'Highly Valued'
        WHEN psa.Score BETWEEN 100 AND 1000 AND psa.AverageCommentScore BETWEEN 1 AND 3 THEN 'Moderately Valued'
        ELSE 'Standard'
    END AS ValueCategory,
    (psa.Score - psa.PreviousPostScore) AS ScoreDifferenceFromPrevious,
    (psa.Score - psa.NextPostScore) AS ScoreDifferenceToNext,
    COALESCE(
        (
            SELECT COUNT(*)
            FROM PostHistory ph
            WHERE ph.PostId = psa.PostId
            AND ph.PostHistoryTypeId IN (4, 5) -- Edit Title, Edit Body
        ),
        0
    ) AS EditHistoryCount,
    CASE
        WHEN psa.Score > 0 AND psa.SafeFavoriteCount > 0 THEN CAST(psa.Score AS FLOAT) / psa.SafeFavoriteCount
        ELSE 0
    END AS ScoreToFavoriteRatio,
    ue.FirstPostFlag
FROM UserEngagement ue
JOIN PostScoreAnalysis psa ON ue.UserId = psa.OwnerUserId
WHERE ue.Reputation > 5000 AND psa.Score > 50 AND psa.PostType IN ('Question', 'Answer')
ORDER BY ue.ReputationRank, psa.Score DESC
LIMIT 100;
