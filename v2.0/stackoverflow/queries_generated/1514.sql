-- {"query": "1514.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2623} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Location,
        U.AboutMe,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersCreated,
        COUNT(DISTINCT C.Id) AS TotalCommentsAuthored,
        COUNT(DISTINCT B.Id) AS TotalBadgesEarned,
        SUM(P.Score) AS TotalScoreOnOwnedPosts,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score END) AS AvgAnswerScore,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC, U.LastAccessDate DESC) AS UserReputationRank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location, U.AboutMe, U.Views, U.UpVotes, U.DownVotes
),
PostAggregatedStats AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS InitialScore,
        P.ViewCount,
        P.Title,
        P.Tags,
        P.AcceptedAnswerId,
        P.ParentId,
        P.LastEditDate,
        P.ClosedDate,
        COUNT(DISTINCT C.Id) AS ActualCommentCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCountFromVotes,
        MAX(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS HasAcceptedAnswer,
        COALESCE(P.AnswerCount, 0) AS StoredAnswerCount
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.Title, P.Tags, P.AcceptedAnswerId, P.ParentId, P.LastEditDate, P.ClosedDate
),
PostHistorySummaryExtended AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS ContentEditCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVoteCount,
        MAX(PH.CreationDate) AS LastHistoryEventDate,
        -- Check for close reasons 101 (Duplicate) or 102 (Off-topic) in Comment field of PostHistory table
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 AND (PH.Comment LIKE '101%' OR PH.Comment LIKE '102%') THEN 1 ELSE 0 END) AS IsClosedByDuplicateOrOffTopic
    FROM PostHistory PH
    GROUP BY PH.PostId
),
ExpandedTags AS (
    SELECT
        P.Id AS PostId,
        LOWER(TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')))) AS TagName
    FROM Posts P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
TagUsageRank AS (
    SELECT
        ET.TagName,
        COUNT(DISTINCT ET.PostId) AS TaggedPostCount,
        SUM(PAS.UpVoteCount) AS TagTotalUpVotes,
        AVG(PAS.InitialScore) AS TagAvgPostScore,
        RANK() OVER (ORDER BY COUNT(DISTINCT ET.PostId) DESC, SUM(PAS.UpVoteCount) DESC) AS TagPopularityRank
    FROM ExpandedTags ET
    JOIN PostAggregatedStats PAS ON ET.PostId = PAS.PostId
    GROUP BY ET.TagName
),
BaseQueryResult AS (
    SELECT
        UE.UserId,
        UE.DisplayName AS OwnerName,
        UE.Reputation AS OwnerReputation,
        UE.UserReputationRank,
        PAS.PostId,
        PAS.Title AS PostTitle,
        PAS.PostTypeId,
        CASE
            WHEN PAS.PostTypeId = 1 THEN 'Question'
            WHEN PAS.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeDescription,
        PAS.PostCreationDate,
        PAS.InitialScore AS PostInitialScore,
        PAS.ViewCount AS PostViewCount,
        PAS.UpVoteCount,
        PAS.DownVoteCount,
        PAS.ActualCommentCount,
        COALESCE(PAS.FavoriteCountFromVotes, 0) AS TotalFavorites,
        PHSE.ContentEditCount AS PostEditCount,
        PHSE.CloseVoteCount AS PostCloseEvents,
        PHSE.ReopenVoteCount AS PostReopenEvents,
        PHSE.LastHistoryEventDate,
        TR.TagName AS TopRelatedTag,
        TR.TaggedPostCount AS TopRelatedTagUsage,
        TR.TagTotalUpVotes AS TopRelatedTagUpVotes,
        (PAS.UpVoteCount - PAS.DownVoteCount) AS NetVotes,
        (PAS.ViewCount * 1.0 / NULLIF(EXTRACT(EPOCH FROM (NOW() - PAS.PostCreationDate)) / (60*60*24), 0)) AS ViewsPerDay,
        -- Correlated Subquery: Check if an owner has edited their own post after initial creation
        (SELECT COUNT(DISTINCT PH.Id)
         FROM PostHistory PH
         WHERE PH.PostId = PAS.PostId
           AND PH.UserId = PAS.OwnerUserId
           AND PH.PostHistoryTypeId IN (4,5,6) -- Edit Title, Body, Tags
           AND PH.CreationDate > PAS.PostCreationDate
        ) AS OwnerSelfEditCount,
        -- Window function: Rank posts by net votes within owner's posts
        RANK() OVER (PARTITION BY UE.UserId ORDER BY (PAS.UpVoteCount - PAS.DownVoteCount) DESC, PAS.PostCreationDate DESC) AS PostRankByNetVotesForOwner,
        -- Window function: NTILE to categorize posts into 5 performance groups based on InitialScore
        NTILE(5) OVER (ORDER BY PAS.InitialScore DESC, PAS.UpVoteCount DESC) AS PostScoreQuintile,
        -- NULL logic: Display custom string if AboutMe is NULL or empty, else first 50 chars
        COALESCE(LEFT(UE.AboutMe, 50), 'No description available for this user.') AS OwnerAboutMeSnippet,
        -- Complex Predicate: Categorize posts based on multiple conditions
        CASE
            WHEN PAS.PostTypeId = 1 AND PAS.ViewCount > 5000 AND PHSE.ContentEditCount > 5 THEN 'Highly Engaged Question'
            WHEN PAS.PostTypeId = 2 AND PAS.InitialScore > 100 AND PAS.HasAcceptedAnswer = 1 AND PAS.UpVoteCount > COALESCE(PAS.DownVoteCount * 5, 0) THEN 'Exceptional Accepted Answer'
            WHEN PAS.PostTypeId = 1 AND PAS.ClosedDate IS NOT NULL AND PHSE.IsClosedByDuplicateOrOffTopic = 1 THEN 'Problematic Duplicate/Off-Topic Question'
            WHEN PAS.PostTypeId = 2 AND (PAS.UpVoteCount * 1.0 / NULLIF(PAS.DownVoteCount, 0.0) >= 10 AND PAS.UpVoteCount >= 50) THEN 'High-Ratio Answer'
            ELSE 'General Content'
        END AS PostCategory,
        ((PAS.UpVoteCount + PAS.DownVoteCount + PAS.ActualCommentCount) * 1.0 / NULLIF(PAS.ViewCount, 0)) AS EngagementRatio,
        PAS.ClosedDate IS NOT NULL AS IsPostClosed,
        -- String expression: Extract first tag from Tags string
        SUBSTRING(PAS.Tags FROM 2 FOR POSITION('><' IN PAS.Tags) - 2) AS FirstTagInList
    FROM PostAggregatedStats PAS
    JOIN UserEngagement UE ON PAS.OwnerUserId = UE.UserId
    LEFT JOIN PostHistorySummaryExtended PHSE ON PAS.PostId = PHSE.PostId
    LEFT JOIN ( -- Lateral join equivalent for top tag per post
        SELECT
            ET.PostId,
            TR.TagName,
            TR.TaggedPostCount,
            TR.TagTotalUpVotes,
            ROW_NUMBER() OVER(PARTITION BY ET.PostId ORDER BY TR.TaggedPostCount DESC, TR.TagTotalUpVotes DESC, TR.TagName) as rn
        FROM ExpandedTags ET
        JOIN TagUsageRank TR ON ET.TagName = TR.TagName
    ) AS TR ON PAS.PostId = TR.PostId AND TR.rn = 1
    WHERE PAS.OwnerUserId IS NOT NULL -- Exclude posts by the community user for user-centric analysis
)
-- Main query with UNION ALL to combine different criteria for benchmarking
SELECT * FROM BaseQueryResult
WHERE
    PostTypeDescription = 'Question'
    AND PostViewCount > 1000
    AND PostInitialScore > 10
    AND PostEditCount > 2
    AND NOT IsPostClosed
    AND FirstTagInList LIKE 'sql%'
    AND OwnerReputationRank <= 1000
UNION ALL
SELECT * FROM BaseQueryResult
WHERE
    PostTypeDescription = 'Answer'
    AND PostInitialScore > 50
    AND TotalFavorites > 5
    AND PostRankByNetVotesForOwner <= 10
    AND OwnerReputation > 5000
    AND EngagementRatio > 0.05
    AND OwnerAboutMeSnippet NOT LIKE '%developer%'
    AND PostCreationDate > (NOW() - INTERVAL '2 years')
ORDER BY
    OwnerReputation DESC,
    NetVotes DESC,
    PostCreationDate DESC
LIMIT 200;
