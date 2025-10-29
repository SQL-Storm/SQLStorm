-- {"query": "1887.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3027} 

WITH UserStats AS (
    -- Aggregated user statistics, including reputation, tenure, post counts, and last badge date.
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN V.VoteTypeId = 8 THEN V.BountyAmount ELSE 0 END) AS TotalBountyGiven,
        MAX(B.Date) AS LastBadgeAwardDate,
        -- Calculate user tenure in days, handling potential division by zero for new users.
        COALESCE(EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (60.0 * 60 * 24), 0) AS UserTenureDays
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Votes AS V ON U.Id = V.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostDetails AS (
    -- Detailed post metadata for questions, including accepted answer score, average answer score, edit counts, and top comment.
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.Body AS QuestionBody,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.AnswerCount AS QuestionAnswerCount,
        Q.CommentCount AS QuestionCommentCount,
        Q.FavoriteCount,
        Q.Tags AS QuestionTags,
        Q.ClosedDate,
        -- Correlated subquery to get the accepted answer's score.
        (SELECT A.Score FROM Posts AS A WHERE A.Id = Q.AcceptedAnswerId) AS AcceptedAnswerScore,
        -- Correlated subquery to calculate the average score of all answers for this question.
        (SELECT AVG(A_ALL.Score)
         FROM Posts AS A_ALL
         WHERE A_ALL.ParentId = Q.Id AND A_ALL.PostTypeId = 2) AS AverageAnswerScore,
        -- Count distinct users who edited the post from PostHistory.
        COUNT(DISTINCT PH.UserId) AS DistinctEditorCount,
        -- Sum of body edit history entries.
        SUM(CASE WHEN PH.PostHistoryTypeId IN (5, 8) THEN 1 ELSE 0 END) AS BodyEditCount,
        -- Extract the first tag from the tags string, handling potential empty or malformed tags.
        SUBSTRING(Q.Tags, 2, POSITION('>' IN Q.Tags) - 2) AS FirstTag,
        -- Get the text of the highest-scoring comment for the question (correlated subquery).
        COALESCE((
            SELECT T_C.Text
            FROM Comments AS T_C
            WHERE T_C.PostId = Q.Id
            ORDER BY T_C.Score DESC, T_C.CreationDate DESC
            LIMIT 1
        ), 'No top comment found') AS TopCommentText
    FROM Posts AS Q
    LEFT JOIN PostHistory AS PH ON Q.Id = PH.PostId
    WHERE Q.PostTypeId = 1 -- Only consider questions
    GROUP BY
        Q.Id, Q.Title, Q.Body, Q.CreationDate, Q.Score, Q.ViewCount, Q.OwnerUserId,
        Q.AnswerCount, Q.CommentCount, Q.FavoriteCount, Q.Tags, Q.ClosedDate, Q.AcceptedAnswerId
),
TagPerformance AS (
    -- Aggregate performance metrics per tag, including total posts, score, and view count.
    SELECT
        T.TagName,
        COUNT(DISTINCT P.Id) AS TotalPostsTagged,
        SUM(P.Score) AS TotalTagScore,
        AVG(P.ViewCount) AS AvgTagViewCount,
        MAX(P.CreationDate) AS LatestPostWithTag,
        MAX(CASE WHEN P.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS HasClosedQuestions
    FROM Tags AS T
    JOIN Posts AS P ON P.Tags LIKE '%' || '<' || T.TagName || '>' || '%'
    GROUP BY T.TagName
),
UserPostTagAggregatedBase AS (
    -- Base aggregation combining user, post, and tag details, filtered for relevant questions.
    SELECT
        US.UserId,
        US.Reputation,
        US.TotalQuestionsOwned,
        US.TotalAnswersOwned,
        US.UserTenureDays,
        PD.QuestionId,
        PD.QuestionTitle,
        PD.QuestionScore,
        PD.QuestionViewCount,
        PD.AcceptedAnswerScore,
        PD.AverageAnswerScore,
        PD.FirstTag,
        PD.QuestionCreationDate,
        PD.ClosedDate,
        PD.FavoriteCount
    FROM UserStats AS US
    JOIN PostDetails AS PD ON US.UserId = PD.QuestionOwnerId
    WHERE US.TotalQuestionsOwned > 0 AND PD.QuestionScore >= 0
),
FinalData AS (
    -- Final combined and enriched dataset before segmentation with UNION ALL.
    SELECT
        UPTA.UserId,
        UPTA.Reputation,
        UPTA.UserTenureDays,
        UPTA.QuestionId,
        UPTA.QuestionTitle,
        UPTA.QuestionScore,
        UPTA.QuestionViewCount,
        UPTA.AcceptedAnswerScore,
        UPTA.AverageAnswerScore,
        UPTA.FirstTag,
        TP_Main.TagName AS MainTagName,
        TP_Main.TotalPostsTagged AS TaggedPostsCount,
        TP_Main.TotalTagScore AS TagAccumulatedScore,
        TP_Main.AvgTagViewCount AS TagAvgViews,
        PH_Latest.CreationDate AS LastActivityDateForQuestion,
        -- COALESCE to provide a fallback if the last editor's display name is NULL.
        COALESCE(U_LatestEditor.DisplayName, UPTA.UserId::text) AS LastEditorNameOrId,
        -- Window function: Rank questions within their primary tag by score and view count.
        RANK() OVER (PARTITION BY UPTA.FirstTag ORDER BY UPTA.QuestionScore DESC, UPTA.QuestionViewCount DESC) AS RankWithinTag,
        -- Window function: Divide users into 5 reputation quintiles.
        NTILE(5) OVER (ORDER BY UPTA.Reputation DESC) AS ReputationQuintile,
        -- Complex calculation: A weighted impact score for questions, normalizing by user tenure.
        (UPTA.QuestionScore * 0.5 + COALESCE(UPTA.AcceptedAnswerScore, 0) * 0.3 + UPTA.QuestionViewCount * 0.001) /
        (CASE WHEN UPTA.UserTenureDays = 0 THEN 1 ELSE UPTA.UserTenureDays END * 0.1 + 1) AS QuestionImpactScore,
        -- Conditional string expression for topic categorization based on title keywords.
        CASE
            WHEN LOWER(UPTA.QuestionTitle) LIKE '%sql%' OR LOWER(UPTA.QuestionTitle) LIKE '%database%' THEN 'DB-Related'
            WHEN LOWER(UPTA.QuestionTitle) LIKE '%python%' OR LOWER(UPTA.QuestionTitle) LIKE '%java%' THEN 'Programming-Lang'
            ELSE 'Other-Topic'
        END AS TopicCategory,
        -- Correlated subquery to find the most upvoted comment text by the question owner on their own question.
        (SELECT C_MaxVote.Text
         FROM Comments AS C_MaxVote
         WHERE C_MaxVote.PostId = UPTA.QuestionId AND C_MaxVote.UserId = UPTA.UserId
         ORDER BY C_MaxVote.Score DESC, C_MaxVote.CreationDate DESC
         LIMIT 1) AS MostUpvotedCommentByOwner,
        -- EXISTS subquery to check if the question owner has a tag-specific badge for the question's primary tag.
        EXISTS (
            SELECT 1
            FROM Badges AS B
            WHERE B.UserId = UPTA.UserId AND B.TagBased = TRUE
                  AND B.Name = UPTA.FirstTag
        ) AS HasTagSpecificBadge,
        -- Subquery to count how many high-view-count posts this question is a duplicate of.
        (
            SELECT COUNT(PL.PostId)
            FROM PostLinks PL
            JOIN Posts RelatedP ON PL.RelatedPostId = RelatedP.Id
            WHERE PL.PostId = UPTA.QuestionId
              AND PL.LinkTypeId = 3 -- Duplicate link type
              AND RelatedP.ViewCount > 5000
        ) AS DuplicateOfHighViewCountPostCount,
        UPTA.QuestionCreationDate,
        UPTA.ClosedDate,
        UPTA.FavoriteCount
    FROM UserPostTagAggregatedBase AS UPTA
    JOIN TagPerformance AS TP_Main ON UPTA.FirstTag = TP_Main.TagName
    LEFT JOIN (
        -- Subquery to find the latest activity date (edit, close, reopen) for each post.
        SELECT PostId, MAX(CreationDate) AS CreationDate
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4, 5, 6, 10, 11) -- Edit Title, Body, Tags, Post Closed, Post Reopened
        GROUP BY PostId
    ) AS PH_Latest ON UPTA.QuestionId = PH_Latest.PostId
    LEFT JOIN Posts AS LatestEditorPost ON UPTA.QuestionId = LatestEditorPost.Id -- For LastEditorUserId
    LEFT JOIN Users AS U_LatestEditor ON LatestEditorPost.LastEditorUserId = U_LatestEditor.Id
    WHERE
        UPTA.QuestionViewCount > 100
        AND UPTA.Reputation > 100
        AND UPTA.QuestionScore > 0
        AND UPTA.QuestionTitle IS NOT NULL AND LENGTH(TRIM(UPTA.QuestionTitle)) > 5
        AND UPTA.FirstTag IS NOT NULL AND LENGTH(TRIM(UPTA.FirstTag)) > 0
)
-- First segment: High Impact Recent Questions by High Reputation Users
SELECT
    UserId,
    Reputation,
    UserTenureDays,
    QuestionId,
    QuestionTitle,
    QuestionScore,
    QuestionViewCount,
    AcceptedAnswerScore,
    AverageAnswerScore,
    FirstTag,
    MainTagName,
    TaggedPostsCount,
    TagAccumulatedScore,
    TagAvgViews,
    LastActivityDateForQuestion,
    LastEditorNameOrId,
    RankWithinTag,
    ReputationQuintile,
    QuestionImpactScore,
    TopicCategory,
    MostUpvotedCommentByOwner,
    HasTagSpecificBadge,
    DuplicateOfHighViewCountPostCount,
    'High Impact Recent Questions' AS Segment
FROM FinalData
WHERE
    QuestionCreationDate >= (NOW() - INTERVAL '3 year')
    AND QuestionImpactScore > 100
    AND ReputationQuintile <= 2 -- Top 2 quintiles of reputation
    AND QuestionId % 10 < 5 -- Modulo for data splitting across UNION ALL branches
UNION ALL
-- Second segment: Popular Older Questions with Edits and Specific Favorite Count
SELECT
    UserId,
    Reputation,
    UserTenureDays,
    QuestionId,
    QuestionTitle,
    QuestionScore,
    QuestionViewCount,
    AcceptedAnswerScore,
    AverageAnswerScore,
    FirstTag,
    MainTagName,
    TaggedPostsCount,
    TagAccumulatedScore,
    TagAvgViews,
    LastActivityDateForQuestion,
    LastEditorNameOrId,
    RankWithinTag,
    ReputationQuintile,
    QuestionImpactScore,
    TopicCategory,
    MostUpvotedCommentByOwner,
    HasTagSpecificBadge,
    DuplicateOfHighViewCountPostCount,
    'Popular Older Questions with Edits' AS Segment
FROM FinalData
WHERE
    QuestionCreationDate < (NOW() - INTERVAL '5 year')
    AND QuestionViewCount > 5000
    AND TagAccumulatedScore > 1000
    AND LastActivityDateForQuestion IS NOT NULL -- Implies it has been edited or closed/reopened
    AND (FavoriteCount IS NULL OR FavoriteCount < 100) -- Example of NULL logic and range for differentiation
    AND QuestionId % 10 >= 5 -- Complementary modulo for data splitting
ORDER BY
    Reputation DESC, QuestionImpactScore DESC
LIMIT 200;
