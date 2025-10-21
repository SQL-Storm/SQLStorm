-- {"query": "50036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1224} 
WITH UserTagActivity AS (
    SELECT
        P_ans.OwnerUserId,
        P_ans.Score,
        P_ans.CreationDate,
        P_q.ViewCount AS QuestionViewCount
    FROM Posts AS P_q
    JOIN Posts AS P_ans ON P_q.Id = P_ans.ParentId
    WHERE P_q.PostTypeId = 1
      AND P_ans.PostTypeId = 2
      AND P_ans.OwnerUserId IS NOT NULL
      AND (P_q.Tags LIKE '%<python>%' OR P_q.Tags LIKE '%<java>%' OR P_q.Tags LIKE '%<javascript>%' OR P_q.Tags LIKE '%<sql>%' OR P_q.Tags LIKE '%<c#>%')
),
UserExpertise AS (
    SELECT
        OwnerUserId,
        COUNT(*) AS ExpertAnswerCount,
        AVG(Score) AS AvgExpertAnswerScore,
        SUM(QuestionViewCount) AS TotalQuestionViewsForAnswers
    FROM UserTagActivity
    GROUP BY OwnerUserId
    HAVING COUNT(*) > 15 AND AVG(Score) > 1
),
UserBadgeCounts AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserVoteStats AS (
    SELECT
        P.OwnerUserId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS TotalFavoritesReceived
    FROM Votes AS V
    JOIN Posts AS P ON V.PostId = P.Id
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserInteractionStats AS (
    SELECT
        OwnerUserId,
        AVG(Score) AS AvgPostScore,
        AVG(CommentCount) AS AvgCommentCount,
        (SELECT COUNT(*) FROM Comments C WHERE C.UserId = P.OwnerUserId) AS TotalCommentsMade
    FROM Posts AS P
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
)
SELECT
    U.DisplayName,
    U.Reputation,
    UE.ExpertAnswerCount,
    CAST(UE.AvgExpertAnswerScore AS DECIMAL(10, 2)) AS AvgExpertAnswerScore,
    UIS.TotalCommentsMade,
    COALESCE(UBC.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBC.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBC.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(UVS.TotalUpvotesReceived, 0) AS UpvotesReceived,
    COALESCE(UVS.TotalDownvotesReceived, 0) AS DownvotesReceived,
    CAST(
        (U.Reputation * 0.05) +
        (UE.ExpertAnswerCount * 5) +
        (UE.AvgExpertAnswerScore * 10) +
        (UE.TotalQuestionViewsForAnswers * 0.001) +
        (COALESCE(UBC.GoldBadges, 0) * 100) +
        (COALESCE(UBC.SilverBadges, 0) * 25) +
        (COALESCE(UIS.AvgCommentCount, 0) * 1.5) -
        (COALESCE(UVS.TotalDownvotesReceived, 0) * 2)
    AS DECIMAL(10, 2)) AS CompositeScore,
    DENSE_RANK() OVER (ORDER BY
        (U.Reputation * 0.05) +
        (UE.ExpertAnswerCount * 5) +
        (UE.AvgExpertAnswerScore * 10) +
        (UE.TotalQuestionViewsForAnswers * 0.001) +
        (COALESCE(UBC.GoldBadges, 0) * 100) +
        (COALESCE(UBC.SilverBadges, 0) * 25) +
        (COALESCE(UIS.AvgCommentCount, 0) * 1.5) -
        (COALESCE(UVS.TotalDownvotesReceived, 0) * 2)
    DESC) AS UserRank
FROM Users AS U
JOIN UserExpertise AS UE ON U.Id = UE.OwnerUserId
LEFT JOIN UserBadgeCounts AS UBC ON U.Id = UBC.UserId
LEFT JOIN UserVoteStats AS UVS ON U.Id = UVS.OwnerUserId
LEFT JOIN UserInteractionStats AS UIS ON U.Id = UIS.OwnerUserId
WHERE U.Reputation > 10000
  AND U.CreationDate < (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 year')
  AND U.UpVotes > (U.DownVotes * 1.2)
ORDER BY UserRank, U.Reputation DESC
LIMIT 150;