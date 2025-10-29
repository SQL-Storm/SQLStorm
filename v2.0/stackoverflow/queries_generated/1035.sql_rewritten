-- {"query": "1035.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4337} 
WITH UserEngagement AS (
    -- Calculate engagement metrics for users, including badge counts and a derived activity score.
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        MAX(B.Date) AS LastBadgeDate,
        -- Calculate a user activity score based on votes, views, reputation, and recent access.
        (U.UpVotes - U.DownVotes) * 0.1 + U.Views * 0.01 + U.Reputation * 0.5 + 
        CASE 
            WHEN U.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days' THEN 100 
            WHEN U.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days' THEN 50 
            ELSE 10 
        END AS UserActivityScore
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.Reputation, U.Views, U.UpVotes, U.DownVotes, U.CreationDate, U.LastAccessDate
    HAVING COUNT(DISTINCT B.Id) >= 3 -- Only consider users with at least 3 badges
),
PostCommentSentiment AS (
    -- Analyze comments for posts to gauge sentiment, total activity, and owner's specific comment score.
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalComments,
        AVG(C.Score) AS AvgCommentScore,
        MAX(C.CreationDate) AS LastCommentDate,
        -- Derive a simple sentiment score based on keywords in comments.
        SUM(CASE 
                WHEN LOWER(C.Text) LIKE '%thank you%' OR LOWER(C.Text) LIKE '%helpful%' THEN 1 
                WHEN LOWER(C.Text) LIKE '%bug%' OR LOWER(C.Text) LIKE '%error%' OR LOWER(C.Text) LIKE '%issue%' THEN -1 
                ELSE 0 
            END) AS SentimentScore,
        COUNT(DISTINCT C.UserId) AS DistinctCommenters,
        -- Correlated subquery to find the score of the most recent comment made by the post's owner.
        (
            SELECT COALESCE(MAX(SubC.Score), 0)
            FROM Comments SubC
            INNER JOIN Posts SubP ON SubC.PostId = SubP.Id
            WHERE SubC.PostId = C.PostId 
              AND SubC.UserId = SubP.OwnerUserId
              AND SubC.CreationDate = (SELECT MAX(SubC2.CreationDate) FROM Comments SubC2 WHERE SubC2.PostId = SubC.PostId AND SubC2.UserId = SubP.OwnerUserId)
        ) AS OwnerLastCommentScore
    FROM Comments C
    GROUP BY C.PostId
),
PostHistoryTimeline AS (
    -- Analyze post history events to count edits, closures, reopens, and determine event chronology.
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edit
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount,
        MIN(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6)) AS FirstEditDate,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (10, 11)) AS LastClosureOrReopenDate,
        -- Window function to rank history events for each post by creation date.
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS HistoryEventRank,
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousEventDate
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 10, 11, 12, 13) -- Focus on creation, edits, close/reopen/delete/undelete
    GROUP BY PH.PostId, PH.CreationDate, PH.Id -- Necessary for window functions to operate correctly
),
PostVoteAggregates AS (
    -- Aggregate vote information for posts, including up/down vote counts and their ratio.
    SELECT
        P.Id AS PostId,
        COUNT(V.Id) AS TotalVotes,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(DISTINCT V.UserId) AS DistinctVoters,
        SUM(CASE WHEN V.VoteTypeId = 8 THEN V.BountyAmount ELSE 0 END) AS TotalBountyAmount,
        -- Calculate up-to-down vote ratio, handling potential division by zero.
        COALESCE(CAST(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS NUMERIC) / 
                 NULLIF(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0), 0) AS UpToDownVoteRatio
    FROM Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId
    GROUP BY P.Id
),
TagPopularity AS (
    -- Calculate popularity metrics for tags and rank them.
    SELECT
        T.TagName,
        T.Id AS TagId,
        T.Count AS TagUseCount,
        P_Wiki.ViewCount AS WikiViewCount,
        P_Excerpt.Score AS ExcerptScore,
        RANK() OVER (ORDER BY T.Count DESC, P_Wiki.ViewCount DESC) AS TagRank
    FROM Tags T
    LEFT JOIN Posts P_Wiki ON T.WikiPostId = P_Wiki.Id
    LEFT JOIN Posts P_Excerpt ON T.ExcerptPostId = P_Excerpt.Id
    WHERE T.IsModeratorOnly = FALSE AND T.IsRequired = FALSE
),
QuestionDetails AS (
    -- Select primary questions and join with their associated aggregated data.
    SELECT
        P.Id AS QuestionId,
        P.Title,
        P.Body,
        P.CreationDate AS QuestionCreationDate,
        P.Score AS QuestionScore,
        P.ViewCount AS QuestionViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount, -- From Posts table, distinct from PostCommentSentiment
        P.FavoriteCount,
        P.ClosedDate,
        P.LastActivityDate,
        P.OwnerUserId,
        P.Tags,
        UE.Reputation AS OwnerReputation,
        UE.TotalBadges AS OwnerTotalBadges,
        UE.UserActivityScore AS OwnerActivityScore,
        PCS.TotalComments,
        PCS.AvgCommentScore,
        PCS.SentimentScore,
        PCS.DistinctCommenters,
        PCS.OwnerLastCommentScore,
        PHT.EditCount,
        PHT.CloseCount,
        PHT.ReopenCount,
        PHT.LastClosureOrReopenDate,
        PVA.UpVotes AS TotalUpVotes,
        PVA.DownVotes AS TotalDownVotes,
        PVA.DistinctVoters,
        PVA.UpToDownVoteRatio,
        -- Count linked duplicates.
        (SELECT COUNT(DISTINCT PL.RelatedPostId) FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 3) AS DuplicateLinkCount,
        -- Check if any linked duplicate has an accepted answer using EXISTS.
        EXISTS (
            SELECT 1
            FROM PostLinks PL
            INNER JOIN Posts RelatedP ON PL.RelatedPostId = RelatedP.Id
            WHERE PL.PostId = P.Id AND PL.LinkTypeId = 3 AND RelatedP.AcceptedAnswerId IS NOT NULL
        ) AS HasLinkedDuplicateWithAcceptedAnswer
    FROM Posts P
    INNER JOIN UserEngagement UE ON P.OwnerUserId = UE.UserId -- Inner join to ensure question has an owner with engagement data
    LEFT JOIN PostCommentSentiment PCS ON P.Id = PCS.PostId
    LEFT JOIN PostHistoryTimeline PHT ON P.Id = PHT.PostId
    LEFT JOIN PostVoteAggregates PVA ON P.Id = PVA.PostId
    WHERE P.PostTypeId = 1 -- Only questions
    AND P.CreationDate BETWEEN cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 years' AND cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year' -- Filter for a specific period
    AND P.Score >= 5
),
AnswerDetails AS (
    -- Select answer details, including accepted status and owner's reputation.
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.Score AS AnswerScore,
        A.CreationDate AS AnswerCreationDate,
        A.OwnerUserId AS AnswerOwnerUserId,
        U.Reputation AS AnswerOwnerReputation,
        CASE WHEN P.AcceptedAnswerId = A.Id THEN TRUE ELSE FALSE END AS IsAcceptedAnswer,
        LENGTH(A.Body) AS AnswerBodyLength,
        SUBSTRING(A.Body, 1, 100) AS AnswerBodyExcerpt
    FROM Posts A
    INNER JOIN Posts P ON A.ParentId = P.Id
    LEFT JOIN Users U ON A.OwnerUserId = U.Id
    WHERE A.PostTypeId = 2 -- Only answers
    AND A.Score >= 1
),
FinalRankedPosts AS (
    -- Combine question and answer details, calculate a complex composite score, and rank.
    SELECT
        QD.QuestionId AS PostId,
        'Question' AS PostType,
        QD.Title AS PostTitle,
        QD.QuestionCreationDate AS PostCreationDate,
        QD.QuestionScore AS PostScore,
        QD.QuestionViewCount AS PostViewCount,
        QD.AnswerCount,
        QD.OwnerUserId,
        QD.OwnerReputation,
        QD.OwnerActivityScore,
        COALESCE(QD.TotalComments, 0) AS TotalComments,
        COALESCE(QD.SentimentScore, 0) AS CommentSentiment,
        COALESCE(QD.EditCount, 0) AS EditCount,
        COALESCE(QD.ReopenCount, 0) AS ReopenCount,
        COALESCE(QD.TotalUpVotes, 0) AS TotalUpVotes,
        COALESCE(QD.TotalDownVotes, 0) AS TotalDownVotes,
        COALESCE(QD.UpToDownVoteRatio, 0) AS UpToDownVoteRatio,
        QD.DuplicateLinkCount,
        QD.HasLinkedDuplicateWithAcceptedAnswer,
        -- Calculate a complex composite score for questions.
        (QD.QuestionScore * 0.5 + QD.QuestionViewCount * 0.01 + QD.AnswerCount * 1.5 + QD.FavoriteCount * 2 +
         COALESCE(QD.OwnerActivityScore, 0) * 0.1 + COALESCE(QD.SentimentScore, 0) * 0.8 +
         CASE WHEN QD.ReopenCount > 0 THEN -10 ELSE 0 END + -- Penalize reopened posts
         CASE WHEN QD.HasLinkedDuplicateWithAcceptedAnswer THEN -5 ELSE 0 END + -- Penalize if linked to an accepted answer duplicate
         COALESCE(LENGTH(QD.Body), 0) * 0.001 -- Reward longer questions
        ) AS CompositePostScore,
        -- Window function: Rank questions by their composite score within their creation year.
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM QD.QuestionCreationDate) ORDER BY (QD.QuestionScore * 0.5 + QD.QuestionViewCount * 0.01 + QD.AnswerCount * 1.5 + QD.FavoriteCount * 2) DESC, QD.QuestionId) AS RankInYear,
        -- Extract the first tag from the tags string.
        SPLIT_PART(SUBSTRING(QD.Tags, 2, LENGTH(QD.Tags)-2), '><', 1) AS FirstTag
    FROM QuestionDetails QD
    WHERE QD.ClosedDate IS NULL OR (QD.ClosedDate IS NOT NULL AND QD.ReopenCount > QD.CloseCount) -- Exclude truly closed posts, allow reopened ones
    AND QD.AnswerCount >= 1 -- Questions with at least one answer
    AND LENGTH(QD.Body) > 100 -- Ensure substantial question body
    AND QD.OwnerReputation > 5000 -- Only from reasonably reputable users
    AND (QD.Tags LIKE '%<sql>%' OR QD.Tags LIKE '%<database>%') -- Must be related to SQL or database
    -- Complex predicate involving multiple conditions and NULL logic.
    AND (
        (QD.OwnerLastCommentScore > 5 AND QD.DistinctCommenters >= 2) OR 
        (QD.SentimentScore IS NULL AND QD.QuestionScore > 100) OR 
        (QD.LastClosureOrReopenDate IS NOT NULL AND QD.LastClosureOrReopenDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months')
    )

    UNION ALL

    -- Process answers with similar metrics and a composite score.
    SELECT
        AD.AnswerId AS PostId,
        'Answer' AS PostType,
        SUBSTRING(P.Title, 1, 200) AS PostTitle, -- Use parent question's title excerpt
        AD.AnswerCreationDate AS PostCreationDate,
        AD.AnswerScore AS PostScore,
        NULL AS PostViewCount, -- Answers don't have direct view counts
        NULL AS AnswerCount, -- Not applicable for answers
        AD.AnswerOwnerUserId AS OwnerUserId,
        AD.AnswerOwnerReputation AS OwnerReputation,
        UE.UserActivityScore AS OwnerActivityScore,
        COALESCE(PCS.TotalComments, 0) AS TotalComments,
        COALESCE(PCS.SentimentScore, 0) AS CommentSentiment,
        COALESCE(PHT.EditCount, 0) AS EditCount,
        COALESCE(PHT.ReopenCount, 0) AS ReopenCount, -- Reopen applies to parent question
        COALESCE(PVA.UpVotes, 0) AS TotalUpVotes,
        COALESCE(PVA.DownVotes, 0) AS TotalDownVotes,
        COALESCE(PVA.UpToDownVoteRatio, 0) AS UpToDownVoteRatio,
        0 AS DuplicateLinkCount, -- Not applicable for answers
        FALSE AS HasLinkedDuplicateWithAcceptedAnswer, -- Not applicable
        -- Composite score for answers.
        (AD.AnswerScore * 2 + AD.AnswerBodyLength * 0.005 + 
         CASE WHEN AD.IsAcceptedAnswer THEN 50 ELSE 0 END +
         COALESCE(UE.UserActivityScore, 0) * 0.05 + COALESCE(PCS.SentimentScore, 0) * 0.6
        ) AS CompositePostScore,
        -- Window function: Rank answers by their composite score within their creation year.
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM AD.AnswerCreationDate) ORDER BY AD.AnswerScore DESC, AD.AnswerId) AS RankInYear,
        SPLIT_PART(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><', 1) AS FirstTag
    FROM AnswerDetails AD
    LEFT JOIN UserEngagement UE ON AD.AnswerOwnerUserId = UE.UserId
    LEFT JOIN PostCommentSentiment PCS ON AD.AnswerId = PCS.PostId
    LEFT JOIN PostHistoryTimeline PHT ON AD.AnswerId = PHT.PostId
    LEFT JOIN PostVoteAggregates PVA ON AD.AnswerId = PVA.PostId
    INNER JOIN Posts P ON AD.QuestionId = P.Id -- Join back to Questions for tags/title
    WHERE AD.AnswerScore > 10 AND AD.AnswerBodyLength > 200
    AND AD.AnswerCreationDate BETWEEN cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '4 years' AND cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    AND (UE.TotalBadges IS NULL OR UE.TotalBadges >= 5) -- Example of NULL logic in filter for users
    AND P.Tags LIKE '%<performance>%' -- Focus on specific tag for answers
)
-- Final selection and ordering of the combined ranked posts.
SELECT
    FRP.PostId,
    FRP.PostType,
    FRP.PostTitle,
    FRP.PostCreationDate,
    FRP.PostScore,
    FRP.PostViewCount,
    FRP.AnswerCount,
    FRP.OwnerUserId,
    FRP.OwnerReputation,
    FRP.TotalComments,
    FRP.CommentSentiment,
    FRP.EditCount,
    FRP.ReopenCount,
    FRP.TotalUpVotes,
    FRP.TotalDownVotes,
    FRP.UpToDownVoteRatio,
    FRP.DuplicateLinkCount,
    FRP.HasLinkedDuplicateWithAcceptedAnswer,
    FRP.CompositePostScore,
    FRP.RankInYear,
    FRP.FirstTag,
    -- Correlated subquery to compare current post's score against the average for its first tag and post type.
    COALESCE(FRP.PostScore - (SELECT AVG(FRP2.PostScore) FROM FinalRankedPosts FRP2 WHERE FRP2.FirstTag = FRP.FirstTag AND FRP2.PostType = FRP.PostType), 0) AS ScoreVsAvgTag,
    -- Correlated subquery to check if the post owner has any gold badges.
    (SELECT COUNT(*) FROM Badges B WHERE B.UserId = FRP.OwnerUserId AND B.Class = 1) > 0 AS OwnerHasGoldBadge
FROM FinalRankedPosts FRP
LEFT JOIN TagPopularity TP ON FRP.FirstTag = TP.TagName -- Left join TagPopularity for potential future use or to include in selection (not currently selected)
WHERE FRP.CompositePostScore > 50 -- Filter by a reasonable composite score threshold
AND FRP.RankInYear <= 100 -- Limit to top 100 ranked posts per year for each creation year partition
ORDER BY FRP.PostType DESC, FRP.CompositePostScore DESC, FRP.PostCreationDate DESC
LIMIT 1000;