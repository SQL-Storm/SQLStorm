-- {"query": "1687.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3489} 
WITH UserActivity AS (
    -- Gathers comprehensive activity and reputation metrics for each user, including post and comment counts, and received votes.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(U.Location, 'Unknown Location') AS UserLocation,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN PV.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceivedOnPosts,
        SUM(CASE WHEN PV.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceivedOnPosts,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END) AS AvgAnswerScore,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id ELSE NULL END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id ELSE NULL END) AS TotalAnswersPosted
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes PV ON P.Id = PV.PostId AND PV.VoteTypeId IN (2, 3) -- Only consider up/down votes on posts
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location, U.Views, U.UpVotes, U.DownVotes
),
PostDetailAndVotes AS (
    -- Aggregates various vote counts for each post and enriches with core post details.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS InitialPostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        P.AcceptedAnswerId,
        P.ClosedDate,
        P.LastActivityDate,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCountActual, -- Note: VoteType 5 (Favorite) was deprecated/changed. This captures historical data.
        MAX(CASE WHEN V.VoteTypeId = 1 THEN 1 ELSE 0 END) AS IsAcceptedAnswerVote
    FROM
        Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.Title, P.Tags, P.AcceptedAnswerId, P.ClosedDate, P.LastActivityDate
),
QuestionPerformance AS (
    -- Calculates advanced performance metrics specifically for questions, including accepted answer details, edit history, and tag relevance.
    SELECT
        PDV.PostId,
        PDV.OwnerUserId,
        PDV.PostCreationDate,
        PDV.Title,
        PDV.Tags,
        PDV.InitialPostScore,
        PDV.ViewCount,
        PDV.AnswerCount,
        PDV.CommentCount,
        PDV.FavoriteCount,
        PDV.UpVoteCount,
        PDV.DownVoteCount,
        PDV.FavoriteCountActual,
        PDV.AcceptedAnswerId,
        PDV.ClosedDate,
        PDV.LastActivityDate,
        (PDV.UpVoteCount - PDV.DownVoteCount) AS NetVotes,
        CASE
            WHEN PDV.PostTypeId = 1 AND PDV.AcceptedAnswerId IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS HasAcceptedAnswer,
        COALESCE(QA.Score, 0) AS AcceptedAnswerScore,
        COALESCE(QA.CreationDate, '1900-01-01 00:00:00') AS AcceptedAnswerCreationDate,
        COALESCE(QA.OwnerUserId, -1) AS AcceptedAnswerOwnerUserId,
        -- Correlated subquery to count edits (Title, Body, Tags)
        (SELECT COUNT(DISTINCT PH.Id) FROM PostHistory PH WHERE PH.PostId = PDV.PostId AND PH.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        -- Correlated subquery to find the name of the last close reason if the post was closed
        (SELECT MAX(CRT.Name)
         FROM PostHistory PH
         LEFT JOIN CloseReasonTypes CRT ON CAST(PH.Comment AS SMALLINT) = CRT.Id
         WHERE PH.PostId = PDV.PostId AND PH.PostHistoryTypeId = 10
        ) AS LastCloseReasonName,
        -- Complex string matching for specific "performance-related" tags
        CASE
            WHEN PDV.Tags LIKE '%<sql>%' OR PDV.Tags LIKE '%<database>%' OR PDV.Tags LIKE '%<performance>%' OR PDV.Tags LIKE '%<optimization>%' THEN TRUE
            ELSE FALSE
        END AS IsPerformanceRelatedTag,
        EXTRACT(HOUR FROM PDV.PostCreationDate) AS CreationHourOfDay
    FROM
        PostDetailAndVotes PDV
    LEFT JOIN Posts QA ON PDV.AcceptedAnswerId = QA.Id AND QA.PostTypeId = 2 -- Join to get details of the accepted answer
    WHERE
        PDV.PostTypeId = 1 -- Only focus on questions
),
PostHistoryAgg AS (
    -- Aggregates various post history event counts and details for each post.
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (1, 2, 3) THEN 1 ELSE 0 END) AS InitialEntriesCount,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 24) THEN 1 ELSE 0 END) AS MinorEditEvents, -- Includes suggested edit applied
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 12, 14) THEN 1 ELSE 0 END) AS ClosureDeletionOrLockEvents, -- Includes locked status
        MAX(PH.CreationDate) AS LatestHistoryDate,
        COUNT(DISTINCT PH.UserId) AS UniqueEditors
    FROM
        PostHistory PH
    GROUP BY
        PH.PostId
),
UserBadges AS (
    -- Counts the different classes of badges (Gold, Silver, Bronze) for each user.
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(B.Id) AS TotalBadges,
        COUNT(DISTINCT B.Name) AS UniqueBadgeNames
    FROM
        Badges B
    GROUP BY
        B.UserId
)
-- Main query to combine all processed data, apply window functions, and derive a composite engagement score.
SELECT
    QP.PostId,
    QP.Title,
    QP.PostCreationDate,
    UA.DisplayName AS QuestionOwnerDisplayName,
    UA.Reputation AS QuestionOwnerReputation,
    UA.TotalPostsCreated AS OwnerTotalPosts,
    UA.TotalQuestionsAsked AS OwnerTotalQuestions,
    COALESCE(UB.GoldBadges, 0) AS OwnerGoldBadges, -- NULL logic for users with no badges
    COALESCE(UB.SilverBadges, 0) AS OwnerSilverBadges,
    COALESCE(UB.BronzeBadges, 0) AS OwnerBronzeBadges,
    QP.InitialPostScore,
    QP.NetVotes,
    QP.ViewCount,
    QP.AnswerCount,
    QP.CommentCount,
    QP.FavoriteCount,
    QP.HasAcceptedAnswer,
    QP.AcceptedAnswerScore,
    COALESCE(AA_UA.DisplayName, 'Community User') AS AcceptedAnswerOwnerDisplayName,
    COALESCE(AA_UA.Reputation, 0) AS AcceptedAnswerOwnerReputation,
    QP.IsPerformanceRelatedTag,
    QP.LastCloseReasonName,
    PHA.TotalHistoryEvents,
    PHA.MinorEditEvents,
    PHA.ClosureDeletionOrLockEvents,
    PHA.UniqueEditors,
    -- Complex calculated ratios
    CAST(QP.NetVotes AS DECIMAL) / NULLIF(QP.ViewCount, 0) AS VotePerViewRatio,
    CAST(QP.CommentCount AS DECIMAL) / NULLIF(QP.AnswerCount + 1, 0) AS CommentsPerAnswerRatio, -- Add 1 to AnswerCount to prevent division by zero for questions with no answers
    CAST(QP.FavoriteCount AS DECIMAL) / NULLIF(QP.ViewCount, 0) AS FavoritePerViewRatio,
    -- Window functions for ranking and temporal analysis
    RANK() OVER (PARTITION BY EXTRACT(YEAR FROM QP.PostCreationDate) ORDER BY QP.NetVotes DESC, QP.ViewCount DESC) AS RankByNetVotesInYear,
    NTILE(10) OVER (ORDER BY QP.ViewCount DESC, QP.NetVotes DESC, QP.FavoriteCount DESC) AS TopEngagementDecile, -- Divides posts into 10 engagement groups
    LAG(QP.PostCreationDate, 1, '1970-01-01 00:00:00') OVER (PARTITION BY QP.OwnerUserId ORDER BY QP.PostCreationDate) AS PreviousPostDateByOwner,
    LEAD(QP.PostCreationDate, 1, '2099-12-31 23:59:59') OVER (PARTITION BY QP.OwnerUserId ORDER BY QP.PostCreationDate) AS NextPostDateByOwner,
    AVG(QP.NetVotes) OVER (PARTITION BY EXTRACT(MONTH FROM QP.PostCreationDate), QP.IsPerformanceRelatedTag) AS AvgNetVotesMonthlyForTagType,
    -- String expressions and NULL logic for formatted tags and question status
    CASE
        WHEN QP.Tags IS NULL OR TRIM(QP.Tags) = '' THEN 'No Tags Provided'
        WHEN LENGTH(QP.Tags) > 60 THEN SUBSTRING(QP.Tags, 2, 58) || '...>' -- Extracts a snippet of tags, removing initial '<' and adding ellipsis
        ELSE SUBSTRING(QP.Tags, 2, LENGTH(QP.Tags) - 2)
    END AS FormattedTagsSnippet,
    CASE
        WHEN QP.ClosedDate IS NOT NULL AND (PHA.ClosureDeletionOrLockEvents > 0 OR QP.LastCloseReasonName IS NOT NULL) THEN 'Closed/Moderated'
        WHEN (cast('2024-10-01 12:34:56' as timestamp) - QP.LastActivityDate) > INTERVAL '1 year' AND QP.AnswerCount = 0 THEN 'Stale - No Answers'
        WHEN QP.HasAcceptedAnswer THEN 'Solved with Accepted Answer'
        WHEN QP.AnswerCount > 0 THEN 'Active - Unsolved'
        ELSE 'Open - No Answers'
    END AS QuestionStatusCategory,
    -- Correlated subquery to count the owner's recent questions before this specific post
    (SELECT COUNT(P2.Id)
     FROM Posts P2
     WHERE P2.OwnerUserId = QP.OwnerUserId
       AND P2.PostTypeId = 1
       AND P2.CreationDate BETWEEN (QP.PostCreationDate - INTERVAL '3 months') AND QP.PostCreationDate -- Questions within the last 3 months
       AND P2.Id != QP.PostId
    ) AS OwnerRecentQuestionsIn3Months,
    -- Elaborate composite score calculation combining multiple engagement and quality factors
    (
        (CAST(QP.NetVotes AS DECIMAL) * 0.45) + -- Net votes heavily weighted
        (CAST(QP.ViewCount AS DECIMAL) / 500.0 * 0.15) + -- Views contribute proportionally
        (CAST(QP.AnswerCount AS DECIMAL) * 1.5 * (CASE WHEN QP.HasAcceptedAnswer THEN 2.0 ELSE 1.0 END) * 0.15) + -- Answers are important, more so if accepted
        (CAST(QP.CommentCount AS DECIMAL) * 0.5 * 0.05) + -- Comments add a small boost
        (CAST(QP.FavoriteCount AS DECIMAL) * 3.0 * 0.1) + -- Favorites show strong user interest
        (COALESCE(PHA.MinorEditEvents, 0) * 0.01) - -- Minor edits indicate refinement
        (COALESCE(PHA.ClosureDeletionOrLockEvents, 0) * 10.0) + -- Penalize heavily for moderation actions
        (CASE WHEN QP.IsPerformanceRelatedTag THEN 5.0 ELSE 0.0 END) + -- Bonus for specific tag relevance
        (CASE WHEN (cast('2024-10-01 12:34:56' as timestamp) - QP.LastActivityDate) < INTERVAL '3 months' THEN 2.0 ELSE 0.0 END) -- Bonus for recent activity
    ) AS CompositeEngagementScore
FROM
    QuestionPerformance QP
LEFT JOIN UserActivity UA ON QP.OwnerUserId = UA.UserId
LEFT JOIN UserActivity AA_UA ON QP.AcceptedAnswerOwnerUserId = AA_UA.UserId -- For accepted answer owner details
LEFT JOIN PostHistoryAgg PHA ON QP.PostId = PHA.PostId
LEFT JOIN UserBadges UB ON QP.OwnerUserId = UB.UserId
WHERE
    QP.PostCreationDate >= '2020-01-01' -- Focus on recent history
    AND QP.ViewCount > 500 -- Filter for reasonably popular questions
    AND QP.NetVotes >= 10 -- Filter for positively perceived questions
    AND QP.Title IS NOT NULL
    AND TRIM(QP.Title) != ''
    AND LOWER(QP.Title) NOT LIKE '%test question%' -- Exclude obvious test/junk posts
    AND (
        (QP.IsPerformanceRelatedTag AND QP.AnswerCount > 0) -- Performance-related questions with answers
        OR (QP.HasAcceptedAnswer AND QP.NetVotes >= 20) -- Any solved question with significant net votes
        OR (QP.PostCreationDate BETWEEN '2023-01-01' AND '2023-03-31' AND QP.ViewCount >= 1000) -- Recently very popular questions
    )
ORDER BY
    CompositeEngagementScore DESC, QP.PostCreationDate DESC, QP.ViewCount DESC
LIMIT 1000;