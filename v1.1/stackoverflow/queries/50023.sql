-- {"query": "50023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 968} 
WITH PopularTags AS (
    SELECT
        TagName
    FROM Tags
    WHERE Count > 50000 AND IsModeratorOnly = '0' AND IsRequired = '0'
    LIMIT 20
),
TopUsers AS (
    SELECT
        U.Id,
        U.DisplayName,
        U.Reputation,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users U
    JOIN Badges B ON U.Id = B.UserId
    WHERE U.Reputation > 150000
    GROUP BY U.Id, U.DisplayName, U.Reputation
    HAVING SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) > 5
),
UserTagContributions AS (
    SELECT
        TU.Id AS UserId,
        TU.DisplayName,
        PT.TagName,
        COUNT(A.Id) AS AnswerCount,
        SUM(A.Score) AS TotalAnswerScore,
        SUM(A.FavoriteCount) AS TotalAnswerFavorites,
        SUM(CASE WHEN Q.AcceptedAnswerId = A.Id THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        MIN(A.CreationDate) AS FirstAnswerDate,
        MAX(A.CreationDate) AS LastAnswerDate
    FROM TopUsers TU
    JOIN Posts A ON TU.Id = A.OwnerUserId AND A.PostTypeId = 2 -- Answers
    JOIN Posts Q ON A.ParentId = Q.Id AND Q.PostTypeId = 1 AND Q.ClosedDate IS NULL -- Questions
    JOIN PopularTags PT ON PT.TagName = ANY(string_to_array(substring(Q.Tags, 2, length(Q.Tags)-2), '><'))
    WHERE A.CreationDate > (cast('2024-10-01' as date) - interval '5 year')
    GROUP BY TU.Id, TU.DisplayName, PT.TagName
    HAVING COUNT(A.Id) > 10
),
RankedTagPerformance AS (
    SELECT
        *,
        CAST(AcceptedAnswersCount AS DECIMAL) / AnswerCount AS AcceptanceRate,
        DENSE_RANK() OVER (PARTITION BY TagName ORDER BY TotalAnswerScore DESC, AnswerCount DESC) AS RankInTag
    FROM UserTagContributions
),
UserPostInteraction AS (
    SELECT
        P.OwnerUserId AS UserId,
        AVG(P.CommentCount) AS AvgCommentsPerPost,
        (SELECT AVG(V.BountyAmount) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 8) AS AvgBounty
    FROM Posts P
    WHERE P.OwnerUserId IN (SELECT Id FROM TopUsers) AND P.CommunityOwnedDate IS NULL
    GROUP BY P.OwnerUserId, P.Id
)
SELECT
    RTP.TagName,
    RTP.RankInTag,
    RTP.DisplayName,
    TU.Reputation,
    TU.GoldBadges,
    RTP.AnswerCount,
    RTP.TotalAnswerScore,
    RTP.AcceptedAnswersCount,
    RTP.AcceptanceRate,
    RTP.TotalAnswerFavorites,
    EXTRACT(YEAR FROM AGE(RTP.LastAnswerDate, RTP.FirstAnswerDate)) || ' years' AS ActivePeriod,
    (
        SELECT AVG(UPI.AvgCommentsPerPost)
        FROM UserPostInteraction UPI
        WHERE UPI.UserId = RTP.UserId
    ) AS OverallAvgCommentsOnUserPosts,
    (
        SELECT STRING_AGG(C.Text, ' || ')
        FROM (
            SELECT C.Text
            FROM Comments C
            JOIN Posts P ON C.PostId = P.Id
            WHERE P.OwnerUserId = RTP.UserId
            ORDER BY C.Score DESC
            LIMIT 3
        ) AS C
    ) AS TopCommentsOnUserPosts
FROM RankedTagPerformance RTP
JOIN TopUsers TU ON RTP.UserId = TU.Id
WHERE RTP.RankInTag <= 10
ORDER BY RTP.TagName, RTP.RankInTag;