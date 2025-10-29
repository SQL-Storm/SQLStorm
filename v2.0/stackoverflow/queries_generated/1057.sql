-- {"query": "1057.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2513} 

WITH UserActivityStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        SUM(CASE WHEN P_Accepted.AcceptedAnswerId IS NOT NULL AND P_Accepted.OwnerUserId = U.Id THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        MAX(COALESCE(P.LastActivityDate, C.CreationDate, V.CreationDate)) AS LastKnownActivityDate,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END) AS AvgAnswerScore,
        COUNT(DISTINCT V.Id) AS TotalVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Posts P_Accepted ON P.Id = P_Accepted.AcceptedAnswerId -- P_Accepted refers to a question that *accepted* this user's answer
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostDetailStats_Raw AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.LastEditDate,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.CommentCount,
        COUNT(DISTINCT PH.Id) AS HistoryEntryCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE NULL END) AS EditCount,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (10,12) THEN 1 ELSE NULL END) AS CloseDeleteEventCount,
        COUNT(DISTINCT PL.RelatedPostId) AS LinkedPostsCount,
        ARRAY_LENGTH(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM P.Tags), '><'), 1) AS ParsedTagCount,
        (SELECT MAX(C_sub.Score) FROM Comments C_sub WHERE C_sub.PostId = P.Id) AS MaxCommentScoreOnPost, -- Correlated subquery
        LAG(P.CreationDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PrevPostCreationDate,
        COALESCE(P.LastEditDate, P.CreationDate) - P.CreationDate AS TimeToFirstEdit,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC, P.Id) AS rn_top_post
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId
    GROUP BY P.Id, P.OwnerUserId, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.LastEditDate, P.FavoriteCount, P.Title, P.Tags, P.AnswerCount, P.CommentCount
),
UserTopPost AS (
    SELECT
        PostId,
        OwnerUserId,
        PostTypeId,
        PostCreationDate,
        Score,
        ViewCount,
        LastEditDate,
        FavoriteCount,
        Title,
        Tags,
        AnswerCount,
        CommentCount,
        HistoryEntryCount,
        EditCount,
        CloseDeleteEventCount,
        LinkedPostsCount,
        ParsedTagCount,
        MaxCommentScoreOnPost,
        TimeToFirstEdit
    FROM PostDetailStats_Raw
    WHERE rn_top_post = 1
),
BadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LatestBadgeDate,
        MIN(B.Date) AS EarliestBadgeDate,
        RANK() OVER (ORDER BY COUNT(B.Id) DESC, MAX(B.Date) ASC) AS BadgeRank
    FROM Badges B
    GROUP BY B.UserId
),
HighImpactPosts AS (
    SELECT
        P.Id AS PostId,
        P.Title AS PostTitle,
        P.CreationDate,
        P.OwnerUserId,
        P.Score,
        P.ViewCount,
        'Question' AS PostCategory,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.ViewCount DESC, P.Score DESC, P.Id) AS rn_high_impact
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) * 2 -- Uncorrelated subquery
    UNION ALL
    SELECT
        P.Id AS PostId,
        LEFT(P.Body, 100) AS PostTitle, -- String expression
        P.CreationDate,
        P.OwnerUserId,
        P.Score,
        NULL AS ViewCount,
        'Answer' AS PostCategory,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC, P.Id) AS rn_high_impact
    FROM Posts P
    WHERE P.PostTypeId = 2 AND P.Score > 50
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.TotalPostScore,
    COALESCE(BS.TotalBadges, 0) AS TotalBadges,
    COALESCE(BS.GoldBadges, 0) AS GoldBadges,
    COALESCE(BS.SilverBadges, 0) AS SilverBadges,
    COALESCE(BS.BronzeBadges, 0) AS BronzeBadges,
    UTP.Title AS TopPostTitle,
    UTP.Score AS TopPostScore,
    UTP.PostTypeId AS TopPostType,
    HIP_Selected.PostTitle AS HighImpactSelectedPostTitle,
    HIP_Selected.Score AS HighImpactSelectedPostScore,
    HIP_Selected.PostCategory AS HighImpactSelectedPostType,
    UTP.MaxCommentScoreOnPost,
    UTP.EditCount,
    UTP.LinkedPostsCount,
    UTP.ParsedTagCount,
    UAS.LastKnownActivityDate,
    AVG(UTP.Score) OVER (PARTITION BY (UAS.TotalQuestions > 0) ORDER BY UAS.Reputation DESC) AS AvgTopPostScoreByQuestionStatusGroup,
    NTILE(10) OVER (ORDER BY UAS.Reputation DESC, UAS.LastAccessDate) AS UserReputationDecile,
    CASE
        WHEN UAS.Reputation > 10000 AND COALESCE(BS.GoldBadges, 0) >= 5 THEN 'Guru Elite'
        WHEN UAS.Reputation > 5000 AND COALESCE(BS.SilverBadges, 0) >= 10 THEN 'Seasoned Expert'
        WHEN UAS.Reputation > 1000 OR UAS.TotalPosts > 50 THEN 'Active Contributor'
        ELSE 'Casual User'
    END AS UserEngagementTier,
    (UAS.UpVotesGiven::numeric / NULLIF(UAS.UpVotesGiven + UAS.DownVotesGiven, 0)) AS UpVoteRatio,
    ABS(EXTRACT(EPOCH FROM (UAS.LastAccessDate - UAS.UserCreationDate))) / (60 * 60 * 24 * 365.25) AS YearsActive,
    COALESCE(U.Location, 'Unknown Location') AS UserLocation, -- NULL logic
    (LOWER(U.DisplayName) LIKE '%dev%' OR LOWER(U.AboutMe) LIKE '%sql%') AS IsDeveloperKeywordUser, -- String expressions and complicated predicates
    (
        SELECT COUNT(DISTINCT PH_sub.UserId)
        FROM PostHistory PH_sub
        WHERE PH_sub.PostId = UTP.PostId AND PH_sub.PostHistoryTypeId IN (4,5,6) AND PH_sub.UserId IS NOT NULL AND PH_sub.UserId <> UAS.UserId
    ) AS OtherEditorsCount -- Correlated subquery
FROM UserActivityStats UAS
LEFT JOIN BadgeSummary BS ON UAS.UserId = BS.UserId
LEFT JOIN Users U ON UAS.UserId = U.Id -- Re-join Users for Location, AboutMe
LEFT JOIN UserTopPost UTP ON UAS.UserId = UTP.OwnerUserId -- Join with the selected top post
LEFT JOIN (SELECT * FROM HighImpactPosts WHERE rn_high_impact = 1) AS HIP_Selected ON UAS.UserId = HIP_Selected.OwnerUserId
WHERE
    UAS.Reputation >= 100
    AND UAS.LastKnownActivityDate >= '2022-01-01'
    AND (UTP.Score IS NULL OR UTP.Score > 0) -- NULL logic in predicate
    AND (
        (UTP.PostTypeId = 1 AND UTP.ParsedTagCount >= 3) OR
        (UTP.PostTypeId = 2 AND UTP.TimeToFirstEdit IS NOT NULL AND UTP.TimeToFirstEdit < INTERVAL '1 hour') OR
        UTP.PostId IS NULL -- Include users even if they don't have a specific "top post" meeting the criteria
    )
    AND (U.AboutMe IS NOT NULL OR UAS.TotalPosts > 10) -- NULL logic on User.AboutMe
ORDER BY
    UAS.Reputation DESC, UAS.LastKnownActivityDate DESC
LIMIT 500;
