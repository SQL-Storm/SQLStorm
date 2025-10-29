-- {"query": "1848.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3279} 

WITH UserEngagement AS (
    -- CTE 1: Aggregates user activity, reputation, and badge counts, filtering for active and influential users.
    -- Includes total post scores and view counts to gauge overall contribution.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.LastAccessDate,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadgeCount,
        COUNT(DISTINCT CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadgeCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsPosted,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersPosted,
        SUM(COALESCE(P.Score, 0)) AS LifetimePostScore,
        SUM(COALESCE(P.ViewCount, 0)) AS LifetimeQuestionViews
    FROM
        Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE
        U.Reputation > 7500 -- High reputation users
        AND U.LastAccessDate >= (NOW() - INTERVAL '6 months') -- Recently active
        AND U.DisplayName IS NOT NULL
        AND U.Location IS NOT NULL
        AND U.Location NOT IN ('', '(null)', 'unknown') -- Exclude generic/empty locations
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.LastAccessDate, U.CreationDate
    HAVING
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) >= 1 -- At least one gold badge
        OR SUM(COALESCE(P.Score, 0)) > 2500 -- Or very high lifetime post score
),
PostHistoryAggregates AS (
    -- CTE 2: Analyzes post history for questions to count edits, closures, and calculate time between events.
    -- Uses window functions for event timing and then aggregates per post.
    WITH HistoryDetails AS (
        SELECT
            PH.PostId,
            PH.PostHistoryTypeId,
            PH.CreationDate AS HistoryDate,
            LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PrevHistoryDate,
            EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate))) / 3600.0 AS TimeSinceLastHistoryHours
        FROM
            PostHistory PH
        WHERE
            PH.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13) -- Edit Title/Body/Tags, Post Closed/Reopened/Deleted/Undeleted
            AND PH.CreationDate >= (NOW() - INTERVAL '3 year') -- Consider history from the last 3 years
    )
    SELECT
        HD.PostId,
        MAX(CASE WHEN HD.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasEverClosedFlag,
        COUNT(DISTINCT CASE WHEN HD.PostHistoryTypeId IN (4, 5, 6) THEN HD.HistoryDate END) AS TotalUniqueEditEvents,
        AVG(HD.TimeSinceLastHistoryHours) FILTER (WHERE HD.TimeSinceLastHistoryHours > 0) AS AvgHoursBetweenHistoryEvents, -- Conditional aggregation
        MAX(HD.TimeSinceLastHistoryHours) FILTER (WHERE HD.TimeSinceLastHistoryHours > 0) AS MaxHoursBetweenHistoryEvents
    FROM
        HistoryDetails HD
    GROUP BY
        HD.PostId
),
QuestionDetailsExtended AS (
    -- CTE 3: Gathers comprehensive details for questions, including accepted/highest answer scores and parsed tags.
    -- Joins with Tags for primary tag information and calculates the number of tags.
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.Title AS QuestionTitle,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.CreationDate AS QuestionCreationDate,
        Q.LastActivityDate,
        Q.ClosedDate,
        Q.Tags,
        COALESCE(A.Id, -1) AS AcceptedAnswerPostId,
        COALESCE(A.Score, 0) AS AcceptedAnswerScore,
        COALESCE(MAX_A.MaxAnswerScore, 0) AS HighestAnswerScore,
        COALESCE(T.TagName, 'Untagged') AS PrimaryTagName, -- Default for questions without a directly linked tag
        ARRAY_LENGTH(string_to_array(SUBSTRING(Q.Tags FROM 2 FOR LENGTH(Q.Tags) - 2), '><'), 1) AS NumberOfTags,
        Q.FavoriteCount,
        Q.CommentCount
    FROM
        Posts Q
    LEFT JOIN Posts A ON Q.AcceptedAnswerId = A.Id -- Details for the accepted answer
    LEFT JOIN (
        SELECT P_ANS.ParentId, MAX(P_ANS.Score) AS MaxAnswerScore
        FROM Posts P_ANS
        WHERE P_ANS.PostTypeId = 2
        GROUP BY P_ANS.ParentId
    ) MAX_A ON Q.Id = MAX_A.ParentId
    LEFT JOIN Tags T ON Q.Tags LIKE '%<' || T.TagName || '>%' AND T.Id = (
        -- Correlated subquery to find the ID of the first tag in the list for a primary tag name
        SELECT MIN(T2.Id)
        FROM Tags T2
        WHERE Q.Tags LIKE '%<' || T2.TagName || '>%'
        LIMIT 1
    )
    WHERE
        Q.PostTypeId = 1
        AND Q.Score >= 20
        AND Q.ViewCount > 500
        AND Q.OwnerUserId IS NOT NULL
        AND Q.Title IS NOT NULL
),
HighlyEngagedComments AS (
    -- CTE 4: Identifies questions with a high volume of positive/negative comments, aggregating scores and summarizing top comments.
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalCommentsOnQuestion,
        SUM(C.Score) AS SumCommentScores,
        STRING_AGG(CASE WHEN C.Score > 5 THEN LEFT(C.Text, 75) ELSE NULL END, ' || ') FILTER (WHERE C.Score > 5) AS TopPositiveCommentSnippets, -- Filter for highly upvoted comments
        STRING_AGG(CASE WHEN C.Score < -2 THEN LEFT(C.Text, 75) ELSE NULL END, ' || ') FILTER (WHERE C.Score < -2) AS TopNegativeCommentSnippets
    FROM
        Comments C
    WHERE
        C.CreationDate >= (NOW() - INTERVAL '1 year')
    GROUP BY
        C.PostId
    HAVING
        COUNT(C.Id) >= 5
        AND (SUM(C.Score) > 10 OR SUM(C.Score) < -5)
),
PostLinkAnalysis AS (
    -- CTE 5: Determines if a question has been linked as a duplicate and counts associated duplicates.
    SELECT
        PL.PostId,
        COUNT(PL.RelatedPostId) AS NumberOfDuplicateLinks,
        STRING_AGG(PL.RelatedPostId::TEXT, ', ') AS DuplicateRelatedPostIds
    FROM
        PostLinks PL
    WHERE
        PL.LinkTypeId = 3 -- Duplicate link type
    GROUP BY
        PL.PostId
)
-- Main Query: Integrates data from all CTEs to provide a comprehensive view of influential users and their popular/problematic questions.
-- Uses various joins, subqueries, window functions (implicitly via CTEs), conditional logic, and string operations.
SELECT
    UE.DisplayName AS UserDisplayName,
    UE.Reputation,
    UE.GoldBadgeCount,
    UE.SilverBadgeCount,
    QDE.QuestionTitle,
    QDE.QuestionScore,
    QDE.ViewCount AS QuestionViewCount,
    QDE.HighestAnswerScore,
    QDE.AcceptedAnswerScore,
    QDE.PrimaryTagName,
    QDE.NumberOfTags,
    QDE.ClosedDate IS NOT NULL AS IsQuestionClosed,
    COALESCE(PHA.WasEverClosedFlag, 0) AS WasEverClosedByHistory,
    COALESCE(PHA.TotalUniqueEditEvents, 0) AS TotalEditHistoryEvents,
    PHA.AvgHoursBetweenHistoryEvents,
    PHA.MaxHoursBetweenHistoryEvents,
    COALESCE(HEC.TotalCommentsOnQuestion, 0) AS QuestionCommentCount,
    COALESCE(HEC.SumCommentScores, 0) AS QuestionCommentsTotalScore,
    HEC.TopPositiveCommentSnippets,
    HEC.TopNegativeCommentSnippets,
    COALESCE(PLA.NumberOfDuplicateLinks, 0) AS HasDuplicateLinks,
    PLA.DuplicateRelatedPostIds,
    (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = QDE.QuestionId AND V.VoteTypeId = 2 AND V.UserId = UE.UserId AND V.CreationDate >= (NOW() - INTERVAL '1 year')) AS UserUpvotesOnOwnQuestionRecent, -- Correlated subquery for recent votes
    (SELECT SUM(V.BountyAmount) FROM Votes V WHERE V.PostId = QDE.QuestionId AND V.VoteTypeId = 8 AND V.BountyAmount > 0) AS TotalBountyOnQuestion, -- Subquery for bounty
    CASE
        WHEN QDE.ClosedDate IS NOT NULL AND COALESCE(QDE.HighestAnswerScore, 0) < 10 THEN 'Closed_UnsatisfactoryAnswers'
        WHEN QDE.ClosedDate IS NOT NULL THEN 'Closed_WithAnswers'
        WHEN QDE.QuestionScore >= 500 AND COALESCE(QDE.HighestAnswerScore, 0) >= 100 AND QDE.FavoriteCount > 20 THEN 'Highly_Successful_Engaged'
        WHEN QDE.QuestionScore >= 200 AND QDE.NumberOfTags >= 5 AND QDE.ViewCount > 5000 THEN 'Popular_BroadTopic_HighTraffic'
        ELSE 'Other'
    END AS QuestionSuccessCategory,
    -- Complex expression involving date differences and string length for lifecycle analysis
    CASE
        WHEN QDE.QuestionCreationDate IS NOT NULL AND QDE.LastActivityDate IS NOT NULL
             AND (QDE.LastActivityDate - QDE.QuestionCreationDate) > INTERVAL '1 year'
             AND LENGTH(QDE.QuestionTitle) > 75
             AND QDE.CommentCount > 10 THEN 'LongLived_Verbose_Discussed'
        WHEN QDE.QuestionCreationDate IS NOT NULL AND QDE.LastActivityDate IS NOT NULL
             AND (QDE.LastActivityDate - QDE.QuestionCreationDate) < INTERVAL '30 days'
             AND COALESCE(QDE.QuestionScore, 0) < 5
             AND COALESCE(QDE.ViewCount, 0) < 100 THEN 'Recent_LowImpact'
        ELSE NULL
    END AS QuestionLifecyclePattern,
    -- Nested subquery to get the display name of the owner of the accepted answer, handling NULLs
    COALESCE(
        (SELECT U_AA.DisplayName FROM Users U_AA WHERE U_AA.Id = (
            SELECT P_AA.OwnerUserId FROM Posts P_AA WHERE P_AA.Id = QDE.AcceptedAnswerPostId AND P_AA.OwnerUserId IS NOT NULL
        ) LIMIT 1),
        'N/A'
    ) AS AcceptedAnswerOwnerDisplayName
FROM
    UserEngagement UE
INNER JOIN
    QuestionDetailsExtended QDE ON UE.UserId = QDE.QuestionOwnerId
LEFT JOIN
    PostHistoryAggregates PHA ON QDE.QuestionId = PHA.PostId
LEFT JOIN
    HighlyEngagedComments HEC ON QDE.QuestionId = HEC.PostId
LEFT JOIN
    PostLinkAnalysis PLA ON QDE.QuestionId = PLA.PostId
WHERE
    QDE.HighestAnswerScore > 0 -- Ensure the question has at least one scored answer
    AND (QDE.QuestionTitle LIKE '%performance%' OR QDE.Tags LIKE '%<sql>%' OR QDE.PrimaryTagName IN ('optimization', 'database-performance')) -- Targeted topic filtering
    AND (UE.TotalQuestionsPosted + UE.TotalAnswersPosted) > 10 -- User is a seasoned contributor
    AND NOT EXISTS ( -- Exclude questions that were rapidly closed after creation and had negative comments
        SELECT 1
        FROM PostHistory PH_CLOSE
        LEFT JOIN Comments C_NEG ON PH_CLOSE.PostId = C_NEG.PostId
        WHERE PH_CLOSE.PostId = QDE.QuestionId
          AND PH_CLOSE.PostHistoryTypeId = 10 -- Post Closed
          AND (PH_CLOSE.CreationDate - QDE.QuestionCreationDate) < INTERVAL '7 days' -- Closed within a week
          AND C_NEG.Score < 0 AND LOWER(C_NEG.Text) LIKE '%confusing%' -- Also has negative/confusing comments
    )
GROUP BY
    UE.DisplayName, UE.Reputation, UE.GoldBadgeCount, UE.SilverBadgeCount,
    QDE.QuestionTitle, QDE.QuestionScore, QDE.ViewCount, QDE.HighestAnswerScore, QDE.AcceptedAnswerScore,
    QDE.PrimaryTagName, QDE.NumberOfTags, QDE.ClosedDate, QDE.QuestionId, UE.UserId,
    PHA.WasEverClosedFlag, PHA.TotalUniqueEditEvents, PHA.AvgHoursBetweenHistoryEvents, PHA.MaxHoursBetweenHistoryEvents,
    HEC.TotalCommentsOnQuestion, HEC.SumCommentScores, HEC.TopPositiveCommentSnippets, HEC.TopNegativeCommentSnippets,
    PLA.NumberOfDuplicateLinks, PLA.DuplicateRelatedPostIds, QDE.AcceptedAnswerPostId, QDE.FavoriteCount,
    QDE.CommentCount, QDE.QuestionCreationDate, QDE.LastActivityDate
ORDER BY
    UE.Reputation DESC, QDE.QuestionScore DESC, QDE.LastActivityDate DESC
LIMIT 500;
