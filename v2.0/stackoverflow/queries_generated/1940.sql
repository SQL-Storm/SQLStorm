-- {"query": "1940.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3829} 

WITH UserBadgeRanked AS (
    -- Identify the most frequent badge class for each user, handling ties by prioritizing Gold, then Silver, then Bronze
    SELECT
        UserId,
        Class,
        COUNT(Id) AS BadgeCount,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY COUNT(Id) DESC, Class ASC) AS rn
    FROM Badges
    GROUP BY UserId, Class
),
UserBadgeSummary AS (
    -- Aggregate badge counts and determine the most awarded badge class for each user
    SELECT
        UBR.UserId,
        (SELECT CASE WHEN Class = 1 THEN 'Gold' WHEN Class = 2 THEN 'Silver' ELSE 'Bronze' END FROM UserBadgeRanked WHERE UserId = UBR.UserId AND rn = 1) AS MostAwardedBadgeClass, -- Correlated subquery for a single value
        COALESCE(SUM(CASE WHEN UBR.Class = 1 THEN UBR.BadgeCount ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN UBR.Class = 2 THEN UBR.BadgeCount ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN UBR.Class = 3 THEN UBR.BadgeCount ELSE 0 END), 0) AS BronzeBadges
    FROM UserBadgeRanked UBR
    GROUP BY UBR.UserId
),
UserEngagement AS (
    -- Summarize user's overall activity, including posts, comments, and voting patterns
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.Views,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalComments,
        MAX(U.LastAccessDate) AS LastActivity
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.Reputation, U.Views, U.UpVotes, U.DownVotes
),
PostHistoryAggregates AS (
    -- Aggregate post history events, including edit counts, close/reopen votes, and specific dates
    SELECT
        PH.PostId,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVoteCount,
        MIN(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate END) AS FirstEditDate,
        MAX(PH.CreationDate) AS LastHistoryEventDate,
        STRING_AGG(DISTINCT SUBSTRING(PH.Comment FROM 1 FOR 50), '; ') FILTER (WHERE PH.Comment IS NOT NULL AND PH.Comment <> '') AS LatestHistoryCommentsSummary,
        (SELECT MAX(ph2.CreationDate)
         FROM PostHistory ph2
         WHERE ph2.PostId = PH.PostId AND ph2.PostHistoryTypeId = 5) AS LastBodyEditDate -- Correlated subquery for specific history type
    FROM PostHistory PH
    GROUP BY PH.PostId
),
PostPerformance AS (
    -- Calculate various performance metrics for individual posts, incorporating window functions and complex logic
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.ClosedDate,
        COALESCE(PHA.EditCount, 0) AS PostEditCount,
        COALESCE(PHA.CloseVoteCount, 0) AS PostCloseVoteCount,
        COALESCE(PHA.ReopenVoteCount, 0) AS PostReopenVoteCount,
        PHA.FirstEditDate,
        PHA.LastBodyEditDate,
        PHA.LatestHistoryCommentsSummary,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId, EXTRACT(MONTH FROM P.CreationDate) ORDER BY P.Score DESC, P.ViewCount DESC) AS PostMonthlyScoreRank,
        CASE
            WHEN P.PostTypeId = 1 AND P.AnswerCount > 0 AND P.AcceptedAnswerId IS NOT NULL THEN 1.0 / P.AnswerCount
            WHEN P.PostTypeId = 1 AND P.AnswerCount > 0 THEN 0.0
            ELSE NULL
        END AS AcceptedAnswerRatio,
        LAG(P.PostTypeId, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostTypeId, -- Window function: previous post type by same user
        LEAD(P.PostTypeId, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS NextPostTypeId, -- Window function: next post type by same user
        CASE WHEN P.ViewCount > 5000 AND P.Score < 5 AND COALESCE(PHA.EditCount, 0) > 3 THEN TRUE ELSE FALSE END AS IsControversialOrUnanswered,
        P.Title IS NULL AS IsTitleNull,
        P.Body IS NULL AS IsBodyNull,
        ARRAY_LENGTH(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><'), 1) AS TagCount, -- String expression for tag parsing
        EXTRACT(EPOCH FROM (PHA.FirstEditDate - P.CreationDate)) / (60 * 60 * 24) AS DaysToFirstEdit, -- Complex date calculation
        (P.ViewCount > 50000 AND P.AnswerCount > 20 AND P.FavoriteCount > 100 AND P.PostTypeId = 1) AS IsHotQuestion
    FROM Posts P
    LEFT JOIN PostHistoryAggregates PHA ON P.Id = PHA.PostId
    WHERE P.OwnerUserId IS NOT NULL
      AND P.PostTypeId IN (1, 2)
      AND P.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
),
RelatedPostAnalysis AS (
    -- Analyze links between posts and aggregate tags from related posts
    SELECT
        PP.PostId,
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPostsCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicatePostsCount,
        STRING_AGG(DISTINCT T.TagName, '; ') FILTER (WHERE T.TagName IS NOT NULL AND T.TagName != '') AS RelatedTagsSummary
    FROM PostPerformance PP
    LEFT JOIN PostLinks PL ON PP.PostId = PL.PostId
    LEFT JOIN Posts LinkedP ON PL.RelatedPostId = LinkedP.Id
    LEFT JOIN LATERAL UNNEST(string_to_array(SUBSTRING(LinkedP.Tags FROM 2 FOR LENGTH(LinkedP.Tags)-2), '><')) AS T(TagName) ON LinkedP.Tags IS NOT NULL AND LENGTH(LinkedP.Tags) > 2
    GROUP BY PP.PostId
),
TagUsageAnalysis AS (
    -- Gather statistics about tags used in posts filtered by PostPerformance
    SELECT
        P.Id AS PostId,
        ARRAY_AGG(DISTINCT T.TagName) FILTER (WHERE T.TagName IS NOT NULL) AS PostTags,
        AVG(TagStats.Count) AS AvgTagPopularity,
        MAX(CASE WHEN T.IsModeratorOnly THEN 1 ELSE 0 END) AS HasModeratorOnlyTag
    FROM Posts P
    LEFT JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><')) AS TagName_UNNEST(TagName) ON P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    LEFT JOIN Tags T ON TagName_UNNEST.TagName = T.TagName
    LEFT JOIN Tags TagStats ON TagName_UNNEST.TagName = TagStats.TagName
    WHERE P.Id IN (SELECT PostId FROM PostPerformance)
    GROUP BY P.Id
)
-- Main query path 1: Identify highly engaged and influential users
SELECT
    U.Id AS UserId,
    U.DisplayName,
    UE.Reputation,
    UE.Views AS UserViews,
    UE.TotalPosts,
    UE.QuestionCount,
    UE.AnswerCount,
    UE.TotalPostScore,
    UE.TotalComments AS UserComments,
    UBS.MostAwardedBadgeClass,
    UBS.GoldBadges,
    UBS.SilverBadges,
    UBS.BronzeBadges,
    AVG(PP.Score) AS AvgPostScore,
    AVG(PP.ViewCount) AS AvgPostViewCount,
    SUM(PP.PostEditCount) AS TotalPostEdits,
    SUM(CASE WHEN PP.IsControversialOrUnanswered THEN 1 ELSE 0 END) AS ControversialPostsCount,
    MAX(PP.LastActivityDate) AS LatestPostActivity,
    MAX(PP.LastBodyEditDate) AS LatestBodyEditAcrossPosts,
    COALESCE(SUM(RPA.LinkedPostsCount), 0) AS TotalLinkedPosts,
    COALESCE(SUM(RPA.DuplicatePostsCount), 0) AS TotalDuplicatePosts,
    MAX(TUA.HasModeratorOnlyTag) FILTER (WHERE TUA.HasModeratorOnlyTag = 1) AS HasModeratorTagsInAnyPost,
    STRING_AGG(DISTINCT RPA.RelatedTagsSummary, '; ') AS AllRelatedTagsSummary,
    CAST(COALESCE(SUM(PP.FavoriteCount), 0) AS DECIMAL) / (COALESCE(SUM(PP.ViewCount), 0) + 1) AS FavoriteToViewRatio,
    CAST(COALESCE(SUM(PP.PostCloseVoteCount), 0) AS DECIMAL) / (COALESCE(SUM(PP.PostEditCount), 0) + 1) AS CloseVoteToEditRatio,
    CASE
        WHEN UE.Reputation > 75000 AND UE.TotalPosts > 750 AND UE.TotalPostScore > 2000 AND UBS.GoldBadges >= 5 THEN 'Distinguished Expert'
        WHEN UE.Reputation > 25000 AND UE.TotalPosts > 250 AND UE.TotalPostScore > 1000 AND UBS.SilverBadges >= 10 THEN 'High Impact Contributor'
        WHEN UE.Reputation > 5000 AND UE.TotalPosts > 50 AND UE.TotalPostScore > 200 THEN 'Active Community Member'
        ELSE 'General Participant'
    END AS UserCategory,
    'Main Analysis' AS QueryPathIdentifier
FROM Users U
JOIN UserEngagement UE ON U.Id = UE.UserId
LEFT JOIN UserBadgeSummary UBS ON U.Id = UBS.UserId
LEFT JOIN PostPerformance PP ON U.Id = PP.OwnerUserId
LEFT JOIN RelatedPostAnalysis RPA ON PP.PostId = RPA.PostId
LEFT JOIN TagUsageAnalysis TUA ON PP.PostId = TUA.PostId
WHERE
    UE.Reputation > 1500
    AND UE.TotalPosts > 10
    AND PP.PostMonthlyScoreRank <= 5
    AND (U.Location IS NOT NULL OR U.WebsiteUrl IS NOT NULL OR U.AboutMe IS NOT NULL)
    AND (UE.UserUpVotesGiven > UE.UserDownVotesGiven * 3 OR UBS.GoldBadges > 0)
GROUP BY
    U.Id, U.DisplayName, UE.Reputation, UE.Views, UE.TotalPosts, UE.QuestionCount,
    UE.AnswerCount, UE.TotalPostScore, UE.TotalComments, UBS.MostAwardedBadgeClass,
    UBS.GoldBadges, UBS.SilverBadges, UBS.BronzeBadges, U.Location, U.WebsiteUrl, U.AboutMe,
    UE.UserUpVotesGiven, UE.UserDownVotesGiven
HAVING
    COUNT(DISTINCT PP.PostId) > 2
    AND AVG(PP.PostEditCount) > 1.0
    AND SUM(CASE WHEN PP.IsHotQuestion THEN 1 ELSE 0 END) >= 0
    AND (SUM(PP.PostCloseVoteCount) = 0 OR AVG(PP.PostReopenVoteCount) > 0.3)

UNION ALL

-- Main query path 2: Identify users associated with controversial/highly dynamic posts, potentially less active overall
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.Views AS UserViews,
    COUNT(P.Id) AS TotalPosts,
    SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    COALESCE(SUM(P.Score), 0) AS TotalPostScore,
    COALESCE(SUM(CASE WHEN C.UserId = P.OwnerUserId THEN 1 ELSE 0 END), 0) AS UserComments, -- Comments by the owner on these specific posts
    NULL AS MostAwardedBadgeClass,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    NULL AS BronzeBadges,
    AVG(P.Score) AS AvgPostScore,
    AVG(P.ViewCount) AS AvgPostViewCount,
    SUM(PHA.EditCount) AS TotalPostEdits,
    SUM(CASE WHEN PP.IsControversialOrUnanswered THEN 1 ELSE 0 END) AS ControversialPostsCount,
    MAX(P.LastActivityDate) AS LatestPostActivity,
    MAX(PHA.LastBodyEditDate) AS LatestBodyEditAcrossPosts,
    COALESCE(SUM(RPA.LinkedPostsCount), 0) AS TotalLinkedPosts,
    COALESCE(SUM(RPA.DuplicatePostsCount), 0) AS TotalDuplicatePosts,
    MAX(TUA.HasModeratorOnlyTag) FILTER (WHERE TUA.HasModeratorOnlyTag = 1) AS HasModeratorTagsInAnyPost,
    STRING_AGG(DISTINCT RPA.RelatedTagsSummary, '; ') AS AllRelatedTagsSummary,
    CAST(COALESCE(SUM(P.FavoriteCount), 0) AS DECIMAL) / (COALESCE(SUM(P.ViewCount), 0) + 1) AS FavoriteToViewRatio,
    CAST(COALESCE(SUM(PHA.CloseVoteCount), 0) AS DECIMAL) / (COALESCE(SUM(PHA.EditCount), 0) + 1) AS CloseVoteToEditRatio,
    'Controversial Post Owner' AS UserCategory,
    'Controversial Analysis' AS QueryPathIdentifier
FROM Posts P
JOIN Users U ON P.OwnerUserId = U.Id
LEFT JOIN Comments C ON P.Id = C.PostId
LEFT JOIN PostHistoryAggregates PHA ON P.Id = PHA.PostId
LEFT JOIN PostPerformance PP ON P.Id = PP.PostId
LEFT JOIN RelatedPostAnalysis RPA ON P.Id = RPA.PostId
LEFT JOIN TagUsageAnalysis TUA ON P.Id = TUA.PostId
WHERE
    P.OwnerUserId IS NOT NULL
    AND (PP.IsControversialOrUnanswered = TRUE
         OR (P.ClosedDate IS NOT NULL AND COALESCE(PHA.CloseVoteCount, 0) > 2 AND COALESCE(PHA.ReopenVoteCount, 0) = 0))
    AND P.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
GROUP BY
    U.Id, U.DisplayName, U.Reputation, U.Views
HAVING
    COUNT(P.Id) >= 1
    AND SUM(P.Score) < 0
    AND AVG(P.CommentCount) > 1
ORDER BY
    Reputation DESC, TotalPostScore DESC;
