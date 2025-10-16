-- {"query": "19054.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3762} 

WITH UserActivitySummary AS (
    -- Summarizes user post and comment activity, including score and view metrics
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT C.Id) AS TotalCommentsOnOwnPosts,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostViews,
        COALESCE(AVG(P.Score) FILTER (WHERE P.PostTypeId IN (1,2)), 0.0) AS AvgPostScore,
        COALESCE(AVG(P.ViewCount) FILTER (WHERE P.PostTypeId = 1), 0.0) AS AvgQuestionViews,
        MAX(P.CreationDate) AS LastPostCreationDate,
        MIN(P.CreationDate) AS FirstPostCreationDate
    FROM
        Posts P
    LEFT JOIN
        Comments C ON P.Id = C.PostId AND P.OwnerUserId = C.UserId -- Comments made on their own posts
    WHERE
        P.OwnerUserId IS NOT NULL
    GROUP BY
        P.OwnerUserId
),
PostTagAnalysis AS (
    -- Analyzes tags associated with questions and their average scores, unnesting tags for easier processing
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate,
        P.LastActivityDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        STRING_TO_ARRAY(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><') AS TagArray,
        CASE
            WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL AND P.FavoriteCount >= 5 AND P.Score >= 10 THEN 'HighlyEngagedQuestion'
            WHEN P.PostTypeId = 2 AND P.ParentId IS NOT NULL AND P.Score >= 5 THEN 'ValuableAnswer'
            ELSE 'OtherPost'
        END AS PostEngagementCategory,
        (EXTRACT(EPOCH FROM (NOW() - P.CreationDate)) / (60 * 60 * 24)) AS DaysSinceCreation,
        (EXTRACT(EPOCH FROM (NOW() - P.LastActivityDate)) / (60 * 60 * 24)) AS DaysSinceLastActivity
    FROM
        Posts P
    WHERE
        P.PostTypeId IN (1, 2) AND P.OwnerUserId IS NOT NULL AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
UserBadgeStats AS (
    -- Counts various badge types for users
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LatestBadgeDate
    FROM
        Badges B
    GROUP BY
        B.UserId
),
UserPostHistoryAgg AS (
    -- Aggregates various post history events for posts owned by a user
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(PH.Id) AS TotalPostHistoryEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS PostEditHistoryCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10) THEN 1 ELSE 0 END) AS PostClosedHistoryCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (11) THEN 1 ELSE 0 END) AS PostReopenedHistoryCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (12,13) THEN 1 ELSE 0 END) AS PostDeletedUndeletedHistoryCount,
        STRING_AGG(DISTINCT CR.Name, '; ' ORDER BY CR.Name) FILTER (WHERE PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL AND CR.Id IS NOT NULL) AS ClosedReasonNamesSummary
    FROM
        PostHistory PH
    JOIN
        Posts P ON PH.PostId = P.Id
    LEFT JOIN
        CloseReasonTypes CR ON PH.PostHistoryTypeId = 10 AND PH.Comment = CR.Id::varchar -- Joining on string representation for CloseReasonTypes
    WHERE
        P.OwnerUserId IS NOT NULL
    GROUP BY
        P.OwnerUserId
),
UserReputationRanks AS (
    -- Ranks users based on their reputation and upvotes
    SELECT
        Id AS UserId,
        Reputation,
        UpVotes,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, UpVotes DESC) AS ReputationRank,
        NTILE(10) OVER (ORDER BY Reputation DESC) AS ReputationDecile
    FROM
        Users
    WHERE
        Reputation > 0
),
ModeratorActivityCandidates AS (
    -- Collects users who have participated in moderation-related PostHistory events
    SELECT DISTINCT UserId
    FROM PostHistory
    WHERE PostHistoryTypeId IN (10, 11, 14, 15, 19, 20) -- Closed, Reopened, Locked, Unlocked, Protected, Unprotected
      AND UserId IS NOT NULL
),
UserLinkInteraction AS (
    -- Summarize linked and duplicated posts involving user's content
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 1 THEN PL.RelatedPostId END) AS LinkedPostsCount,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId END) AS DuplicateSourcePostsCount
    FROM
        Posts P
    JOIN
        PostLinks PL ON P.Id = PL.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY
        P.OwnerUserId
)
-- Main query to combine all insights
SELECT
    U.Id AS UserIdentifier,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserRegistrationDate,
    U.LastAccessDate,
    COALESCE(UAS.TotalPosts, 0) AS UserTotalPosts,
    COALESCE(UAS.QuestionCount, 0) AS UserQuestionCount,
    COALESCE(UAS.AnswerCount, 0) AS UserAnswerCount,
    COALESCE(UAS.TotalCommentsOnOwnPosts, 0) AS UserTotalCommentsOnTheirPosts,
    COALESCE(UAS.TotalPostScore, 0) AS UserTotalPostScore,
    COALESCE(UAS.AvgPostScore, 0.0) AS UserAvgPostScore,
    COALESCE(UAS.AvgQuestionViews, 0.0) AS UserAvgQuestionViews,
    COALESCE(UBS.TotalBadges, 0) AS UserTotalBadges,
    COALESCE(UBS.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS UserSilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS UserBronzeBadges,
    COALESCE(UPHA.TotalPostHistoryEvents, 0) AS UserPostHistoryActivityCount,
    COALESCE(UPHA.PostEditHistoryCount, 0) AS UserPostEditCount,
    COALESCE(UPHA.PostClosedHistoryCount, 0) AS UserPostClosedCount,
    COALESCE(UPHA.PostReopenedHistoryCount, 0) AS UserPostReopenedCount,
    UPHA.ClosedReasonNamesSummary AS LatestClosedReasonSummary, -- String aggregation with NULL handling
    COALESCE(RR.ReputationRank, (SELECT MAX(ReputationRank) + 1 FROM UserReputationRanks)) AS GlobalReputationRank, -- NULL handling for rank
    COALESCE(RR.ReputationDecile, 11) AS GlobalReputationDecile,
    EXISTS (SELECT 1 FROM ModeratorActivityCandidates MAC WHERE MAC.UserId = U.Id) AS HasPerformedModerationAction, -- Correlated subquery for boolean check
    COALESCE(ULI.LinkedPostsCount, 0) AS LinkedPostsCountByThisUser,
    COALESCE(ULI.DuplicateSourcePostsCount, 0) AS DuplicateSourcePostsCountByThisUser,
    COALESCE(
        (SELECT COUNT(DISTINCT unnest_tags.tag_val)
         FROM PostTagAnalysis pta_tags
         JOIN LATERAL UNNEST(pta_tags.TagArray) AS unnest_tags(tag_val) ON TRUE
         WHERE pta_tags.OwnerUserId = U.Id
           AND pta_tags.PostEngagementCategory = 'HighlyEngagedQuestion'
           AND unnest_tags.tag_val IS NOT NULL
        ), 0
    ) AS UniqueTagsInHighlyEngagedQuestions,
    COALESCE(
        (SELECT AVG(CAST(V.BountyAmount AS NUMERIC))
         FROM Votes V
         WHERE V.UserId = U.Id AND V.VoteTypeId = 8 AND V.BountyAmount IS NOT NULL),
    0.0) AS AvgBountyStarted,
    (
        SELECT STRING_AGG(DISTINCT unnest_tags.tag_val, ', ' ORDER BY unnest_tags.tag_val)
        FROM PostTagAnalysis pta_tags
        JOIN LATERAL UNNEST(pta_tags.TagArray) AS unnest_tags(tag_val) ON TRUE
        WHERE pta_tags.OwnerUserId = U.Id
          AND pta_tags.PostEngagementCategory IN ('HighlyEngagedQuestion', 'ValuableAnswer')
          AND unnest_tags.tag_val IS NOT NULL
          AND LENGTH(TRIM(unnest_tags.tag_val)) > 0
    ) AS TopTagsUserContributedTo, -- Lateral unnest + string aggregation
    LAG(U.Reputation, 1, 0) OVER (ORDER BY U.CreationDate, U.Id) AS PreviousUserReputationByCreationOrder, -- LAG window function
    AVG(U.Reputation) OVER (ORDER BY U.CreationDate ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING) AS MovingAvgReputationByCreationDate, -- Moving average window function
    CASE
        WHEN U.AboutMe IS NULL THEN 'No Bio Provided'
        WHEN LENGTH(U.AboutMe) < 50 THEN 'Short Bio'
        WHEN LENGTH(U.AboutMe) >= 50 AND LENGTH(U.AboutMe) < 200 THEN 'Medium Bio'
        ELSE 'Long Bio'
    END AS AboutMeLengthCategory,
    COALESCE(U.Location, 'Unspecified') AS UserLocation,
    NULLIF(TRIM(U.EmailHash), 'd41d8cd98f00b204e9800998ecf8427e') AS HashedEmailIfProvided, -- Empty string MD5 hash (trim to handle possible whitespace)
    (SELECT COUNT(DISTINCT PostId) FROM Posts WHERE OwnerUserId = U.Id AND AcceptedAnswerId IS NOT NULL) AS QuestionsWithAcceptedAnswers,
    (SELECT COUNT(DISTINCT T_sub.Id)
     FROM Posts P_sub
     JOIN LATERAL UNNEST(STRING_TO_ARRAY(SUBSTRING(P_sub.Tags FROM 2 FOR LENGTH(P_sub.Tags) - 2), '><')) AS unnest_tags(tag_val) ON TRUE
     JOIN Tags T_sub ON unnest_tags.tag_val = T_sub.TagName
     WHERE P_sub.OwnerUserId = U.Id
       AND (T_sub.TagName ILIKE '%sql%' OR T_sub.TagName ILIKE '%database%')
    ) AS UserDatabaseRelatedTagsCount, -- Correlated subquery with LATERAL UNNEST and string matching
    (SELECT SUM(CASE WHEN VT.Name = 'UpMod' THEN 1 ELSE 0 END)
     FROM Votes V
     JOIN VoteTypes VT ON V.VoteTypeId = VT.Id
     WHERE V.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = U.Id)
    ) AS TotalUpvotesReceivedOnOwnPosts
FROM
    Users U
LEFT JOIN
    UserActivitySummary UAS ON U.Id = UAS.UserId
LEFT JOIN
    UserBadgeStats UBS ON U.Id = UBS.UserId
LEFT JOIN
    UserPostHistoryAgg UPHA ON U.Id = UPHA.UserId
LEFT JOIN
    UserReputationRanks RR ON U.Id = RR.UserId
LEFT JOIN
    UserLinkInteraction ULI ON U.Id = ULI.UserId
WHERE
    U.Reputation >= 500
    AND U.Views >= 20
    AND U.LastAccessDate >= (NOW() - INTERVAL '6 months') -- Active in the last 6 months
    AND (U.Location IS NOT NULL OR U.WebsiteUrl IS NOT NULL OR U.AboutMe IS NOT NULL)
    AND (
        (COALESCE(UAS.TotalPosts, 0) >= 20 AND COALESCE(UAS.AvgPostScore, 0) >= 1) OR
        (COALESCE(UBS.GoldBadges, 0) >= 1 OR COALESCE(UBS.SilverBadges, 0) >= 3)
    )
    AND EXISTS (
        SELECT 1
        FROM PostTagAnalysis PTA_sub
        WHERE PTA_sub.OwnerUserId = U.Id
          AND PTA_sub.PostEngagementCategory IN ('HighlyEngagedQuestion', 'ValuableAnswer')
          AND PTA_sub.DaysSinceLastActivity < 180
          AND PTA_sub.Score >= 5
        HAVING COUNT(DISTINCT PTA_sub.PostId) >= 3
    )
    AND (U.DisplayName IS NOT NULL AND U.DisplayName NOT ILIKE '%bot%' AND U.DisplayName NOT ILIKE '%deleted user%' AND LENGTH(U.DisplayName) > 3)
    AND (U.WebsiteUrl IS NULL OR U.WebsiteUrl ILIKE 'https://%.com%' OR U.WebsiteUrl ILIKE 'http://%.org%') -- String pattern matching
    AND U.CreationDate < (NOW() - INTERVAL '1 year') -- User must be at least 1 year old
GROUP BY
    U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.WebsiteUrl,
    UAS.TotalPosts, UAS.QuestionCount, UAS.AnswerCount, UAS.TotalCommentsOnOwnPosts, UAS.TotalPostScore, UAS.AvgPostScore, UAS.AvgQuestionViews,
    UBS.TotalBadges, UBS.GoldBadges, UBS.SilverBadges, UBS.BronzeBadges, UBS.LatestBadgeDate,
    UPHA.TotalPostHistoryEvents, UPHA.PostEditHistoryCount, UPHA.PostClosedHistoryCount, UPHA.PostReopenedHistoryCount, UPHA.PostDeletedUndeletedHistoryCount, UPHA.ClosedReasonNamesSummary,
    RR.ReputationRank, RR.ReputationDecile,
    ULI.LinkedPostsCount, ULI.DuplicateSourcePostsCount,
    U.AboutMe, U.Location, U.EmailHash
HAVING
    COALESCE(UAS.TotalPosts, 0) > 0 -- Ensure user has at least one post for most calculations to be relevant
    AND COALESCE(UPHA.PostEditHistoryCount, 0) >= 1 -- User's posts must have been edited at least once
    AND (
        (COALESCE(UAS.QuestionCount, 0) >= 1 AND COALESCE(UAS.AnswerCount, 0) >= 1) OR -- At least one question and one answer
        (COALESCE(ULI.LinkedPostsCount, 0) + COALESCE(ULI.DuplicateSourcePostsCount, 0) > 0) -- User's posts are linked or duplicated
    )
ORDER BY
    MovingAvgReputationByCreationDate DESC, U.Reputation DESC, UserTotalPostScore DESC
LIMIT 50;
