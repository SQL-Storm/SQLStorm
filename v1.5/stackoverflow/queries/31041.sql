-- {"query": "31041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 321} 
WITH RankedPosts AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        U.DisplayName AS OwnerDisplayName,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS PostRank
    FROM Posts P
    JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostTypeId = 1 -- Only Questions
),
AggregatedScores AS (
    SELECT 
        OwnerDisplayName,
        COUNT(PostId) AS TotalQuestions,
        SUM(Score) AS TotalScore,
        AVG(ViewCount) AS AvgViewCount,
        SUM(AnswerCount) AS TotalAnswers
    FROM RankedPosts
    WHERE PostRank <= 5 -- Top 5 latest questions per user
    GROUP BY OwnerDisplayName
),
UserBadges AS (
    SELECT 
        U.DisplayName,
        COUNT(B.Id) AS BadgeCount
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.DisplayName
)
SELECT 
    A.OwnerDisplayName,
    A.TotalQuestions,
    A.TotalScore,
    A.AvgViewCount,
    A.TotalAnswers,
    COALESCE(B.BadgeCount, 0) AS BadgeCount
FROM AggregatedScores A
LEFT JOIN UserBadges B ON A.OwnerDisplayName = B.DisplayName
ORDER BY A.TotalScore DESC, A.TotalQuestions DESC;