-- {"query": "1852.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3910} 

WITH UserSummary AS (
    -- Aggregates basic user information and counts from posts and comments.
    -- Includes NULL logic for WebsiteUrl and string expressions for AboutMe length.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpVotesGiven,
        U.DownVotes AS UserTotalDownVotesGiven,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestionsPosted,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswersPosted,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreReceived,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalCommentsMade,
        COALESCE(U.WebsiteUrl, 'N/A') AS UserWebsiteUrl,
        LENGTH(U.AboutMe) AS AboutMeLength
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes, U.WebsiteUrl, U.AboutMe
),
PostDetailedMetrics AS (
    -- Calculates detailed metrics for questions and answers, including a custom "Impact Score".
    -- Features string processing for tags and complicated predicates for "IsHighlyEngaged".
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.Title,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.ClosedDate,
        P.AcceptedAnswerId,
        P.Tags,
        -- Complex calculation: "Impact Score" weighing different post attributes
        CAST(P.Score * 0.6 + COALESCE(P.FavoriteCount, 0) * 0.2 + P.CommentCount * 0.1 + COALESCE(P.AnswerCount, 0) * 0.1 AS NUMERIC) AS PostImpactScore,
        -- String expression: Convert tags string into an array, handling NULLs and empty strings.
        CASE
            WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 THEN
                ARRAY(SELECT TRIM(s) FROM UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><')) AS s)
            ELSE '{}'::varchar[]
        END AS TagArray,
        -- Complicated predicate: Identifies highly engaged posts based on multiple criteria.
        P.Score > 50 AND P.ViewCount > 10000 AND P.AnswerCount > 5 AND P.FavoriteCount IS NOT NULL AS IsHighlyEngaged,
        -- Date calculation: Days since last activity for the post.
        EXTRACT(DAY FROM (NOW() - P.LastActivityDate)) AS DaysSinceLastActivity
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
),
UserBadgeStats AS (
    -- Aggregates badge counts for each user and ranks users by their total badges.
    -- Includes window function for ranking.
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(CASE WHEN B.Class = 1 THEN B.Date END) AS LatestGoldBadgeAwardDate,
        RANK() OVER (ORDER BY COUNT(B.Id) DESC, B.UserId ASC) AS OverallBadgeRank
    FROM Badges B
    GROUP BY B.UserId
),
PostHistoricalChanges AS (
    -- Analyzes post history events, calculating time differences between events and counting specific event types.
    -- Features LAG window function and string processing on comments.
    SELECT
        PH.PostId,
        PH.UserId AS EditorUserId,
        PH.PostHistoryTypeId,
        PHT.Name AS HistoryTypeName,
        PH.CreationDate AS HistoryEventDate,
        -- Window function with date arithmetic: Hours since previous history event for the same post.
        EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate))) / 3600.0 AS HoursSincePrevHistory,
        -- Window functions: Count total edits and close events for each post.
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) OVER (PARTITION BY PH.PostId) AS TotalEditEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) OVER (PARTITION BY PH.PostId) AS TotalCloseEvents,
        -- String expression and NULL logic: Replaces spaces in comment with underscores, handles NULL comments.
        REPLACE(COALESCE(PH.Comment, 'No_comment_provided'), ' ', '_') AS FormattedComment
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PH.PostHistoryTypeId IN (1, 2, 4, 5, 6, 10, 11, 12, 13, 35, 36) -- Focus on initial, edits, close/reopen/delete/undelete, migration
),
GlobalPostAverages AS (
    -- Calculates global averages for post metrics for comparison.
    SELECT
        AVG(Score) AS AvgScore,
        AVG(ViewCount) AS AvgViewCount,
        AVG(PostImpactScore) AS AvgPostImpactScore,
        COUNT(DISTINCT PostId) AS TotalIndexedPosts
    FROM PostDetailedMetrics
),
UserTopPosts AS (
    -- Identifies the top question and top answer for each user based on PostImpactScore.
    -- Uses ROW_NUMBER window function to pick the best post of each type.
    SELECT
        PDM.PostId,
        PDM.OwnerUserId,
        PDM.PostTypeName,
        PDM.Title,
        PDM.PostImpactScore,
        PDM.Score,
        PDM.ViewCount,
        PDM.AnswerCount,
        PDM.CommentCount,
        PDM.FavoriteCount,
        PDM.PostCreationDate,
        PDM.LastEditDate,
        PDM.DaysSinceLastActivity,
        PDM.TagArray,
        PDM.IsHighlyEngaged,
        PDM.ClosedDate,
        ROW_NUMBER() OVER (PARTITION BY PDM.OwnerUserId, PDM.PostTypeId ORDER BY PDM.PostImpactScore DESC, PDM.PostCreationDate DESC) AS rn_post_type_impact
    FROM PostDetailedMetrics PDM
)
-- Main query: Combines user and post data, analyzes top posts, and provides comparative metrics.
-- Uses UNION ALL to combine results for top questions and top answers.
SELECT
    US.UserId,
    US.DisplayName,
    US.Reputation,
    US.TotalQuestionsPosted,
    US.TotalAnswersPosted,
    US.TotalPostScoreReceived,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
    TP.PostId AS TopPostId,
    TP.PostTypeName AS TopPostType,
    TP.Title AS TopPostTitle,
    TP.PostImpactScore AS TopPostCalculatedImpact,
    TP.Score AS TopPostScore,
    TP.ViewCount AS TopPostViewCount,
    TP.AnswerCount AS TopPostAnswerCount,
    TP.CommentCount AS TopPostCommentCount,
    TP.FavoriteCount AS TopPostFavoriteCount,
    TP.PostCreationDate AS TopPostDate,
    TP.DaysSinceLastActivity AS TopPostDaysSinceActivity,
    TP.TagArray AS TopPostTags,
    GPA.AvgPostImpactScore AS GlobalAverageImpact,
    GPA.AvgScore AS GlobalAverageScore,
    -- Correlated subquery: Checks if the top post has any recent (last year) major edits by a user other than the owner.
    EXISTS (
        SELECT 1
        FROM PostHistory PH_corr
        WHERE PH_corr.PostId = TP.PostId
          AND PH_corr.UserId IS NOT NULL
          AND PH_corr.UserId != US.UserId
          AND PH_corr.PostHistoryTypeId IN (5) -- PostHistoryTypeId 5 = Edit Body
          AND PH_corr.CreationDate > (NOW() - INTERVAL '1 year')
    ) AS HasRecentOtherEditor,
    -- Case expression: Categorizes users based on reputation, badges, and post counts.
    CASE
        WHEN US.Reputation > 50000 AND COALESCE(UBS.GoldBadges, 0) >= 5 THEN 'Legendary Contributor'
        WHEN US.Reputation > 10000 AND (COALESCE(UBS.GoldBadges, 0) >= 1 OR COALESCE(UBS.SilverBadges, 0) >= 5) THEN 'Distinguished Member'
        WHEN US.TotalQuestionsPosted > 50 AND US.TotalAnswersPosted > 100 THEN 'Prodigious All-Rounder'
        ELSE 'Active Participant'
    END AS UserCategory,
    -- Window function: Ranks users globally based on their top post's impact and reputation.
    RANK() OVER (ORDER BY TP.PostImpactScore DESC, US.Reputation DESC) AS OverallImpactRank,
    -- String expression and NULL logic: Concatenates the top 3 tags from the array, provides a default if no tags.
    COALESCE(
        ARRAY_TO_STRING(TP.TagArray[1:3], ', '),
        'No_Tags'
    ) AS Top3TagsConcatenated,
    -- Complex calculation: User's total score received per day since creation.
    CAST(US.TotalPostScoreReceived AS NUMERIC) / (EXTRACT(DAY FROM (NOW() - US.UserCreationDate)) + 1) AS ScorePerDaySinceCreation,
    -- NULL logic: Provides an effective closed date for top posts (a future date if not closed).
    COALESCE(TP.ClosedDate, '9999-12-31'::timestamp) AS TopPostClosedDateEffective,
    COALESCE(PHC.TotalEditEvents, 0) AS TopPostTotalEditEvents,
    COALESCE(PHC.TotalCloseEvents, 0) AS TopPostTotalCloseEvents,
    PHC.AvgHoursBetweenHistory AS TopPostAvgHoursBetweenHistoryEvents
FROM UserSummary US
LEFT JOIN UserBadgeStats UBS ON US.UserId = UBS.UserId
JOIN UserTopPosts TP ON US.UserId = TP.OwnerUserId
LEFT JOIN GlobalPostAverages GPA ON TRUE -- Joins for global averages (1=1 or TRUE is typical for single-row CTEs)
LEFT JOIN ( -- Aggregate PostHistoricalChanges to one row per PostId for joining
    SELECT
        PostId,
        MAX(TotalEditEvents) AS TotalEditEvents,
        MAX(TotalCloseEvents) AS TotalCloseEvents,
        AVG(HoursSincePrevHistory) FILTER (WHERE HoursSincePrevHistory IS NOT NULL) AS AvgHoursBetweenHistory
    FROM PostHistoricalChanges
    GROUP BY PostId
) PHC ON TP.PostId = PHC.PostId
WHERE TP.rn_post_type_impact = 1 AND TP.PostTypeId = 1 -- Selects the top QUESTION for each user
AND US.Reputation > 1000 -- Filter for reasonably active users
AND US.LastAccessDate > (NOW() - INTERVAL '2 years') -- Users active in the last 2 years
AND US.AboutMeLength IS NOT NULL AND US.AboutMeLength > 50 -- Users with meaningful "About Me"
-- Correlated subquery with NOT EXISTS: Excludes posts that are duplicates of others.
AND NOT EXISTS (
    SELECT 1
    FROM PostLinks PL
    WHERE PL.PostId = TP.PostId AND PL.LinkTypeId = 3
)

UNION ALL

-- Second branch of UNION ALL: Same logic but for the top ANSWER of each user.
SELECT
    US.UserId,
    US.DisplayName,
    US.Reputation,
    US.TotalQuestionsPosted,
    US.TotalAnswersPosted,
    US.TotalPostScoreReceived,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
    TP.PostId AS TopPostId,
    TP.PostTypeName AS TopPostType,
    TP.Title AS TopPostTitle,
    TP.PostImpactScore AS TopPostCalculatedImpact,
    TP.Score AS TopPostScore,
    TP.ViewCount AS TopPostViewCount,
    TP.AnswerCount AS TopPostAnswerCount,
    TP.CommentCount AS TopPostCommentCount,
    TP.FavoriteCount AS TopPostFavoriteCount,
    TP.PostCreationDate AS TopPostDate,
    TP.DaysSinceLastActivity AS TopPostDaysSinceActivity,
    TP.TagArray AS TopPostTags,
    GPA.AvgPostImpactScore AS GlobalAverageImpact,
    GPA.AvgScore AS GlobalAverageScore,
    EXISTS (
        SELECT 1
        FROM PostHistory PH_corr
        WHERE PH_corr.PostId = TP.PostId
          AND PH_corr.UserId IS NOT NULL
          AND PH_corr.UserId != US.UserId
          AND PH_corr.PostHistoryTypeId IN (5)
          AND PH_corr.CreationDate > (NOW() - INTERVAL '1 year')
    ) AS HasRecentOtherEditor,
    CASE
        WHEN US.Reputation > 50000 AND COALESCE(UBS.GoldBadges, 0) >= 5 THEN 'Legendary Contributor'
        WHEN US.Reputation > 10000 AND (COALESCE(UBS.GoldBadges, 0) >= 1 OR COALESCE(UBS.SilverBadges, 0) >= 5) THEN 'Distinguished Member'
        WHEN US.TotalQuestionsPosted > 50 AND US.TotalAnswersPosted > 100 THEN 'Prodigious All-Rounder'
        ELSE 'Active Participant'
    END AS UserCategory,
    RANK() OVER (ORDER BY TP.PostImpactScore DESC, US.Reputation DESC) AS OverallImpactRank,
    COALESCE(
        ARRAY_TO_STRING(TP.TagArray[1:3], ', '),
        'No_Tags'
    ) AS Top3TagsConcatenated,
    CAST(US.TotalPostScoreReceived AS NUMERIC) / (EXTRACT(DAY FROM (NOW() - US.UserCreationDate)) + 1) AS ScorePerDaySinceCreation,
    COALESCE(TP.ClosedDate, '9999-12-31'::timestamp) AS TopPostClosedDateEffective,
    COALESCE(PHC.TotalEditEvents, 0) AS TopPostTotalEditEvents,
    COALESCE(PHC.TotalCloseEvents, 0) AS TopPostTotalCloseEvents,
    PHC.AvgHoursBetweenHistory AS TopPostAvgHoursBetweenHistoryEvents
FROM UserSummary US
LEFT JOIN UserBadgeStats UBS ON US.UserId = UBS.UserId
JOIN UserTopPosts TP ON US.UserId = TP.OwnerUserId
LEFT JOIN GlobalPostAverages GPA ON TRUE
LEFT JOIN (
    SELECT
        PostId,
        MAX(TotalEditEvents) AS TotalEditEvents,
        MAX(TotalCloseEvents) AS TotalCloseEvents,
        AVG(HoursSincePrevHistory) FILTER (WHERE HoursSincePrevHistory IS NOT NULL) AS AvgHoursBetweenHistory
    FROM PostHistoricalChanges
    GROUP BY PostId
) PHC ON TP.PostId = PHC.PostId
WHERE TP.rn_post_type_impact = 1 AND TP.PostTypeId = 2 -- Selects the top ANSWER for each user
AND US.Reputation > 1000
AND US.LastAccessDate > (NOW() - INTERVAL '2 years')
AND US.AboutMeLength IS NOT NULL AND US.AboutMeLength > 50;
