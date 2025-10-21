-- {"query": "13008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 597} 
WITH UserActivity AS (
    SELECT 
        U.Id AS UserId,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(COALESCE(P.Score, 0)) AS AvgScore,
        MAX(P.CreationDate) AS LastPostDate,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalCloseVotes,
        SUM(CASE WHEN PH.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS TotalEdits,
        ROW_NUMBER() OVER (ORDER BY SUM(COALESCE(P.Score, 0)) DESC) AS Rank
    FROM 
        Users U
    LEFT JOIN 
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN 
        PostHistory PH ON P.Id = PH.PostId
    WHERE 
        P.CreationDate > cast('2024-10-01' as date) - INTERVAL '1 year'
        AND (U.Reputation > 1000 OR P.Score > 50)
    GROUP BY 
        U.Id
),
CommentActivity AS (
    SELECT 
        UserId,
        COUNT(*) AS TotalComments,
        SUM(LENGTH(COALESCE(Text, ''))) AS TotalCommentLength
    FROM 
        Comments
    WHERE 
        CreationDate > cast('2024-10-01' as date) - INTERVAL '1 year'
    GROUP BY 
        UserId
)
SELECT 
    UA.UserId,
    UA.TotalPosts,
    UA.TotalQuestions,
    UA.TotalAnswers,
    UA.AvgScore,
    UA.LastPostDate,
    UA.TotalCloseVotes,
    UA.TotalEdits,
    CA.TotalComments,
    CA.TotalCommentLength,
    DENSE_RANK() OVER (ORDER BY UA.AvgScore DESC, CA.TotalComments DESC) AS OverallRank,
    CONCAT(U.DisplayName, ' - Reputation: ', U.Reputation) AS UserDetails
FROM 
    UserActivity UA
JOIN 
    Users U ON UA.UserId = U.Id
LEFT JOIN 
    CommentActivity CA ON UA.UserId = CA.UserId
WHERE 
    UA.Rank <= 100
ORDER BY 
    UA.AvgScore DESC, 
    CA.TotalComments DESC
LIMIT 20;