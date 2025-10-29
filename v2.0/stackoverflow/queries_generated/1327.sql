-- {"query": "1327.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3197} 

WITH UserActivitySummary AS (
    -- Aggregates user activity and reputation metrics, ranks users by their total post scores.
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserDisplayName,
        U.Reputation,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersGiven,
        -- Total score received across all posts, handling potential NULL scores gracefully.
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreReceived,
        -- Average score of all posts owned by the user, treating NULL scores as 0 for averaging.
        AVG(CASE WHEN P.Score IS NOT NULL THEN P.Score ELSE 0 END) AS AvgPostScore,
        MAX(P.CreationDate) AS LatestPostCreationDate,
        MIN(P.CreationDate) AS EarliestPostCreationDate,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        -- Window function: Rank users based on their total post score received, breaking ties with reputation.
        RANK() OVER (ORDER BY COALESCE(SUM(P.Score), 0) DESC, U.Reputation DESC) AS PostScoreRankGlobally
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    WHERE U.Reputation > 500 -- Focus on more established users to reduce dataset size for CTE.
      AND U.CreationDate >= '2015-01-01' -- Filter newer users for a more active subset.
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT P.Id) > 3 -- Ensure users have at least a few posts.
),
PostDetailsAggregated AS (
    -- Consolidates detailed information for each post, including tag analysis, history, and comment sentiment.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        COALESCE(P.Title, '(No Title)') AS PostTitle, -- Handle NULL titles
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.CreationDate,
        P.LastActivityDate,
        P.LastEditDate,
        P.ClosedDate,
        P.CommunityOwnedDate,
        -- Extract the first tag from the 'Tags' string, handling NULLs and missing tags.
        COALESCE(SPLIT_PART(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><', 1), 'untagged') AS FirstTag,
        -- Correlated subquery: Determines if the post has ever been officially closed based on PostHistory.
        (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.PostId = P.Id AND ph.PostHistoryTypeId = 10) > 0 AS HasBeenClosed,
        -- Aggregates upvotes and downvotes from the Votes table for the post.
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        -- Total score of all comments on this post.
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        -- Average score of comments on this post, NULL if no comments.
        AVG(C.Score) AS AverageCommentScore,
        -- Correlated subquery: Checks if any comment on the post has a negative score.
        EXISTS (SELECT 1 FROM Comments neg_c WHERE neg_c.PostId = P.Id AND neg_c.Score < 0) AS HasNegativeComments,
        -- Calculates the age of the post in full days since its creation.
        FLOOR(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - P.CreationDate)) / (60 * 60 * 24)) AS PostAgeDays,
        -- Identifies posts where the last editor is different from the original owner.
        (P.OwnerUserId IS NOT NULL AND P.LastEditorUserId IS NOT NULL AND P.OwnerUserId <> P.LastEditorUserId) AS IsEditedByOther,
        -- Calculates the length of the post body, useful for content analysis.
        LENGTH(P.Body) AS BodyLength
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3) -- Only UpMod (2) and DownMod (3)
    LEFT JOIN Comments C ON P.Id = C.PostId
    WHERE P.CreationDate >= '2022-01-01' -- Focus on posts created in recent years.
      AND P.ViewCount IS NOT NULL -- Exclude posts without view count.
    GROUP BY P.Id, P.PostTypeId, PT.Name, P.OwnerUserId, P.Title, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.CreationDate, P.LastActivityDate, P.LastEditDate, P.ClosedDate, P.CommunityOwnedDate, P.Tags, P.LastEditorUserId, P.Body
    HAVING COUNT(DISTINCT P.Id) = 1 -- Ensure distinct posts after group by for PostId.
),
HighlyEngagedPosts AS (
    -- Filters and further processes posts based on engagement metrics like score and vote ratios.
    SELECT
        PDA.PostId,
        PDA.OwnerUserId,
        PDA.PostTypeName,
        PDA.PostScore,
        PDA.UpVoteCount,
        PDA.DownVoteCount,
        -- Calculates the ratio of upvotes to total votes, handling potential division by zero.
        CASE WHEN (PDA.UpVoteCount + PDA.DownVoteCount) > 0
             THEN CAST(PDA.UpVoteCount AS NUMERIC) / (PDA.UpVoteCount + PDA.DownVoteCount)
             ELSE 0
        END AS UpVoteRatio,
        -- Window function: Ranks posts by score within each post type.
        ROW_NUMBER() OVER (PARTITION BY PDA.PostTypeId ORDER BY PDA.PostScore DESC, PDA.CreationDate DESC) AS PostTypeScoreRank,
        -- Window function: Calculates a running sum of post scores for each user's posts, ordered by creation date.
        SUM(PDA.PostScore) OVER (PARTITION BY PDA.OwnerUserId ORDER BY PDA.CreationDate ASC) AS RunningUserPostScore
    FROM PostDetailsAggregated PDA
    WHERE PDA.PostScore > 5 OR PDA.UpVoteCount > 10 -- Focus on posts with significant positive reception.
),
QuestionAnswerAnalysis AS (
    -- Analyzes the quality of accepted answers for questions.
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.OwnerUserId AS QuestionOwnerUserId,
        A.Id AS AcceptedAnswerId,
        A.Score AS AcceptedAnswerScore,
        UA.DisplayName AS AcceptedAnswerOwnerName,
        UA.Reputation AS AcceptedAnswerOwnerReputation,
        -- Correlated subquery: Checks if the owner of the accepted answer has a high reputation.
        (SELECT US.Reputation FROM Users US WHERE US.Id = A.OwnerUserId) > 25000 AS IsAcceptedAnswerByVeryHighRepUser,
        -- Counts the number of duplicate links associated with the question.
        (SELECT COUNT(PL_Dup.Id) FROM PostLinks PL_Dup WHERE PL_Dup.PostId = Q.Id AND PL_Dup.LinkTypeId = 3) AS DuplicateLinkCount,
        -- Calculates the time difference between question creation and accepted answer creation in minutes.
        EXTRACT(EPOCH FROM (A.CreationDate - Q.CreationDate)) / 60 AS TimeToAcceptAnswerMinutes
    FROM Posts Q
    JOIN Posts A ON Q.AcceptedAnswerId = A.Id -- Join question to its accepted answer.
    LEFT JOIN Users UA ON A.OwnerUserId = UA.Id
    WHERE Q.PostTypeId = 1 -- Only questions.
      AND Q.AcceptedAnswerId IS NOT NULL -- Only questions with an accepted answer.
      AND A.CreationDate > Q.CreationDate -- Ensure answer was created after question.
)
-- Final SELECT statement, combining all CTEs with complex logic, filtering, and calculations.
SELECT
    UAS.UserId,
    UAS.UserDisplayName,
    UAS.Reputation,
    UAS.TotalPostsOwned,
    UAS.TotalPostScoreReceived,
    HEP.PostId,
    HEP.PostTypeName,
    PDA.PostTitle,
    PDA.PostScore,
    PDA.ViewCount,
    PDA.CommentCount,
    PDA.FavoriteCount,
    HEP.UpVoteCount,
    HEP.DownVoteCount,
    HEP.UpVoteRatio,
    HEP.PostTypeScoreRank,
    HEP.RunningUserPostScore,
    PDA.FirstTag,
    PDA.HasBeenClosed,
    PDA.HasNegativeComments,
    PDA.PostAgeDays,
    PDA.TotalCommentScore,
    PDA.AverageCommentScore,
    QAA.AcceptedAnswerScore,
    QAA.AcceptedAnswerOwnerName,
    QAA.IsAcceptedAnswerByVeryHighRepUser,
    QAA.DuplicateLinkCount,
    QAA.TimeToAcceptAnswerMinutes,
    PDA.BodyLength,
    PDA.IsEditedByOther,
    -- Complex calculation: Engagement Ratio, weighing comments, answers, and favorites against views.
    CAST(PDA.CommentCount + COALESCE(PDA.AnswerCount, 0) + COALESCE(PDA.FavoriteCount, 0) AS NUMERIC) / (PDA.ViewCount + 1) AS EngagementRatio,
    -- String expression: Creates a summary snippet of the post, handling NULLs and long titles.
    COALESCE(UAS.UserDisplayName, 'Community User') || ' posted "' || SUBSTRING(PDA.PostTitle, 1, 75) || (CASE WHEN LENGTH(PDA.PostTitle) > 75 THEN '...' ELSE '' END) || '" (ID:' || CAST(HEP.PostId AS VARCHAR) || ')' AS PostSummarySnippet,
    -- NULL logic and conditional expression: Categorizes post based on its edit and closed status.
    CASE
        WHEN PDA.LastEditDate IS NOT NULL AND PDA.LastEditDate > PDA.CreationDate AND PDA.HasBeenClosed AND PDA.CommunityOwnedDate IS NOT NULL
        THEN 'Edited, Closed & Community Owned'
        WHEN PDA.LastEditDate IS NOT NULL AND PDA.LastEditDate > PDA.CreationDate AND PDA.HasBeenClosed
        THEN 'Edited & Closed'
        WHEN PDA.LastEditDate IS NOT NULL AND PDA.LastEditDate > PDA.CreationDate
        THEN 'Edited'
        WHEN PDA.HasBeenClosed THEN 'Closed'
        WHEN PDA.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Original State'
    END AS PostStatusFlag,
    -- Correlated subquery: Checks if the post owner has any gold badges.
    EXISTS (SELECT 1 FROM Badges B WHERE B.UserId = UAS.UserId AND B.Class = 1) AS HasOwnerGoldBadge,
    -- Complex predicate to identify "problematic" users (e.g., high downvote ratio).
    (UAS.UserDownVotesGiven > 100 AND UAS.UserDownVotesGiven > UAS.UserUpVotesGiven * 0.5) AS IsPotentiallyProblematicUser
FROM UserActivitySummary UAS
JOIN HighlyEngagedPosts HEP ON UAS.UserId = HEP.OwnerUserId
JOIN PostDetailsAggregated PDA ON HEP.PostId = PDA.PostId
LEFT JOIN QuestionAnswerAnalysis QAA ON PDA.PostId = QAA.QuestionId
WHERE PDA.ViewCount > 500 -- Posts with significant view counts.
  AND PDA.PostScore >= 10 -- Posts with good scores.
  AND PDA.FirstTag IS NOT NULL AND PDA.FirstTag <> 'untagged' -- Ensure tags are present.
  AND (UAS.Reputation > 10000 OR HEP.PostTypeScoreRank <= 5) -- Filter for highly reputed users or top-ranked posts within their type.
  AND PDA.PostAgeDays BETWEEN 30 AND 730 -- Posts between 1 month and 2 years old.
  AND HEP.UpVoteRatio >= 0.8 -- Only highly upvoted posts.
  AND PDA.HasNegativeComments IS FALSE -- Exclude posts with negative comments.
  AND PDA.FavoriteCount >= 1 -- Posts favorited at least once.
  -- Correlated subquery: Excludes posts that are duplicates of more than 3 other posts.
  AND NOT EXISTS (
      SELECT 1
      FROM PostLinks PL_Excl
      WHERE PL_Excl.RelatedPostId = PDA.PostId
        AND PL_Excl.LinkTypeId = 3 -- Duplicate link type
      GROUP BY PL_Excl.RelatedPostId
      HAVING COUNT(PL_Excl.PostId) > 3
  )
  -- Another complex predicate: posts with a very active last editor if they are also highly viewed.
  AND (NOT PDA.IsEditedByOther OR (PDA.IsEditedByOther AND PDA.ViewCount > 1000 AND PDA.LastEditDate > PDA.CreationDate + INTERVAL '1 hour'))
ORDER BY UAS.Reputation DESC, HEP.PostScore DESC, HEP.UpVoteRatio DESC, QAA.TimeToAcceptAnswerMinutes ASC NULLS LAST
LIMIT 1000;
