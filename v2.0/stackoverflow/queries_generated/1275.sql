-- {"query": "1275.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3209} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 1) AS TotalQuestions,
        COUNT(DISTINCT P.Id) FILTER (WHERE P.PostTypeId = 2) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        MAX(GREATEST(P.LastActivityDate, C.CreationDate)) AS LastUserActivityDate,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE NULL END) AS AvgQuestionViewCount,
        EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / (3600 * 24 * 365.25) AS YearsActive,
        COALESCE(SUM(P.FavoriteCount), 0) AS TotalFavoritePosts
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
PostHistoryMetrics AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS EditCount, -- Edit Title, Body, Tags
        COUNT(DISTINCT PH.UserId) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS UniqueEditorsCount,
        MIN(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS FirstEditDate,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS LastEditHistoryDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN 'Closed'
                 WHEN PH.PostHistoryTypeId = 11 THEN 'Reopened'
                 WHEN PH.PostHistoryTypeId = 12 THEN 'Deleted'
                 WHEN PH.PostHistoryTypeId = 13 THEN 'Undeleted'
                 ELSE NULL END) AS LastSignificantPostStatusEvent,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13)) AS LastPostStatusChangeDate,
        STRING_AGG(DISTINCT CR.Name, ', ' ORDER BY CR.Name) FILTER (WHERE PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL AND CR.Id = PH.Comment::smallint) AS CloseReasons,
        SUM(CASE WHEN PH.Text ILIKE '%<a href="/users/%' THEN 1 ELSE 0 END) AS MentionsInHistory,
        COUNT(PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (33, 34)) AS PostNoticeEvents
    FROM PostHistory PH
    LEFT JOIN CloseReasonTypes CR ON PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL AND CR.Id = PH.Comment::smallint
    GROUP BY PH.PostId
),
PostLinkAnalysis AS (
    SELECT
        P.Id AS PostId,
        COUNT(PL.Id) FILTER (WHERE PL.LinkTypeId = 1) AS LinkedPostCount, -- Linked
        COUNT(PL.Id) FILTER (WHERE PL.LinkTypeId = 3) AS DuplicatePostCount, -- Duplicate
        ARRAY_AGG(DISTINCT PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 3) AS DuplicatedToPosts,
        ARRAY_AGG(DISTINCT PLA.RelatedPostId) FILTER (WHERE PLA.LinkTypeId = 3) AS DuplicatedFromPosts
    FROM Posts P
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId
    LEFT JOIN PostLinks PLA ON P.Id = PLA.RelatedPostId AND PLA.LinkTypeId = 3 -- Posts that link TO this post as a duplicate
    GROUP BY P.Id
),
UserBadgeStats AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 2) AS SilverBadges,
        COUNT(B.Id) FILTER (WHERE B.Class = 3) AS BronzeBadges,
        COUNT(B.Id) FILTER (WHERE B.TagBased IS TRUE) AS TagBadges
    FROM Badges B
    GROUP BY B.UserId
),
UserTopTags AS (
    SELECT
        TSM.OwnerUserId AS UserId,
        TSM.TagName,
        SUM(P.Score) AS TagTotalScore,
        COUNT(DISTINCT TSM.PostId) AS TagPostCount,
        ROW_NUMBER() OVER (PARTITION BY TSM.OwnerUserId ORDER BY SUM(P.Score) DESC, COUNT(DISTINCT TSM.PostId) DESC) AS TagRankForUser
    FROM (
        SELECT
            P_inner.Id AS PostId,
            P_inner.OwnerUserId,
            TRIM(UNNEST(string_to_array(substring(P_inner.Tags, 2, length(P_inner.Tags)-2), '><'))) AS TagName
        FROM Posts P_inner
        WHERE P_inner.PostTypeId = 1 AND P_inner.Tags IS NOT NULL AND P_inner.OwnerUserId IS NOT NULL
    ) TSM
    JOIN Posts P ON TSM.PostId = P.Id
    GROUP BY TSM.OwnerUserId, TSM.TagName
),
VoteTypeBreakdown AS (
    SELECT
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCount,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount_OldSystem,
        SUM(CASE WHEN V.VoteTypeId = 8 THEN V.BountyAmount ELSE 0 END) AS TotalBountyGiven,
        SUM(CASE WHEN V.VoteTypeId = 9 THEN V.BountyAmount ELSE 0 END) AS TotalBountyReceived,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId IN (4, 12)) AS OffensiveSpamVotes
    FROM Votes V
    GROUP BY V.PostId
)
SELECT
    UAS.UserId,
    UAS.DisplayName AS UserDisplayName,
    UAS.Reputation,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.TotalComments,
    UAS.TotalPostScore,
    UAS.LastUserActivityDate,
    UAS.YearsActive,
    UB.GoldBadges,
    UB.SilverBadges,
    UB.BronzeBadges,
    UB.TagBadges,
    P.Id AS PostId,
    PT.Name AS PostTypeName,
    P.Title AS PostTitle,
    P.CreationDate AS PostCreationDate,
    P.Score AS PostScore,
    P.ViewCount AS PostViewCount,
    P.AnswerCount,
    P.CommentCount AS PostCommentCount,
    P.FavoriteCount AS PostFavoriteCount_NewSystem,
    P.LastActivityDate AS PostLastActivityDate,
    P.LastEditDate AS PostLastEditDate,
    P.ClosedDate,
    P.CommunityOwnedDate,
    PHM.EditCount AS PostEditCount,
    PHM.UniqueEditorsCount,
    PHM.LastSignificantPostStatusEvent,
    PHM.CloseReasons,
    PHM.MentionsInHistory,
    PHM.PostNoticeEvents,
    PLA.LinkedPostCount,
    PLA.DuplicatePostCount,
    COALESCE(ARRAY_LENGTH(PLA.DuplicatedToPosts, 1), 0) AS DuplicatedToCount,
    COALESCE(ARRAY_LENGTH(PLA.DuplicatedFromPosts, 1), 0) AS DuplicatedFromCount,
    UTT.TagName AS UsersTopTag,
    UTT.TagTotalScore AS UsersTopTagScore,
    UTT.TagPostCount AS UsersTopTagPosts,
    VTB.UpVotesCount,
    VTB.DownVotesCount,
    VTB.TotalBountyGiven,
    VTB.TotalBountyReceived,
    VTB.OffensiveSpamVotes,
    -- Correlated Subquery: Get the text of the latest comment on this post by a different user with a high score
    (
        SELECT C_inner.Text
        FROM Comments C_inner
        WHERE C_inner.PostId = P.Id
          AND C_inner.UserId IS DISTINCT FROM UAS.UserId
          AND C_inner.Score >= 3
        ORDER BY C_inner.CreationDate DESC
        LIMIT 1
    ) AS LatestHighlyScoredOtherCommentText,
    -- Window Function: Rank posts by score within each post type, ordered by last activity
    ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.LastActivityDate DESC) AS PostRankByScoreAndActivity,
    -- Window Function: Calculate average score for posts by this user within their top tag
    AVG(P.Score) OVER (PARTITION BY UAS.UserId, UTT.TagName) AS AvgPostScoreInUserTopTag,
    -- Window Function: Calculate the difference in days between the post creation and its first edit (if any)
    COALESCE(EXTRACT(DAY FROM (PHM.FirstEditDate - P.CreationDate)), -1) AS DaysToFirstEdit,
    -- Complicated Expression/Calculation with NULL handling, string length, and conditional logic
    COALESCE(
        (P.Score * 10.0 + P.ViewCount * 0.5 + P.CommentCount * 2.0 + COALESCE(P.AnswerCount, 0) * 3.0 - VTB.DownVotesCount * 5.0) /
        NULLIF(PHM.EditCount + ABS(VTB.OffensiveSpamVotes * 2) + 1 + LENGTH(COALESCE(P.Body, '')) / 1000, 0),
        0.0
    ) AS CalculatedPostImpactMetric,
    -- String Expression: Analyze post title and body for complexity/sentiment and apply NULL logic
    CASE
        WHEN P.Title ILIKE '%help%' OR P.Title ILIKE '%stuck%' OR P.Title ILIKE '%issue%' THEN 'Problematic Title'
        WHEN P.ClosedDate IS NOT NULL AND PHM.CloseReasons ILIKE '%duplicate%' THEN 'Closed Duplicate'
        WHEN P.AnswerCount = 0 AND P.PostTypeId = 1 AND P.CreationDate < NOW() - INTERVAL '6 months' THEN 'Old Unanswered Question'
        WHEN P.Body ILIKE '%I don''t understand%' OR P.Body ILIKE '%newbie%' THEN 'Beginner Content'
        ELSE 'General Content'
    END AS PostContentClassification,
    -- Complex Predicate with Date arithmetic, boolean logic, and multiple table conditions
    (P.Score < 0 AND P.ClosedDate IS NOT NULL AND PHM.EditCount > 3 AND UAS.Reputation < 2000 AND VTB.DownVotesCount > VTB.UpVotesCount * 2)
    OR
    (P.PostTypeId = 1 AND P.AnswerCount = 0 AND P.LastActivityDate < NOW() - INTERVAL '1 year' AND PHM.LastSignificantPostStatusEvent IS NULL)
    AS IsHighlyProblematicOrStalePost
FROM UserActivitySummary UAS
LEFT JOIN UserBadgeStats UB ON UAS.UserId = UB.UserId
JOIN Posts P ON UAS.UserId = P.OwnerUserId
LEFT JOIN PostTypes PT ON P.PostTypeId = PT.Id
LEFT JOIN PostHistoryMetrics PHM ON P.Id = PHM.PostId
LEFT JOIN PostLinkAnalysis PLA ON P.Id = PLA.PostId
LEFT JOIN UserTopTags UTT ON UAS.UserId = UTT.UserId AND UTT.TagRankForUser = 1 -- Get only the user's highest-scoring top tag
LEFT JOIN VoteTypeBreakdown VTB ON P.Id = VTB.PostId
WHERE
    UAS.Reputation > 100 -- Filter out very low reputation users
    AND UAS.TotalQuestions + UAS.TotalAnswers > 0 -- Only users with at least one post
    AND P.CreationDate BETWEEN NOW() - INTERVAL '10 years' AND NOW() - INTERVAL '1 day' -- Posts from the past 10 years, excluding today
    AND P.PostTypeId IN (1, 2) -- Only Questions (1) and Answers (2)
    AND P.Score >= -10 -- Include some negatively scored posts for analysis
    AND (
        (P.PostTypeId = 1 AND P.ViewCount > 500 AND P.AnswerCount > 0 AND P.AcceptedAnswerId IS NOT NULL) OR -- Popular questions with accepted answers
        (P.PostTypeId = 2 AND P.ParentId IS NOT NULL AND P.Score > 5 AND P.OwnerUserId IS NOT NULL) -- High-scoring answers from active users
    )
    AND NOT EXISTS ( -- Correlated NOT EXISTS subquery: ensure post is not part of a recent migration away
        SELECT 1
        FROM PostHistory PH_mig
        WHERE PH_mig.PostId = P.Id
        AND PH_mig.PostHistoryTypeId = 35 -- Post Migrated Away
        AND PH_mig.CreationDate > NOW() - INTERVAL '6 months'
    )
    AND P.Title IS NOT NULL
ORDER BY
    CalculatedPostImpactMetric DESC,
    UAS.Reputation DESC,
    PostLastActivityDate DESC,
    P.Id
LIMIT 1000;
