-- {"query": "2023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 549} 
WITH TopUsers AS (
    SELECT 
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        RANK() OVER (ORDER BY U.Reputation DESC) AS ReputationRank
    FROM Users U
    WHERE U.Reputation IS NOT NULL
),
BadgeCounts AS (
    SELECT 
        B.UserId, 
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges B
    GROUP BY B.UserId
),
PostStats AS (
    SELECT 
        P.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE P.PostTypeId = 1) AS QuestionsPosted,
        COUNT(*) FILTER (WHERE P.PostTypeId = 2) AS AnswersPosted,
        AVG(NULLIF(P.Score, 0)) AS AvgPostScore,
        COUNT(P.Id) FILTER (WHERE P.Score > 0) AS PositivePosts,
        COUNT(P.Id) FILTER (WHERE P.Score < 0) AS NegativePosts
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserComments AS (
    SELECT 
        C.UserId, 
        COUNT(C.Id) AS CommentCount,
        AVG(C.Score) AS AvgCommentScore
    FROM Comments C
    WHERE C.UserId IS NOT NULL
    GROUP BY C.UserId
)
SELECT 
    U.UserId,
    U.DisplayName,
    U.Reputation,
    B.TotalBadges,
    B.GoldBadges,
    B.SilverBadges,
    B.BronzeBadges,
    PS.QuestionsPosted,
    PS.AnswersPosted,
    PS.AvgPostScore,
    PS.PositivePosts,
    PS.NegativePosts,
    COALESCE(UC.CommentCount, 0) AS TotalComments,
    COALESCE(UC.AvgCommentScore, 0) AS AvgCommentScore
FROM TopUsers U
LEFT JOIN BadgeCounts B ON U.UserId = B.UserId
LEFT JOIN PostStats PS ON U.UserId = PS.UserId
LEFT JOIN UserComments UC ON U.UserId = UC.UserId
WHERE (B.TotalBadges IS NOT NULL OR PS.QuestionsPosted IS NOT NULL OR UC.CommentCount IS NOT NULL)
AND U.ReputationRank <= 100
ORDER BY U.ReputationRank, U.DisplayName;