-- {"query": "1198.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2246} 

WITH UserLifetimeStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Location,
        U.AboutMe,
        DATE_PART('day', U.LastAccessDate - U.CreationDate) AS ActiveDays,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(P.Score) AS TotalPostScore,
        AVG(P.Score) FILTER (WHERE P.PostTypeId IN (1, 2)) AS AvgPostScore,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN P.AcceptedAnswerId END) AS AcceptedAnswersGiven,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(CASE WHEN P.PostTypeId = 1 AND P.ViewCount IS NOT NULL THEN P.ViewCount END) AS MaxQuestionViewCount,
        SUM(LENGTH(P.Body)) AS TotalContentLength
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location, U.AboutMe
),
PostContentMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.CreationDate AS PostCreationDate,
        LENGTH(P.Body) AS BodyLength,
        LENGTH(P.Title) - LENGTH(REPLACE(P.Title, ' ', '')) + 1 AS TitleWordCount,
        ARRAY_LENGTH(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'), 1) AS TagCount,
        P.CommentCount,
        (CAST(P.Score AS DECIMAL) / NULLIF(P.ViewCount, 0)) AS ScoreToViewRatio,
        COALESCE(P.ClosedDate, '1900-01-01'::timestamp) AS ActualClosedDate, -- Sentinel value for easier comparisons
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY (CAST(P.Score AS DECIMAL) / NULLIF(P.ViewCount, 0)) DESC NULLS LAST, P.ViewCount DESC) AS PostEngagementRank
    FROM Posts AS P
    WHERE P.OwnerUserId IS NOT NULL
),
AggregatedTagStats AS (
    SELECT
        Tag.TagName AS TagName,
        COUNT(DISTINCT P.Id) AS TotalTaggedQuestions,
        SUM(P.Score) AS TotalTagScore,
        AVG(P.ViewCount) AS AvgTagViewCount,
        RANK() OVER (ORDER BY SUM(P.ViewCount) DESC, COUNT(DISTINCT P.Id) DESC) AS TagPopularityRank
    FROM Posts AS P
    JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS Tag(TagName) ON TRUE
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND P.Tags != ''
    GROUP BY Tag.TagName
),
UserTagContributions AS (
    SELECT
        P.OwnerUserId,
        Tag.TagName,
        SUM(P.Score) AS UserTagScore,
        COUNT(P.Id) AS UserTagPostCount,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY SUM(P.Score) DESC, COUNT(P.Id) DESC) AS TagRankForUser
    FROM Posts AS P
    JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS Tag(TagName) ON TRUE
    WHERE P.PostTypeId = 1 AND P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId, Tag.TagName
),
ControversialPostActivity AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        CRT.Name AS CloseReason,
        P.ClosedDate,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT CASE WHEN C.CreationDate > P.ClosedDate THEN C.Id END) AS CommentsAfterClosure,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEvents,
        COUNT(DISTINCT CASE WHEN PH.CreationDate > P.ClosedDate AND PH.PostHistoryTypeId IN (4, 5, 6, 8, 9, 11, 13) THEN PH.Id END) AS PostClosureEditsAndReopenings
    FROM Posts AS P
    JOIN PostHistory AS PH_Close ON P.Id = PH_Close.PostId
        AND PH_Close.PostHistoryTypeId = 10 -- Post Closed event
        AND P.ClosedDate IS NOT NULL -- Ensure it was actually closed
    LEFT JOIN CloseReasonTypes AS CRT ON PH_Close.Comment = CAST(CRT.Id AS VARCHAR) -- Link PostHistory.Comment (CloseReasonId) to CloseReasonTypes
    LEFT JOIN Comments AS C ON P.Id = C.PostId
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    WHERE P.PostTypeId = 1 -- Only consider questions
      AND P.ClosedDate IS NOT NULL
      AND CRT.Name IN ('Duplicate', 'Off-topic', 'Needs details or clarity', 'Needs more focus') -- Focus on specific controversial reasons
    GROUP BY P.Id, P.OwnerUserId, CRT.Name, P.ClosedDate
    HAVING COUNT(DISTINCT C.Id) > 5 -- Only posts with at least 5 comments
)
SELECT
    ULS.DisplayName,
    ULS.Reputation,
    ULS.Location,
    ULS.AboutMe,
    ULS.UserCreationDate,
    ULS.LastAccessDate,
    ULS.ActiveDays,
    ULS.TotalQuestions,
    ULS.TotalAnswers,
    ULS.TotalPostScore,
    ULS.AvgPostScore,
    ULS.GoldBadges,
    UTC.TagName AS TopContributingTag,
    ATS.TagPopularityRank AS TopContributingTagPopularityRank,
    CPM.BodyLength AS LongestPostLength,
    CPM.TitleWordCount AS LongestPostTitleWords,
    CPM.TagCount AS LongestPostTagCount,
    CPM.CommentCount AS LongestPostCommentCount,
    CPM.ScoreToViewRatio AS LongestPostScoreToViewRatio,
    CPA.TotalControversialPosts,
    CPA.AvgCommentsOnControversialPosts,
    CPA.AvgPostClosureEdits,
    RANK() OVER (ORDER BY ULS.Reputation DESC, ULS.TotalPostScore DESC, ULS.TotalQuestions DESC, ULS.GoldBadges DESC, CPA.TotalControversialPosts DESC NULLS LAST) AS OverallUserRank,
    NTILE(10) OVER (ORDER BY ULS.Reputation DESC, ULS.TotalPostScore DESC) AS ReputationDecile,
    (ULS.Reputation / NULLIF(ULS.ActiveDays, 0)) AS ReputationPerDay
FROM UserLifetimeStats AS ULS
LEFT JOIN (
    SELECT OwnerUserId, TagName
    FROM UserTagContributions
    WHERE TagRankForUser = 1
) AS UTC ON ULS.UserId = UTC.OwnerUserId
LEFT JOIN AggregatedTagStats AS ATS ON UTC.TagName = ATS.TagName
LEFT JOIN (
    -- Subquery to get the longest post details for each user
    SELECT
        OwnerUserId,
        BodyLength,
        TitleWordCount,
        TagCount,
        CommentCount,
        ScoreToViewRatio,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY BodyLength DESC, Score DESC) AS rn
    FROM PostContentMetrics
    WHERE BodyLength IS NOT NULL
) AS CPM ON ULS.UserId = CPM.OwnerUserId AND CPM.rn = 1
LEFT JOIN (
    SELECT
        OwnerUserId,
        COUNT(DISTINCT PostId) AS TotalControversialPosts,
        AVG(CommentsAfterClosure) AS AvgCommentsOnControversialPosts,
        AVG(PostClosureEditsAndReopenings) AS AvgPostClosureEdits
    FROM ControversialPostActivity
    GROUP BY OwnerUserId
) AS CPA ON ULS.UserId = CPA.OwnerUserId
WHERE
    ULS.Reputation > 5000
    AND ULS.TotalQuestions >= 10
    AND ULS.TotalAnswers >= 15
    AND ULS.ActiveDays > 365 * 3 -- Active for at least 3 years
    AND ULS.DisplayName IS NOT NULL
    AND ULS.DisplayName ~* '^[A-Z]' -- DisplayName starts with a capital letter
    AND (ULS.Location IS NOT NULL OR ULS.AboutMe IS NOT NULL) -- User has provided some profile information
    AND ULS.UserId IN (SELECT DISTINCT P.OwnerUserId FROM Posts AS P JOIN PostLinks AS PL ON P.Id = PL.PostId WHERE PL.LinkTypeId = 1) -- Only users who have linked other posts from their own posts
ORDER BY OverallUserRank ASC, ULS.LastAccessDate DESC
LIMIT 200;
