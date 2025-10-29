-- {"query": "1353.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2508} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT Q.Id) AS TotalQuestions,
        COUNT(DISTINCT A.Id) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(COALESCE(Q.Score, 0)) AS TotalQuestionScore,
        SUM(COALESCE(A.Score, 0)) AS TotalAnswerScore,
        SUM(COALESCE(Q.ViewCount, 0)) AS TotalQuestionViews,
        AVG(CASE WHEN C.Score >= 0 THEN C.Score ELSE NULL END) AS AveragePositiveCommentScore, -- Only considers non-negative comment scores
        MAX(C.CreationDate) AS LastCommentDate,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes
    FROM Users AS U
    LEFT JOIN Posts AS Q ON U.Id = Q.OwnerUserId AND Q.PostTypeId = 1
    LEFT JOIN Posts AS A ON U.Id = A.OwnerUserId AND A.PostTypeId = 2
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes
),
BadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeDate
    FROM Badges AS B
    GROUP BY B.UserId
),
UserPostHistorySummary AS ( -- Aggregates history per user
    SELECT
        PH.UserId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS TotalEditCount, -- Edits to Title, Body, Tags
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS LastEditDateByUser,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 AND PH.Comment NOT IN ('1', '101', '102', '103', '104', '105') THEN 1 ELSE 0 END) AS NonStandardCloseVoteCount -- Exclude common close reasons (duplicate, off-topic, needs clarity/focus, opinion-based)
    FROM PostHistory AS PH
    WHERE PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
RecentPostActivity AS (
    SELECT
        P.OwnerUserId AS UserId,
        P.Id AS PostId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.ViewCount AS PostViewCount,
        P.Score AS PostScore,
        P.Title AS PostTitle,
        P.Tags AS PostTags,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.LastActivityDate DESC, P.CreationDate DESC) AS rn
    FROM Posts AS P
    WHERE P.OwnerUserId IS NOT NULL AND P.PostTypeId = 1 -- Focus on questions for "recent post" analysis
),
AggregatedTagStats AS (
    SELECT
        P.OwnerUserId AS UserId,
        unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')) AS TagName,
        SUM(P.Score) AS TagScoreSum,
        AVG(P.ViewCount) AS TagAvgViews,
        COUNT(P.Id) AS TagPostCount
    FROM Posts AS P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND P.OwnerUserId IS NOT NULL AND substring(P.Tags, 2, length(P.Tags)-2) != ''
    GROUP BY P.OwnerUserId, unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><'))
),
UserVoteSummary AS (
    SELECT
        V.UserId,
        COUNT(CASE WHEN V.VoteTypeId = 2 THEN 1 END) AS TotalUpVotesGiven,
        COUNT(CASE WHEN V.VoteTypeId = 3 THEN 1 END) AS TotalDownVotesGiven,
        COUNT(CASE WHEN V.VoteTypeId = 5 THEN 1 END) AS TotalFavoritesGiven
    FROM Votes AS V
    WHERE V.UserId IS NOT NULL
    GROUP BY V.UserId
),
UserCommentSentiment AS (
    SELECT
        C.UserId,
        C.Text AS RecentCommentText,
        C.CreationDate AS RecentCommentDate,
        CASE
            WHEN C.Text ILIKE '%thank%' OR C.Text ILIKE '%appreciate%' THEN 'Positive'
            WHEN C.Text ILIKE '%bug%' OR C.Text ILIKE '%error%' OR C.Text ILIKE '%problem%' THEN 'Negative'
            WHEN C.Text ILIKE '%feature%' OR C.Text ILIKE '%suggestion%' THEN 'Suggestion'
            ELSE 'Neutral'
        END AS SentimentCategory,
        ROW_NUMBER() OVER (PARTITION BY C.UserId ORDER BY C.CreationDate DESC) AS rn
    FROM Comments AS C
    WHERE C.UserId IS NOT NULL
)
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.UserCreationDate,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.TotalComments,
    UE.TotalQuestionScore,
    UE.TotalAnswerScore,
    UE.TotalQuestionViews,
    COALESCE(UE.AveragePositiveCommentScore, 0.0) AS AveragePositiveCommentScore,
    COALESCE(BS.GoldBadges, 0) AS GoldBadges,
    COALESCE(BS.SilverBadges, 0) AS SilverBadges,
    COALESCE(BS.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(UPHS.TotalEditCount, 0) AS UserTotalEditCount,
    COALESCE(UPHS.NonStandardCloseVoteCount, 0) AS UserNonStandardCloseVoteCount,
    (UE.Reputation * 0.1)
    + (UE.TotalQuestions * 0.5)
    + (UE.TotalAnswers * 0.3)
    + (COALESCE(BS.SilverBadges, 0) * 10)
    + (COALESCE(BS.GoldBadges, 0) * 50)
    + (CASE WHEN UE.TotalComments > 0 AND UE.AveragePositiveCommentScore IS NOT NULL THEN UE.AveragePositiveCommentScore * 0.2 ELSE 0 END)
    - (CASE WHEN COALESCE(UPHS.NonStandardCloseVoteCount, 0) > 0 THEN UPHS.NonStandardCloseVoteCount * 5 ELSE 0 END)
    AS CompositeActivityScore,
    RANK() OVER (ORDER BY (UE.Reputation + UE.TotalQuestions * 5 + UE.TotalAnswers * 3 + COALESCE(BS.GoldBadges, 0) * 100 + COALESCE(BS.SilverBadges, 0) * 50) DESC) AS OverallActivityRank,
    (SELECT AVG(P_Inner.Score) FROM Posts P_Inner WHERE P_Inner.OwnerUserId = UE.UserId AND P_Inner.PostTypeId = 1 AND P_Inner.CreationDate BETWEEN '2020-01-01' AND '2023-01-01') AS AvgQuestionScore2020_2022,
    RP.PostTitle AS RecentQuestionTitle,
    RP.PostCreationDate AS RecentQuestionCreationDate,
    LEAD(UE.CreationDate, 1) OVER (ORDER BY UE.CreationDate) AS NextUserCreationDate, -- Creation date of the next user in chronological order
    COALESCE(UVS.TotalUpVotesGiven, 0) AS TotalUpVotesGiven,
    COALESCE(UVS.TotalDownVotesGiven, 0) AS TotalDownVotesGiven,
    COALESCE(UVS.TotalFavoritesGiven, 0) AS TotalFavoritesGiven,
    UCS.RecentCommentText,
    UCS.SentimentCategory AS RecentCommentSentiment,
    (
        SELECT STRING_AGG(DISTINCT T.TagName, ', ') -- Concatenates the top 3 tags by aggregated score and post count
        FROM AggregatedTagStats AS ATS_inner
        WHERE ATS_inner.UserId = UE.UserId
        ORDER BY ATS_inner.TagScoreSum DESC, ATS_inner.TagPostCount DESC
        LIMIT 3
    ) AS Top3TagsByScoreAndCount,
    ROUND(CAST(UE.TotalQuestionViews AS NUMERIC) / GREATEST(UE.TotalQuestions, 1), 2) AS AvgViewsPerQuestion,
    EXTRACT(EPOCH FROM (COALESCE(UE.LastCommentDate, UE.UserCreationDate) - UE.UserCreationDate)) / 86400.0 AS DaysSinceUserCreationToLastComment
FROM UserEngagement AS UE
LEFT JOIN BadgeSummary AS BS ON UE.UserId = BS.UserId
LEFT JOIN UserPostHistorySummary AS UPHS ON UE.UserId = UPHS.UserId
LEFT JOIN RecentPostActivity AS RP ON UE.UserId = RP.UserId AND RP.rn = 1
LEFT JOIN UserVoteSummary AS UVS ON UE.UserId = UVS.UserId
LEFT JOIN UserCommentSentiment AS UCS ON UE.UserId = UCS.UserId AND UCS.rn = 1
WHERE
    UE.Reputation > (SELECT AVG(Reputation) FROM Users) -- Filter for users with reputation above global average
    AND UE.TotalQuestions >= 5
    AND UE.TotalAnswers >= 5
    AND (COALESCE(BS.SilverBadges, 0) + COALESCE(BS.GoldBadges, 0)) >= 1
    AND UE.UserCreationDate >= '2015-01-01' -- Filter for more recent active users
    AND (
        SELECT COUNT(P_closed.Id) -- Correlated subquery to ensure at least one non-standard closed question
        FROM Posts AS P_closed
        INNER JOIN PostHistory AS PH_closed ON P_closed.Id = PH_closed.PostId
        WHERE P_closed.OwnerUserId = UE.UserId
          AND PH_closed.PostHistoryTypeId = 10
          AND PH_closed.Comment NOT IN ('1', '101', '102', '103', '104', '105') -- Exclude common close reasons
    ) >= 1
ORDER BY OverallActivityRank ASC, UE.Reputation DESC, UE.UserId
LIMIT 500;
