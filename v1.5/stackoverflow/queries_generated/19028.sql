-- {"query": "19028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3003} 
WITH UserBaseMetrics AS (
    -- Aggregates fundamental user statistics, including badge counts and account age.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        AGE(NOW(), U.CreationDate) AS AccountAge,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsAsked,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersGiven,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS CommentsMade,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 AND V.PostId = P.Id THEN 1 ELSE 0 END), 0) AS UpVotesReceivedOnPosts,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 AND V.PostId = P.Id THEN 1 ELSE 0 END), 0) AS DownVotesReceivedOnPosts,
        MIN(B.Date) AS FirstBadgeDate,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    -- Joins Votes to Posts to count votes specific to a user's posts
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostDetailedMetrics AS (
    -- Calculates detailed metrics for questions, including accepted answers, edit history, and tag parsing.
    SELECT
        Q.Id AS QuestionId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Title AS QuestionTitle,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.AnswerCount AS QuestionAnswerCount,
        Q.FavoriteCount,
        Q.OwnerUserId AS QuestionOwnerId,
        U_Q.Reputation AS QuestionOwnerReputation,
        Q.LastActivityDate AS QuestionLastActivityDate,
        COALESCE(AA.Id, -1) AS AcceptedAnswerId,
        AA.Score AS AcceptedAnswerScore,
        AA.OwnerUserId AS AcceptedAnswerOwnerId,
        -- Correlated subquery to get accepted answer owner reputation
        (SELECT U_AA_SUB.Reputation FROM Users U_AA_SUB WHERE U_AA_SUB.Id = AA.OwnerUserId) AS AcceptedAnswerOwnerReputation,
        AGE(AA.CreationDate, Q.CreationDate) AS TimeToAcceptedAnswer,
        COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4,5,6)) AS EditCount, -- Edits to title, body, tags
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.CreationDate END) AS LastEditDate,
        -- Scalar subquery for unique commenters
        (SELECT COUNT(DISTINCT C.UserId) FROM Comments C WHERE C.PostId = Q.Id AND C.UserId IS NOT NULL) AS UniqueCommentersOnQuestion,
        -- String manipulation to extract the first tag
        SUBSTRING(Q.Tags FROM 2 FOR COALESCE(NULLIF(STRPOS(Q.Tags, '><'), 0), LENGTH(Q.Tags)+1) - 2) AS FirstTag,
        -- Window function to rank questions by score for each user
        DENSE_RANK() OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.Score DESC, Q.CreationDate DESC) AS UserQuestionRankByScore,
        LAG(Q.CreationDate, 1, '1970-01-01'::timestamp) OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.CreationDate) AS PreviousQuestionCreationDate
    FROM
        Posts Q
    INNER JOIN Users U_Q ON Q.OwnerUserId = U_Q.Id
    LEFT JOIN Posts AA ON Q.AcceptedAnswerId = AA.Id AND AA.PostTypeId = 2 -- Accepted Answer
    LEFT JOIN PostHistory PH ON Q.Id = PH.PostId
    WHERE
        Q.PostTypeId = 1 -- Only Questions
    GROUP BY
        Q.Id, Q.CreationDate, Q.Title, Q.Score, Q.ViewCount, Q.AnswerCount, Q.FavoriteCount, Q.OwnerUserId, U_Q.Reputation, Q.LastActivityDate,
        AA.Id, AA.Score, AA.OwnerUserId, AA.CreationDate
),
TagEngagementSnapshot AS (
    -- Analyzes tag popularity and associated wiki content length. Uses UNNEST for tag parsing.
    SELECT
        T.Id AS TagId,
        T.TagName,
        T.Count AS TagUseCount,
        T.IsModeratorOnly,
        COALESCE(AVG(TaggedPosts.Score), 0) AS AvgPostScoreForTag,
        COALESCE(SUM(TaggedPosts.ViewCount), 0) AS TotalViewCountForTag,
        COUNT(DISTINCT TaggedPosts.OwnerUserId) AS UniqueOwnersForTag,
        LENGTH(PW.Body) AS TagWikiLength,
        LENGTH(PE.Body) AS TagExcerptLength,
        -- Window function to divide tags into deciles by popularity
        NTILE(10) OVER (ORDER BY T.Count DESC) AS TagPopularityDecile
    FROM
        Tags T
    LEFT JOIN (
        -- Subquery to unnest tags from posts for joining
        SELECT
            P.Id,
            P.Score,
            P.ViewCount,
            P.OwnerUserId,
            UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><')) AS ParsedTag
        FROM Posts P
        WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    ) AS TaggedPosts ON TaggedPosts.ParsedTag = T.TagName
    LEFT JOIN Posts PW ON T.WikiPostId = PW.Id AND PW.PostTypeId = 5 -- TagWiki
    LEFT JOIN Posts PE ON T.ExcerptPostId = PE.Id AND PE.PostTypeId = 4 -- TagWikiExcerpt
    GROUP BY
        T.Id, T.TagName, T.Count, T.IsModeratorOnly, PW.Body, PE.Body
),
PostClosingAnalysis AS (
    -- Identifies closed posts, their reasons, and potential reopen dates.
    SELECT
        PH.PostId,
        CR.Name AS CloseReasonName,
        PH.CreationDate AS CloseDate,
        P.Score AS PostScoreAtClose,
        P.ViewCount AS PostViewCountAtClose,
        -- Correlated subquery to find the latest reopen date after a close event
        (SELECT MAX(PH_reopen.CreationDate)
         FROM PostHistory PH_reopen
         WHERE PH_reopen.PostId = PH.PostId AND PH_reopen.PostHistoryTypeId = 11 AND PH_reopen.CreationDate > PH.CreationDate) AS ReopenDate
    FROM
        PostHistory PH
    INNER JOIN Posts P ON PH.PostId = P.Id
    LEFT JOIN CloseReasonTypes CR ON
        -- Parse CloseReasonId from Comment field
        (PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL AND CR.Id = CAST(PH.Comment AS SMALLINT))
    WHERE
        PH.PostHistoryTypeId = 10 -- Post Closed event
)
-- Main query to combine insights from various CTEs
SELECT
    UBM.UserId,
    UBM.DisplayName,
    UBM.Reputation,
    UBM.AccountAge,
    UBM.QuestionsAsked,
    UBM.AnswersGiven,
    UBM.CommentsMade,
    UBM.TotalPostScore,
    UBM.GoldBadges,
    UBM.SilverBadges,
    UBM.BronzeBadges,
    PDM.QuestionId AS TopQuestionId,
    PDM.QuestionTitle AS TopQuestionTitle,
    PDM.QuestionScore AS TopQuestionScore,
    PDM.QuestionViewCount AS TopQuestionViewCount,
    PDM.FirstTag AS TopQuestionFirstTag,
    TES.TagName AS TopQuestionFirstTagNameDetails,
    TES.AvgPostScoreForTag AS TopQuestionTagAvgScore,
    TES.TagPopularityDecile AS TopQuestionTagPopularityDecile,
    COALESCE(PCA.CloseReasonName, 'N/A') AS LastClosedQuestionReason,
    AGE(COALESCE(PCA.ReopenDate, NOW()), PCA.CloseDate) AS TimeToReopenIfClosed, -- Calculated only if ReopenDate exists
    -- Window function: Average question score by user
    AVG(PDM.QuestionScore) OVER (PARTITION BY UBM.UserId) AS AvgQuestionScoreByUser,
    -- Window function: Count of accepted answers by user
    SUM(CASE WHEN PDM.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) OVER (PARTITION BY UBM.UserId) AS AcceptedAnswerCountByUser,
    -- Count of 'high impact' questions (arbitrary criteria)
    COUNT(PDM.QuestionId) FILTER (WHERE PDM.QuestionViewCount > 5000 AND PDM.QuestionScore > 10) AS HighImpactQuestions,
    -- String expression: Masked display name
    SUBSTRING(UBM.DisplayName, 1, 3) || '***' || SUBSTRING(UBM.DisplayName, LENGTH(UBM.DisplayName)-2, 3) AS MaskedDisplayName,
    -- String expression: Formatted location, handling NULLs
    COALESCE(UPPER(SUBSTRING(U.Location, 1, 1)) || LOWER(SUBSTRING(U.Location, 2)), 'Unknown') AS FormattedLocation,
    -- Window function: Reputation of the user with the next higher reputation
    LAG(UBM.Reputation, 1, 0) OVER (ORDER BY UBM.Reputation DESC) AS PreviousHigherReputation,
    -- Scalar subquery: Count of favorites on the user's top question
    (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = PDM.QuestionId AND V.VoteTypeId = 5) AS FavoriteCountOnTopQuestion
FROM
    UserBaseMetrics UBM
INNER JOIN Users U ON UBM.UserId = U.Id
LEFT JOIN PostDetailedMetrics PDM ON UBM.UserId = PDM.QuestionOwnerId AND PDM.UserQuestionRankByScore = 1 -- Join to get the user's highest-scoring question
LEFT JOIN TagEngagementSnapshot TES ON PDM.FirstTag = TES.TagName
LEFT JOIN PostClosingAnalysis PCA ON PDM.QuestionId = PCA.PostId AND PCA.CloseDate = (SELECT MAX(PCA2.CloseDate) FROM PostClosingAnalysis PCA2 WHERE PCA2.PostId = PDM.QuestionId) -- Join to get the most recent close event for the top question
WHERE
    UBM.Reputation > 1000
    AND UBM.QuestionsAsked > 5
    AND UBM.AnswersGiven > 5
    AND UBM.LastAccessDate >= (NOW() - INTERVAL '1 year') -- Active users within the last year
    AND (UBM.DisplayName IS NOT NULL AND UBM.DisplayName LIKE 'A%') -- Display name starts with 'A'
    AND PDM.QuestionId IS NOT NULL -- Ensure the user has a top question
    -- Correlated subquery in WHERE clause: Users who have earned the 'Disciplined' badge
    AND UBM.UserId IN (SELECT B.UserId FROM Badges B WHERE B.Name = 'Disciplined')
GROUP BY
    UBM.UserId, UBM.DisplayName, UBM.Reputation, UBM.AccountAge, UBM.QuestionsAsked, UBM.AnswersGiven, UBM.CommentsMade,
    UBM.TotalPostScore, UBM.GoldBadges, UBM.SilverBadges, UBM.BronzeBadges, PDM.QuestionId, PDM.QuestionTitle,
    PDM.QuestionScore, PDM.QuestionViewCount, PDM.FirstTag, TES.TagName, TES.AvgPostScoreForTag, TES.TagPopularityDecile,
    PCA.CloseReasonName, PCA.CloseDate, PCA.ReopenDate, U.Location
HAVING
    -- At least one question with a score greater than 100
    COUNT(PDM.QuestionId) FILTER (WHERE PDM.QuestionScore > 100) >= 1
ORDER BY
    UBM.Reputation DESC, UBM.LastAccessDate DESC
LIMIT 500;