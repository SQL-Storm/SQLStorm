-- {"query": "1492.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3105} 

WITH UserBaseStats AS (
    -- Aggregates basic user statistics, including badge counts and vote ratios.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.UpVotes,
        U.DownVotes,
        COALESCE(CAST(U.UpVotes AS NUMERIC) / NULLIF(U.DownVotes, 0), 0) AS UpDownVoteRatio,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        MAX(U.LastAccessDate) AS LastAccessDate,
        U.Location,
        RANK() OVER (ORDER BY U.Reputation DESC, U.CreationDate ASC) AS GlobalReputationRank
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes, U.Location
),
PostWindowStats AS (
    -- Calculates window functions related to posts, specifically for individual posts by owner.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        LAG(P.Score, 1, 0) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PreviousPostScore,
        RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC) AS PostScoreRankByOwner
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
      AND P.PostTypeId IN (1, 2) -- Only questions and answers relevant for score ranking.
),
PostAggregates AS (
    -- Aggregates comment and post history data per post, along with base post details.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.ParentId,
        P.OwnerUserId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        P.LastEditDate,
        P.LastEditorUserId,
        STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><') AS TagArray,
        -- Aggregates for comments
        AVG(COALESCE(C.Score, 0)) AS AvgCommentScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        -- Aggregates for post history (edits, closes, etc.)
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN PH.CreationDate ELSE NULL END) AS LastCloseDate,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN PH.Id END) AS CloseHistoryEntryCount,
        -- Votes
        (SELECT COUNT(DISTINCT V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpvoteCount,
        (SELECT COUNT(DISTINCT V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS DownvoteCount
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    GROUP BY P.Id, P.PostTypeId, P.ParentId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount,
             P.AnswerCount, P.CommentCount, P.FavoriteCount, P.Title, P.Tags, P.LastEditDate, P.LastEditorUserId
),
PostMetrics AS (
    -- Combines post aggregates with window function results.
    SELECT
        PA.PostId,
        PA.PostTypeId,
        PA.ParentId,
        PA.OwnerUserId,
        PA.CreationDate,
        PA.Score,
        PA.ViewCount,
        PA.AnswerCount,
        PA.CommentCount,
        PA.FavoriteCount,
        PA.Title,
        PA.Tags,
        PA.LastEditDate,
        PA.LastEditorUserId,
        PA.TagArray,
        PA.AvgCommentScore,
        PA.TotalComments,
        PA.EditCount,
        PA.LastCloseDate,
        PA.CloseHistoryEntryCount,
        PA.UpvoteCount,
        PA.DownvoteCount,
        PWS.PreviousPostScore,
        PWS.PostScoreRankByOwner
    FROM PostAggregates PA
    JOIN PostWindowStats PWS ON PA.PostId = PWS.PostId
),
QuestionAnswerAggregates AS (
    -- Filters for questions and answers, enriching with user and derived metrics.
    SELECT
        PM.PostId,
        PM.PostTypeId,
        PM.CreationDate AS PostCreationDate,
        PM.Score,
        PM.OwnerUserId,
        UBS.DisplayName AS OwnerDisplayName,
        UBS.Reputation,
        PM.Title,
        PM.TagArray,
        PM.AvgCommentScore,
        PM.EditCount,
        PM.UpvoteCount,
        PM.DownvoteCount,
        PM.PreviousPostScore,
        PM.PostScoreRankByOwner,
        (PM.UpvoteCount - PM.DownvoteCount) AS NetVotes,
        CASE
            WHEN PM.PostTypeId = 1 THEN PM.AnswerCount
            ELSE 0 -- Answers do not have an 'AnswerCount' attribute
        END AS RelatedAnswerCount,
        COALESCE(DATE_PART('day', PM.LastCloseDate - PM.CreationDate), -1) AS DaysToClose -- NULL if never closed, -1 if no close activity
    FROM PostMetrics PM
    JOIN UserBaseStats UBS ON PM.OwnerUserId = UBS.UserId
    WHERE PM.PostTypeId IN (1, 2) -- Focus on Questions and Answers
      AND PM.OwnerUserId IS NOT NULL -- Exclude community-owned posts
),
HighlyVotedPosts AS (
    -- Identifies highly-voted questions by reputable users.
    SELECT
        QAA.PostId,
        QAA.PostTypeId,
        QAA.Title,
        QAA.OwnerDisplayName,
        QAA.OwnerUserId,
        QAA.NetVotes,
        QAA.PostCreationDate
    FROM QuestionAnswerAggregates QAA
    WHERE QAA.NetVotes > 200
      AND QAA.PostScoreRankByOwner <= 5 -- Among the top 5 posts by the owner
      AND QAA.PostTypeId = 1 -- Only questions
      AND QAA.Reputation >= 10000 -- By highly reputable users
),
RecentControversialPosts AS (
    -- Finds recent posts with significant upvotes and downvotes, indicating controversy.
    SELECT
        QAA.PostId,
        QAA.PostTypeId,
        QAA.Title,
        QAA.OwnerDisplayName,
        QAA.OwnerUserId,
        QAA.NetVotes,
        QAA.PostCreationDate
    FROM QuestionAnswerAggregates QAA
    WHERE QAA.PostCreationDate >= NOW() - INTERVAL '180 days' -- Within the last 6 months
      AND QAA.UpvoteCount > 50
      AND QAA.DownvoteCount > 20
      AND ABS(QAA.UpvoteCount - QAA.DownvoteCount) < (QAA.UpvoteCount + QAA.DownvoteCount) * 0.5 -- Ratio indicating balanced opinions
      AND QAA.AvgCommentScore < 1.0 -- Potentially negative sentiment in comments
),
InfluentialOldPosts AS (
    -- Identifies older, influential questions that have not been closed and received multiple edits.
    SELECT
        QAA.PostId,
        QAA.PostTypeId,
        QAA.Title,
        QAA.OwnerDisplayName,
        QAA.OwnerUserId,
        QAA.NetVotes,
        QAA.PostCreationDate
    FROM QuestionAnswerAggregates QAA
    WHERE QAA.PostCreationDate < NOW() - INTERVAL '2 year' -- Older than 2 years
      AND QAA.NetVotes > 100
      AND QAA.EditCount >= 3 -- Edited at least 3 times
      AND QAA.PostTypeId = 1 -- Only questions
      AND QAA.DaysToClose = -1 -- Never closed
      AND EXISTS (SELECT 1 FROM Posts A WHERE A.ParentId = QAA.PostId AND A.AcceptedAnswerId IS NOT NULL AND A.AcceptedAnswerId = A.Id) -- Has an accepted answer
)
-- Final selection combining results from various categories using UNION ALL.
SELECT
    FinalResult.PostId,
    FinalResult.PostTypeId,
    PostTypes.Name AS PostTypeName,
    FinalResult.PostTitle,
    FinalResult.OwnerDisplayName,
    UBS.Reputation AS OwnerReputation,
    FinalResult.PostNetVotes,
    FinalResult.PostCreationDate,
    PM.AvgCommentScore,
    PM.EditCount,
    QAA.RelatedAnswerCount,
    FinalResult.PostTypeCategory,
    UBS.Location AS OwnerLocation,
    DATE_PART('year', AGE(NOW(), UBS.UserCreationDate)) AS OwnerAccountAgeYears,
    COALESCE(UBS.TotalBadges, 0) AS OwnerTotalBadges,
    COALESCE(UBS.GoldBadges, 0) AS OwnerGoldBadges,
    (SELECT COUNT(DISTINCT B.Id) FROM Badges B WHERE B.UserId = FinalResult.OwnerUserId AND B.Name ILIKE '%Tag Editor%') AS HasTagEditorBadge, -- Correlated subquery for a specific badge count
    COALESCE(PM.PreviousPostScore, 0) AS PreviousPostScoreForOwner,
    PM.PostScoreRankByOwner,
    (SELECT AVG(LENGTH(T.TagName)) FROM UNNEST(PM.TagArray) AS T(TagName)) AS AvgTagLength, -- Average length of tags associated with the post
    NULLIF(LENGTH(FinalResult.PostTitle), 0) AS TitleLength,
    PM.LastCloseDate,
    PM.CloseHistoryEntryCount,
    COALESCE(LinkTypes.Name, 'No Primary Link') AS PrimaryLinkType, -- Type of the first linked post (if any, with type 'Linked')
    (SELECT COUNT(*) FROM PostLinks PL_Dup WHERE PL_Dup.PostId = FinalResult.PostId AND PL_Dup.LinkTypeId = 3) AS DuplicateLinkCount, -- Correlated subquery for count of duplicate links
    (SELECT Body FROM Posts OriginalPost WHERE OriginalPost.Id = FinalResult.PostId) AS PostBodySnippet -- Retrieve full post body (potentially expensive)
FROM (
    SELECT
        HVP.PostId,
        HVP.PostTypeId,
        HVP.Title AS PostTitle,
        HVP.OwnerDisplayName,
        HVP.OwnerUserId,
        HVP.NetVotes AS PostNetVotes,
        HVP.PostCreationDate,
        'Highly Voted Question' AS PostTypeCategory
    FROM HighlyVotedPosts HVP

    UNION ALL

    SELECT
        RCP.PostId,
        RCP.PostTypeId,
        RCP.Title AS PostTitle,
        RCP.OwnerDisplayName,
        RCP.OwnerUserId,
        RCP.NetVotes AS PostNetVotes,
        RCP.PostCreationDate,
        'Recent Controversial Post' AS PostTypeCategory
    FROM RecentControversialPosts RCP

    UNION ALL

    SELECT
        IOP.PostId,
        IOP.PostTypeId,
        IOP.Title AS PostTitle,
        IOP.OwnerDisplayName,
        IOP.OwnerUserId,
        IOP.NetVotes AS PostNetVotes,
        IOP.PostCreationDate,
        'Influential Old Question' AS PostTypeCategory
    FROM InfluentialOldPosts IOP
) AS FinalResult
LEFT JOIN UserBaseStats UBS ON FinalResult.OwnerUserId = UBS.UserId
LEFT JOIN PostMetrics PM ON FinalResult.PostId = PM.PostId
LEFT JOIN QuestionAnswerAggregates QAA ON FinalResult.PostId = QAA.PostId -- Re-join to access specific QAA-derived metrics not in PM
LEFT JOIN PostTypes ON FinalResult.PostTypeId = PostTypes.Id
LEFT JOIN PostLinks PL_Main ON FinalResult.PostId = PL_Main.PostId AND PL_Main.LinkTypeId = 1 -- Example: get first 'Linked' type link
LEFT JOIN LinkTypes ON PL_Main.LinkTypeId = LinkTypes.Id
WHERE FinalResult.OwnerUserId IS NOT NULL -- Ensure owner user data is available
  AND FinalResult.PostTitle IS NOT NULL
  AND LENGTH(FinalResult.PostTitle) > 10 -- Filter out very short or empty titles
  AND UBS.Reputation IS NOT NULL -- Ensure user reputation is known
ORDER BY FinalResult.PostNetVotes DESC, FinalResult.PostCreationDate DESC, FinalResult.PostTypeCategory
LIMIT 500;
