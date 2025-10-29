-- {"query": "1294.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4791} 
WITH UserComprehensiveStats AS (
    -- Gathers comprehensive statistics for each user, including post ownership, comments, and votes.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        COALESCE(AVG(P.Score) FILTER (WHERE P.PostTypeId IN (1,2)), 0) AS AvgOwnedPostScore,
        COALESCE(MAX(P.CreationDate), U.CreationDate) AS LastPostCreationDate,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesMade,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesMade,
        SUM(CASE WHEN PV.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceivedOnPosts,
        SUM(CASE WHEN PV.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceivedOnPosts
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId -- Votes made by the user
    LEFT JOIN Posts PPV ON U.Id = PPV.OwnerUserId -- For votes received on posts owned by user
    LEFT JOIN Votes PV ON PPV.Id = PV.PostId -- Votes received on user's posts
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
        U.Views, U.UpVotes, U.DownVotes
),
PostDetailsExtended AS (
    -- Enhances post data with editor information, detailed tag counts, and history event tracking.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Title,
        P.Body,
        P.Tags,
        P.LastActivityDate,
        P.LastEditDate,
        P.ClosedDate,
        P.AcceptedAnswerId,
        (SELECT COUNT(DISTINCT TRIM(unnest_tag))
         FROM unnest(string_to_array(REPLACE(REPLACE(P.Tags, '<', ''), '>', ','), ',')) AS unnest_tag
         WHERE unnest_tag IS NOT NULL AND TRIM(unnest_tag) != '') AS UniqueTagCount,
        COALESCE(P.AnswerCount, 0) AS ActualAnswerCount,
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'AcceptedAnswer'
            WHEN P.AnswerCount > 0 THEN 'HasAnswers'
            ELSE 'Open'
        END AS PostLifeCycleStatus,
        LEU.DisplayName AS LastEditorActualDisplayName,
        PH_CLOSED.CreationDate AS ClosedHistoryDate,
        PH_REOPENED.CreationDate AS ReopenedHistoryDate,
        PH_LAST_EDIT.CreationDate AS LastEditHistoryDate,
        LAG(PH_ALL.CreationDate, 1, P.CreationDate) OVER (PARTITION BY P.Id ORDER BY PH_ALL.CreationDate) AS PrevHistoryEventDate,
        LEAD(PH_ALL.CreationDate, 1, P.CreationDate) OVER (PARTITION BY P.Id ORDER BY PH_ALL.CreationDate) AS NextHistoryEventDate
    FROM Posts P
    LEFT JOIN Users LEU ON P.LastEditorUserId = LEU.Id
    LEFT JOIN PostHistory PH_CLOSED ON P.Id = PH_CLOSED.PostId AND PH_CLOSED.PostHistoryTypeId = 10
    LEFT JOIN PostHistory PH_REOPENED ON P.Id = PH_REOPENED.PostId AND PH_REOPENED.PostHistoryTypeId = 11
    LEFT JOIN PostHistory PH_LAST_EDIT ON P.Id = PH_LAST_EDIT.PostId AND PH_LAST_EDIT.PostHistoryTypeId IN (4,5,6) -- Any type of edit
    LEFT JOIN PostHistory PH_ALL ON P.Id = PH_ALL.PostId -- For LAG/LEAD across all history events
    WHERE P.OwnerUserId IS NOT NULL -- Exclude community user posts
    AND P.PostTypeId IN (1, 2) -- Focus on Questions and Answers
),
TopTagsByScore AS (
    -- Identifies top-performing tags based on average post score and question count.
    SELECT
        TRIM(unnest_tag) AS TagName,
        AVG(P.Score * 1.0) AS AvgScoreForTag,
        COUNT(DISTINCT P.Id) AS QuestionCountForTag
    FROM Posts P,
         unnest(string_to_array(REPLACE(REPLACE(P.Tags, '<', ''), '>', ','), ',')) AS unnest_tag
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND TRIM(unnest_tag) != ''
    GROUP BY TRIM(unnest_tag)
    HAVING COUNT(DISTINCT P.Id) > 100 -- Only consider sufficiently used tags
),
FrequentEditorActivity AS (
    -- Lists users with significant editing contributions to posts.
    SELECT
        UserId,
        COUNT(Id) AS TotalEdits,
        MAX(CreationDate) AS LastEditContributionDate
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4,5,6,8) -- Edit Title, Body, Tags, Rollback Body
    GROUP BY UserId
    HAVING COUNT(Id) >= 50 -- Users with significant editing activity
)
-- Main query to analyze high-impact users with specific post characteristics
SELECT
    UCS.UserId,
    UCS.DisplayName,
    UCS.Reputation,
    UCS.UserCreationDate,
    UCS.TotalPostsOwned,
    UCS.TotalQuestionsOwned,
    UCS.TotalAnswersOwned,
    UCS.AvgOwnedPostScore,
    UCS.TotalCommentsMade,
    UCS.TotalUpvotesReceivedOnPosts,
    UCS.TotalDownvotesReceivedOnPosts,
    PDE.PostId,
    PDE.PostCreationDate,
    PDE.PostScore,
    PDE.ViewCount AS PostViewCount,
    PDE.Title AS PostTitle,
    PDE.UniqueTagCount,
    PDE.PostLifeCycleStatus,
    -- Correlated Subquery 1: Finds the maximum score of an answer provided by this user to another user's accepted question.
    (
        SELECT COALESCE(MAX(Ans.Score), 0)
        FROM Posts Q
        JOIN Posts Ans ON Q.AcceptedAnswerId = Ans.Id
        WHERE Q.OwnerUserId <> UCS.UserId -- Not their own question
          AND Ans.OwnerUserId = UCS.UserId
          AND Ans.PostTypeId = 2
          AND Q.PostTypeId = 1
    ) AS MaxScoreAcceptedAnswerByOtherUser,
    -- Correlated Subquery 2: Retrieves the most recent comment text made by the user on their own post containing "solution".
    (
        SELECT C.Text
        FROM Comments C
        WHERE C.PostId = PDE.PostId
          AND C.UserId = UCS.UserId
          AND C.Text ILIKE '%solution%'
        ORDER BY C.CreationDate DESC
        LIMIT 1
    ) AS LatestOwnPostSolutionComment,
    -- Complicated predicates/expressions/calculations
    COALESCE(PDE.LastEditorActualDisplayName, UCS.DisplayName, 'Community') AS FinalEditorDisplayName,
    PDE.Body ILIKE '%<img src="https://i.stack.imgur.com/%' AND PDE.Body ILIKE '%"/>%' AS ContainsImgurLink,
    (EXTRACT(DAY FROM (UCS.LastAccessDate - UCS.UserCreationDate)) * 24 * 60 * 60 +
     EXTRACT(HOUR FROM (UCS.LastAccessDate - UCS.UserCreationDate)) * 60 * 60 +
     EXTRACT(MINUTE FROM (UCS.LastAccessDate - UCS.UserCreationDate)) * 60 +
     EXTRACT(SECOND FROM (UCS.LastAccessDate - UCS.UserCreationDate))) AS UserAccountAgeSeconds,
    -- String expressions
    UPPER(SUBSTRING(COALESCE(PDE.Title, 'Untitled Post'), 1, 5)) || '_' || LENGTH(COALESCE(PDE.Title, '')) AS TitlePrefixLengthHash,
    REPLACE(REPLACE(REPLACE(COALESCE(PDE.Tags, '<untagged>'), '<', ''), '>', ' '), ',', '|') AS FlattenedTagsPipeSeparated,
    NULLIF(TRIM(PDE.Body), '') IS NULL AS IsEmptyPostBody, -- NULL logic
    -- Window functions
    RANK() OVER (ORDER BY UCS.Reputation DESC, UCS.TotalPostsOwned DESC) AS OverallReputationRank,
    DENSE_RANK() OVER (PARTITION BY PDE.PostLifeCycleStatus ORDER BY PDE.PostScore DESC) AS PostScoreRankByStatus,
    AVG(PDE.PostScore) OVER (PARTITION BY (EXTRACT(YEAR FROM PDE.PostCreationDate))) AS AvgPostScoreForYear,
    SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) OVER (PARTITION BY UCS.UserId) AS UserTotalClosedPosts, -- Count of closed posts for the user
    EXTRACT(EPOCH FROM (PDE.NextHistoryEventDate - PDE.PrevHistoryEventDate)) / 86400.0 AS DaysBetweenPostHistoryEvents, -- Time diff in days
    COALESCE(TTS.AvgScoreForTag, 0.0) AS MainTagAvgScore,
    COALESCE(TTS.QuestionCountForTag, 0) AS MainTagQuestionCount,
    (SELECT COUNT(DISTINCT B.Name) FROM Badges B WHERE B.UserId = UCS.UserId AND B.Class = 1) AS GoldBadgesCount,
    FEA.TotalEdits AS EditorContributionCount -- From FrequentEditorActivity CTE
FROM UserComprehensiveStats UCS
INNER JOIN PostDetailsExtended PDE ON UCS.UserId = PDE.OwnerUserId
LEFT JOIN PostHistory PH ON PDE.PostId = PH.PostId AND PH.UserId = UCS.UserId -- To count history events for user's own posts
LEFT JOIN FrequentEditorActivity FEA ON UCS.UserId = FEA.UserId
LEFT JOIN LATERAL ( -- Lateral join to get top tag info for each post
    SELECT TQS.AvgScoreForTag, TQS.QuestionCountForTag
    FROM unnest(string_to_array(REPLACE(REPLACE(PDE.Tags, '<', ''), '>', ','), ',')) AS unnest_tag
    JOIN TopTagsByScore TQS ON TQS.TagName = TRIM(unnest_tag)
    WHERE TRIM(unnest_tag) IS NOT NULL AND TRIM(unnest_tag) != ''
    ORDER BY TQS.AvgScoreForTag DESC, TQS.QuestionCountForTag DESC
    LIMIT 1
) TTS ON TRUE
WHERE
    UCS.Reputation >= 10000
    AND UCS.TotalQuestionsOwned > 5
    AND UCS.TotalAnswersOwned > 10
    AND PDE.PostScore > 50
    AND PDE.PostCreationDate >= '2022-01-01'
    AND PDE.PostLifeCycleStatus IN ('AcceptedAnswer', 'Closed')
    AND PDE.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = PDE.PostTypeId AND CreationDate >= '2022-01-01') -- Subquery in WHERE
    AND (
        PDE.Title ILIKE '%performance%' OR
        PDE.Title ILIKE '%optimization%' OR
        PDE.Tags ILIKE '%<sql>%' OR
        PDE.Tags ILIKE '%<database>%'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM PostLinks PL
        WHERE PL.PostId = PDE.PostId
          AND PL.LinkTypeId = 3 -- Exclude posts that are duplicates
          AND PL.CreationDate >= PDE.PostCreationDate - INTERVAL '1 day'
    )
GROUP BY
    UCS.UserId, UCS.DisplayName, UCS.Reputation, UCS.UserCreationDate, UCS.TotalPostsOwned, UCS.TotalQuestionsOwned,
    UCS.TotalAnswersOwned, UCS.AvgOwnedPostScore, UCS.TotalCommentsMade, UCS.TotalUpvotesReceivedOnPosts,
    UCS.TotalDownvotesReceivedOnPosts, PDE.PostId, PDE.PostCreationDate, PDE.PostScore, PDE.ViewCount,
    PDE.Title, PDE.UniqueTagCount, PDE.PostLifeCycleStatus, PDE.Body, UCS.LastAccessDate,
    PDE.LastEditorActualDisplayName, FEA.TotalEdits, TTS.AvgScoreForTag, TTS.QuestionCountForTag,
    PDE.PrevHistoryEventDate, PDE.NextHistoryEventDate
HAVING
    COUNT(DISTINCT PH.PostHistoryTypeId) > 2 -- User has made at least 3 distinct history event types on their posts
    AND SUM(CASE WHEN PDE.PostLifeCycleStatus = 'Closed' THEN 1 ELSE 0 END) <= UCS.TotalPostsOwned / 2 -- Less than half of their considered posts are closed
ORDER BY OverallReputationRank ASC, PostScoreRankByStatus DESC
LIMIT 100

-- Set operator: UNION ALL to combine the above results with a different segment of users/posts for benchmarking.
UNION ALL

-- Second branch of the query, focusing on active answerers in an older timeframe.
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserCreationDate,
    COUNT(DISTINCT P.Id) AS TotalPostsOwned,
    SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
    SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
    COALESCE(AVG(P.Score) FILTER (WHERE P.PostTypeId IN (1,2)), 0) AS AvgOwnedPostScore,
    COUNT(DISTINCT C.Id) AS TotalCommentsMade,
    SUM(CASE WHEN PV.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceivedOnPosts,
    SUM(CASE WHEN PV.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceivedOnPosts,
    P.Id AS PostId,
    P.CreationDate AS PostCreationDate,
    P.Score AS PostScore,
    P.ViewCount AS PostViewCount,
    P.Title AS PostTitle,
    (SELECT COUNT(DISTINCT TRIM(unnest_tag))
         FROM unnest(string_to_array(REPLACE(REPLACE(P.Tags, '<', ''), '>', ','), ',')) AS unnest_tag
         WHERE unnest_tag IS NOT NULL AND TRIM(unnest_tag) != '') AS UniqueTagCount,
    CASE
        WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN P.AcceptedAnswerId IS NOT NULL THEN 'AcceptedAnswer'
        WHEN P.AnswerCount > 0 THEN 'HasAnswers'
        ELSE 'Open'
    END AS PostLifeCycleStatus,
    COALESCE(LEU.DisplayName, U.DisplayName, 'Community') AS FinalEditorDisplayName,
    -- Correlated Subquery 1 (same as above): Max score of accepted answer by this user for another's question.
    (
        SELECT COALESCE(MAX(Ans.Score), 0)
        FROM Posts Q
        JOIN Posts Ans ON Q.AcceptedAnswerId = Ans.Id
        WHERE Q.OwnerUserId <> U.Id
          AND Ans.OwnerUserId = U.Id
          AND Ans.PostTypeId = 2
          AND Q.PostTypeId = 1
    ) AS MaxScoreAcceptedAnswerByOtherUser,
    -- Correlated Subquery 2 (modified): Most recent comment by user on their own post mentioning "bug".
    (
        SELECT C.Text
        FROM Comments C
        WHERE C.PostId = P.Id
          AND C.UserId = U.Id
          AND C.Text ILIKE '%bug%'
        ORDER BY C.CreationDate DESC
        LIMIT 1
    ) AS LatestOwnPostSolutionComment,
    P.Body ILIKE '%error%' OR P.Body ILIKE '%exception%' AS ContainsImgurLink, -- Different predicate
    (EXTRACT(DAY FROM (U.LastAccessDate - U.CreationDate)) * 24 * 60 * 60 +
     EXTRACT(HOUR FROM (U.LastAccessDate - U.CreationDate)) * 60 * 60 +
     EXTRACT(MINUTE FROM (U.LastAccessDate - U.CreationDate)) * 60 +
     EXTRACT(SECOND FROM (U.LastAccessDate - U.CreationDate))) AS UserAccountAgeSeconds,
    UPPER(SUBSTRING(COALESCE(P.Title, 'Untitled Post'), 1, 5)) || '_' || LENGTH(COALESCE(P.Title, '')) AS TitlePrefixLengthHash,
    REPLACE(REPLACE(REPLACE(COALESCE(P.Tags, '<untagged>'), '<', ''), '>', ' '), ',', '|') AS FlattenedTagsPipeSeparated,
    NULLIF(TRIM(P.Body), '') IS NULL AS IsEmptyPostBody,
    RANK() OVER (ORDER BY U.Reputation DESC, COUNT(P.Id) DESC) AS OverallReputationRank,
    DENSE_RANK() OVER (PARTITION BY (CASE WHEN P.PostTypeId = 1 THEN 'Question' ELSE 'Answer' END) ORDER BY P.Score DESC) AS PostScoreRankByStatus,
    AVG(P.Score) OVER (PARTITION BY (EXTRACT(YEAR FROM P.CreationDate))) AS AvgPostScoreForYear,
    SUM(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) OVER (PARTITION BY U.Id) AS UserTotalClosedPosts, -- Counting deletions here
    NULL AS DaysBetweenPostHistoryEvents, -- Not computed in this branch
    NULL AS MainTagAvgScore, -- Not computed in this branch
    NULL AS MainTagQuestionCount, -- Not computed in this branch
    (SELECT COUNT(DISTINCT B.Name) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 2) AS GoldBadgesCount, -- Counting Silver badges here
    (SELECT COUNT(Id) FROM PostHistory PHE WHERE PHE.UserId = U.Id AND PHE.PostHistoryTypeId IN (4,5,6)) AS EditorContributionCount -- Direct subquery for edits
FROM Users U
INNER JOIN Posts P ON U.Id = P.OwnerUserId
LEFT JOIN Comments C ON U.Id = C.UserId
LEFT JOIN Posts PPV ON U.Id = PPV.OwnerUserId
LEFT JOIN Votes PV ON PPV.Id = PV.PostId
LEFT JOIN Users LEU ON P.LastEditorUserId = LEU.Id
LEFT JOIN PostHistory PH ON P.Id = PH.PostId AND PH.UserId = U.Id -- For counting history events
WHERE
    U.Reputation BETWEEN 1000 AND 9999
    AND P.PostTypeId = 2 -- Only answers for this branch
    AND P.CreationDate >= '2019-01-01' AND P.CreationDate < '2022-01-01'
    AND P.Score > 20
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory PH_DEL
        WHERE PH_DEL.PostId = P.Id
          AND PH_DEL.PostHistoryTypeId = 12 -- Exclude deleted answers
    )
    AND P.Body ILIKE '%example%'
GROUP BY
    U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate,
    P.Id, P.CreationDate, P.Score, P.ViewCount, P.Title, P.Body, P.Tags, LEU.DisplayName
HAVING
    COUNT(DISTINCT C.Id) > 1 -- At least 2 comments by the user
    AND SUM(CASE WHEN PV.VoteTypeId = 2 THEN 1 ELSE 0 END) > 50 -- Over 50 upvotes received on their answers
ORDER BY OverallReputationRank DESC, PostScoreRankByStatus DESC
LIMIT 50;