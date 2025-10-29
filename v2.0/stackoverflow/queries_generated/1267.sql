-- {"query": "1267.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2883} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        COALESCE(U.Location, 'Unknown Location') AS UserLocation,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 1) AS GoldBadgesCount,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 2) AS SilverBadgesCount,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 3) AS BronzeBadgesCount,
        SUM(CASE WHEN VT.Name = 'UpMod' THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN VT.Name = 'DownMod' THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
        SUM(CASE WHEN VT.Name = 'Favorite' THEN 1 ELSE 0 END) AS TotalFavoritesOnUserPosts,
        MAX(V.CreationDate) AS LastVoteReceivedDate
    FROM Users AS U
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    LEFT JOIN Posts AS P_UserPosts ON U.Id = P_UserPosts.OwnerUserId
    LEFT JOIN Votes AS V ON P_UserPosts.Id = V.PostId
    LEFT JOIN VoteTypes AS VT ON V.VoteTypeId = VT.Id
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location,
        U.Views, U.UpVotes, U.DownVotes
),
PostHistoryAgg AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN PHT.Name LIKE '%Edit%' THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN PHT.Name LIKE '%Rollback%' THEN 1 ELSE 0 END) AS RollbackCount,
        SUM(CASE WHEN PHT.Name = 'Post Closed' THEN 1 ELSE 0 END) AS CloseEventsCount,
        SUM(CASE WHEN PHT.Name = 'Post Reopened' THEN 1 ELSE 0 END) AS ReopenEventsCount,
        MAX(PH.CreationDate) AS LastHistoryActivityDate,
        MIN(PH.CreationDate) AS FirstHistoryActivityDate,
        COUNT(DISTINCT PH.UserId) FILTER (WHERE PH.UserId IS NOT NULL) AS DistinctEditors
    FROM PostHistory AS PH
    JOIN PostHistoryTypes AS PHT ON PH.PostHistoryTypeId = PHT.Id
    GROUP BY PH.PostId
),
PostTagEngagement AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.Title,
        P.Tags,
        P.AcceptedAnswerId,
        P.ClosedDate,
        P.LastActivityDate,
        COALESCE(P.CommunityOwnedDate, '9999-12-31 23:59:59') AS CommunityOwnedDateEffective, -- Using a sentinel value for non-community owned posts
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(COALESCE(P.Tags, '<>'), 2, LENGTH(COALESCE(P.Tags, '<>'))-2), '><'), 1) AS TagCount,
        CASE
            WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            WHEN P.PostTypeId = 1 AND P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NULL AND P.AnswerCount > 0 THEN 'Unaccepted_Answered'
            WHEN P.PostTypeId = 1 AND P.AnswerCount = 0 THEN 'Unanswered'
            ELSE 'N/A'
        END AS QuestionStatus,
        SUM(C.Score) AS TotalCommentScore,
        COUNT(DISTINCT C.Id) AS DistinctComments,
        (SELECT COUNT(PL.Id) FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 1) AS LinkedFromPostsCount,
        (SELECT COUNT(PL.Id) FROM PostLinks PL WHERE PL.RelatedPostId = P.Id AND PL.LinkTypeId = 1) AS LinkedToPostsCount,
        (SELECT COUNT(PL.Id) FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 3) AS DuplicatesCount,
        (SELECT AVG(Score) FROM Comments WHERE PostId = P.Id AND UserId IS NOT NULL AND Score > 0) AS AvgPositiveCommentScoreByUser,
        NTILE(4) OVER (ORDER BY P.Score DESC, P.ViewCount DESC) AS PostScoreViewQuartile
    FROM Posts AS P
    JOIN PostTypes AS PT ON P.PostTypeId = PT.Id
    LEFT JOIN Comments AS C ON P.Id = C.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY
        P.Id, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount,
        P.FavoriteCount, P.PostTypeId, PT.Name, P.Title, P.Tags, P.AcceptedAnswerId,
        P.ClosedDate, P.LastActivityDate, P.CommunityOwnedDate
),
RecentActiveUsers AS (
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.UserLastAccessDate,
        RANK() OVER (ORDER BY UE.Reputation DESC, UE.UserLastAccessDate DESC) AS OverallReputationRank
    FROM UserEngagement UE
    WHERE UE.UserLastAccessDate >= NOW() - INTERVAL '6 months'
),
HighImpactPosts AS (
    SELECT PostId, OwnerUserId, PostScore, ViewCount, PostTypeName, QuestionStatus
    FROM PostTagEngagement
    WHERE PostTypeId = 1 AND PostScore > 50 AND AnswerCount >= 5 -- High score questions with many answers
    UNION ALL
    SELECT PostId, OwnerUserId, PostScore, ViewCount, PostTypeName, QuestionStatus
    FROM PostTagEngagement
    WHERE PostTypeId = 2 AND PostScore > 30 AND PostCreationDate > NOW() - INTERVAL '1 year' -- Recent high score answers
),
TagAnalysis AS (
    SELECT
        T.TagName,
        COUNT(P.Id) AS TotalPostsWithTag,
        AVG(P.Score) AS AvgScoreForTag,
        MAX(P.CreationDate) AS LastUsedDate,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCountWithTag
    FROM Tags AS T
    JOIN Posts AS P ON P.Tags LIKE '%' || T.TagName || '%' -- Using LIKE for tag matching
    GROUP BY T.TagName
    HAVING COUNT(P.Id) > 100 -- Only consider tags used in many posts
)
-- Main query combining all CTEs and adding more complex logic
SELECT
    RAU.UserId,
    RAU.DisplayName,
    RAU.OverallReputationRank,
    UE.Reputation AS UserReputation,
    UE.GoldBadgesCount,
    UE.SilverBadgesCount,
    UE.BronzeBadgesCount,
    UE.UserProfileViews,
    UE.TotalUpvotesReceived,
    UE.TotalDownvotesReceived,
    UE.TotalFavoritesOnUserPosts,
    COUNT(DISTINCT PTE.PostId) AS TotalPostsByThisUser,
    COUNT(DISTINCT PTE.PostId) FILTER (WHERE PTE.PostTypeId = 1) AS TotalQuestionsByThisUser,
    COUNT(DISTINCT PTE.PostId) FILTER (WHERE PTE.PostTypeId = 2) AS TotalAnswersByThisUser,
    AVG(PTE.PostScore) AS AvgPostScoreByUser,
    SUM(PTE.TotalCommentScore) AS TotalCommentScoreOnUserPosts,
    MAX(PTE.LastActivityDate) AS LastUserPostActivity,
    (SELECT AVG(P_sub.Score)
     FROM Posts AS P_sub
     WHERE P_sub.OwnerUserId = RAU.UserId
       AND P_sub.PostTypeId = 1
       AND P_sub.CreationDate BETWEEN RAU.UserCreationDate AND RAU.UserCreationDate + INTERVAL '1 year'
    ) AS AvgQuestionScoreFirstYear,
    SUM(CASE WHEN PTE.QuestionStatus = 'Accepted' THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
    SUM(CASE WHEN PTE.QuestionStatus = 'Closed' THEN 1 ELSE 0 END) AS ClosedQuestionsCount,
    AVG(PH.EditCount) AS AvgEditsPerPost,
    AVG(PH.CloseEventsCount) AS AvgCloseEventsPerPost,
    SUM(CASE WHEN HIP.PostId IS NOT NULL THEN 1 ELSE 0 END) AS ElitePostsCount,
    STRING_AGG(DISTINCT TA.TagName, ', ') FILTER (WHERE TA.TotalPostsWithTag > 500 AND TA.QuestionCountWithTag > 100) AS HighlyUsedTags,
    (
        SELECT COUNT(DISTINCT PL.RelatedPostId)
        FROM Posts P_inner
        JOIN PostLinks PL ON P_inner.Id = PL.PostId
        WHERE P_inner.OwnerUserId = RAU.UserId AND PL.LinkTypeId = 1
    ) AS TotalPostsLinkedByThisUser,
    -- Complicated calculation with NULL logic
    COALESCE(NULLIF(CAST(UE.TotalUpvotesReceived AS NUMERIC), 0) / NULLIF(UE.TotalDownvotesReceived, 0), 0) AS UpvoteToDownvoteRatio,
    COALESCE(NULLIF(CAST(UE.Reputation AS NUMERIC), 0) / NULLIF(UE.UserProfileViews, 0), 0) AS ReputationPerViewRatio,
    PERCENT_RANK() OVER (ORDER BY AVG(PTE.PostScore) DESC) AS PostScorePercentRank,
    -- Example of a string expression combined with NULL logic and date arithmetic
    LOWER(SUBSTRING(COALESCE(UE.DisplayName, 'anonymous'), 1, 10) || '-' || TO_CHAR(UE.UserCreationDate, 'YYYYMMDD')) AS UserIdentifierHashFragment,
    -- Additional check for community owned status, using NULL logic
    COUNT(DISTINCT PTE.PostId) FILTER (WHERE PTE.CommunityOwnedDateEffective < NOW() - INTERVAL '2 years' AND PTE.CommunityOwnedDateEffective <> '9999-12-31 23:59:59') AS OldCommunityOwnedPosts
FROM RecentActiveUsers AS RAU
JOIN UserEngagement AS UE ON RAU.UserId = UE.UserId
LEFT JOIN PostTagEngagement AS PTE ON RAU.UserId = PTE.OwnerUserId
LEFT JOIN PostHistoryAgg AS PH ON PTE.PostId = PH.PostId
LEFT JOIN HighImpactPosts AS HIP ON PTE.PostId = HIP.PostId
LEFT JOIN (
    SELECT DISTINCT TagName, TotalPostsWithTag, QuestionCountWithTag
    FROM TagAnalysis
    WHERE TotalPostsWithTag > 500 AND QuestionCountWithTag > 100
) AS TA ON PTE.Tags LIKE '%' || TA.TagName || '%'
GROUP BY
    RAU.UserId, RAU.DisplayName, RAU.OverallReputationRank, UE.Reputation, UE.GoldBadgesCount,
    UE.SilverBadgesCount, UE.BronzeBadgesCount, UE.UserProfileViews, UE.TotalUpvotesReceived,
    UE.TotalDownvotesReceived, UE.TotalFavoritesOnUserPosts, UE.UserCreationDate, UE.DisplayName
HAVING
    COUNT(DISTINCT PTE.PostId) > 5 -- At least 5 posts by the user
    AND UE.Reputation > 1000 -- User must have significant reputation
    AND (SUM(COALESCE(PTE.PostScore, 0)) > 200 OR SUM(COALESCE(PTE.ViewCount, 0)) > 1000) -- User's posts must have overall impact
ORDER BY
    UE.Reputation DESC, TotalPostsByThisUser DESC, AvgPostScoreByUser DESC
LIMIT 100;
