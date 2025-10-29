-- {"query": "1590.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2700} 
WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        MAX(COALESCE(P.LastActivityDate, C.CreationDate, U.LastAccessDate)) AS LatestActivity,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViews,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
    HAVING
        U.Reputation >= 500
        AND COUNT(DISTINCT P.Id) > 0 -- At least one post
),
PostActivityMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate,
        P.LastEditDate,
        P.ClosedDate,
        P.OwnerUserId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        COUNT(V.Id) AS TotalVoteCount, -- Count of votes, not distinct
        DENSE_RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC, P.CreationDate DESC) AS RankByPopularity,
        EXTRACT(EPOCH FROM (NOW() - P.LastActivityDate)) / 3600 AS HoursSinceLastActivity, -- Hours since last activity
        COALESCE(P.AnswerCount, 0) * 1.0 / GREATEST(COALESCE(P.ViewCount, 0), 1) AS AnswerToViewRatio,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS UserPostSeqNum
    FROM Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount,
        P.CreationDate, P.LastActivityDate, P.LastEditDate, P.ClosedDate, P.OwnerUserId
),
TagAnalysis AS (
    SELECT
        unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName,
        Id AS PostId,
        Score
    FROM Posts
    WHERE Tags IS NOT NULL AND Tags != '' AND PostTypeId = 1 -- Only questions for tag analysis
)
, CommonTagStats AS (
    SELECT
        TA.TagName,
        COUNT(TA.PostId) AS TotalTaggedQuestions,
        AVG(TA.Score) AS AvgTagScore,
        SUM(TA.Score) AS SumTagScore
    FROM TagAnalysis TA
    GROUP BY TA.TagName
    HAVING COUNT(TA.PostId) > 50 -- Only consider reasonably common tags
)
-- Main query starts here
SELECT
    Q.Id AS QuestionId,
    Q.Title AS QuestionTitle,
    Q.CreationDate AS QuestionCreationDate,
    Q.Score AS QuestionScore,
    Q.ViewCount AS QuestionViewCount,
    Q.AnswerCount AS QuestionAnswerCount,
    Q.FavoriteCount AS QuestionFavoriteCount,
    Q.ClosedDate,
    UES_Q.DisplayName AS QuestionOwnerDisplayName,
    UES_Q.Reputation AS QuestionOwnerReputation,
    PAM_Q.HoursSinceLastActivity,
    PAM_Q.RankByPopularity AS QuestionPopularityRank,
    PAM_Q.UpVoteCount AS QuestionUpVotes,
    PAM_Q.DownVoteCount AS QuestionDownVotes,
    PAM_Q.AnswerToViewRatio,
    (SELECT COUNT(PH.Id) FROM PostHistory PH WHERE PH.PostId = Q.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS EditCount, -- Correlated Subquery for edit history
    (SELECT COALESCE(CLRT.Name, 'Unknown Reason')
     FROM PostHistory PH_CLOSE
     LEFT JOIN CloseReasonTypes CLRT ON PH_CLOSE.Comment = CAST(CLRT.Id AS VARCHAR)
     WHERE PH_CLOSE.PostId = Q.Id AND PH_CLOSE.PostHistoryTypeId = 10
     ORDER BY PH_CLOSE.CreationDate DESC
     LIMIT 1) AS LastCloseReason, -- Correlated Subquery for latest close reason, with NULL logic
    COALESCE(LEFT(Q.Body, 150) || '...', '[No Body Preview]') AS QuestionBodyPreview, -- String expression & NULL logic
    Q.Tags,
    ARRAY_TO_STRING(
        (SELECT ARRAY_AGG(T.TagName ORDER BY CTS.SumTagScore DESC)
         FROM Tags T
         INNER JOIN CommonTagStats CTS ON T.TagName = CTS.TagName
         WHERE T.TagName = ANY(string_to_array(substring(Q.Tags, 2, length(Q.Tags)-2), '><'))
           AND CTS.TotalTaggedQuestions > (SELECT AVG(CTS2.TotalTaggedQuestions) FROM CommonTagStats CTS2) -- Joining CTE with subquery for complex condition
         ), ', ') AS PopularHighImpactTags,
    AA.Id AS AcceptedAnswerId,
    AA.Score AS AcceptedAnswerScore,
    UES_AA.DisplayName AS AcceptedAnswerOwnerDisplayName,
    UES_AA.Reputation AS AcceptedAnswerOwnerReputation,
    CASE
        WHEN Q.AcceptedAnswerId IS NOT NULL AND PAM_AA.PostScore > (Q.Score * 0.75) THEN 'High-Impact Accepted Answer'
        WHEN Q.AcceptedAnswerId IS NOT NULL AND PAM_AA.PostScore > 0 THEN 'Standard Accepted Answer'
        WHEN Q.AcceptedAnswerId IS NOT NULL THEN 'Low-Score Accepted Answer'
        ELSE 'No Accepted Answer'
    END AS AcceptedAnswerImpactCategory, -- Complicated predicate/expression
    PL_Linked.RelatedPostId AS LinkedQuestionId,
    (SELECT QP.Title FROM Posts QP WHERE QP.Id = PL_Linked.RelatedPostId) AS LinkedQuestionTitle,
    PL_Duplicate.RelatedPostId AS DuplicateQuestionId,
    (SELECT DUP.Title FROM Posts DUP WHERE DUP.Id = PL_Duplicate.RelatedPostId) AS DuplicateQuestionTitle,
    UES_Q.TotalPosts AS OwnerTotalPosts,
    UES_Q.QuestionsAsked AS OwnerQuestionsAsked,
    UES_Q.AnswersProvided AS OwnerAnswersProvided,
    (SELECT AVG(CAST(V.VoteTypeId = 2 AS NUMERIC)) FROM Votes V WHERE V.PostId = Q.Id AND V.VoteTypeId IN (2,3)) AS UpvoteRatioForQuestion, -- Calculation
    -- Window functions used directly in main query
    SUM(Q.Score) OVER (PARTITION BY UES_Q.UserId ORDER BY Q.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeOwnerScore, -- Cumulative sum
    LAG(Q.CreationDate, 1, UES_Q.UserCreationDate) OVER (PARTITION BY UES_Q.UserId ORDER BY Q.CreationDate) AS PreviousQuestionDate, -- Lag function with default value
    COUNT(DISTINCT C.Id) AS RecentCommentCount,
    MAX(C.CreationDate) AS LatestCommentDate,
    MAX(B.Name) FILTER (WHERE B.Class = 1) AS GoldBadgeName, -- Filter clause for aggregate
    MAX(B.Date) FILTER (WHERE B.Class = 1) AS GoldBadgeDate,
    NULLIF(MAX(B.Name) FILTER (WHERE B.Class = 2), MAX(B.Name) FILTER (WHERE B.Class = 1)) AS SilverBadgeIfNotGold -- NULLIF and aggregate filters
FROM Posts Q
INNER JOIN UserEngagementSummary UES_Q ON Q.OwnerUserId = UES_Q.UserId
INNER JOIN PostActivityMetrics PAM_Q ON Q.Id = PAM_Q.PostId AND Q.PostTypeId = 1 -- Only questions
LEFT JOIN Posts AA ON Q.AcceptedAnswerId = AA.Id AND AA.PostTypeId = 2 -- Accepted Answer (Outer Join)
LEFT JOIN UserEngagementSummary UES_AA ON AA.OwnerUserId = UES_AA.UserId
LEFT JOIN PostActivityMetrics PAM_AA ON AA.Id = PAM_AA.PostId -- Metrics for Accepted Answer
LEFT JOIN PostLinks PL_Linked ON Q.Id = PL_Linked.PostId AND PL_Linked.LinkTypeId = 1 -- Linked Posts (Outer Join)
LEFT JOIN PostLinks PL_Duplicate ON Q.Id = PL_Duplicate.PostId AND PL_Duplicate.LinkTypeId = 3 -- Duplicate Posts (Outer Join)
LEFT JOIN Comments C ON Q.Id = C.PostId AND C.CreationDate > NOW() - INTERVAL '60 days' -- Recent comments (Outer Join)
LEFT JOIN Badges B ON UES_Q.UserId = B.UserId AND B.Date > UES_Q.LatestActivity - INTERVAL '1 year' -- Recent badges for the owner
WHERE
    Q.PostTypeId = 1 -- Ensure it's a question
    AND Q.CreationDate >= NOW() - INTERVAL '3 years' -- Posts within last 3 years
    AND PAM_Q.PostScore > 15 -- Only questions with reasonable score
    AND PAM_Q.HoursSinceLastActivity < 1440 -- Active in the last 60 days
    AND UES_Q.TotalPosts > 10 -- Owner has at least 10 posts
    AND (Q.Tags LIKE '%<sql>%' OR Q.Tags LIKE '%<postgresql>%' OR Q.Tags LIKE '%<database>%') -- Specific tag interest (string matching)
    AND Q.ClosedDate IS NULL -- Not closed
    AND (LOWER(Q.Title) LIKE '%performance%' OR LOWER(Q.Body) LIKE '%optimize%') -- Text search in title/body
GROUP BY
    Q.Id, Q.Title, Q.CreationDate, Q.Score, Q.ViewCount, Q.AnswerCount, Q.FavoriteCount, Q.ClosedDate, Q.Body, Q.Tags,
    UES_Q.UserId, UES_Q.DisplayName, UES_Q.Reputation, UES_Q.TotalPosts, UES_Q.QuestionsAsked, UES_Q.AnswersProvided, UES_Q.UserCreationDate, UES_Q.LatestActivity,
    PAM_Q.HoursSinceLastActivity, PAM_Q.RankByPopularity, PAM_Q.UpVoteCount, PAM_Q.DownVoteCount, PAM_Q.AnswerToViewRatio,
    AA.Id, AA.Score, UES_AA.DisplayName, UES_AA.Reputation, PAM_AA.PostScore,
    PL_Linked.RelatedPostId, PL_Duplicate.RelatedPostId
HAVING COUNT(DISTINCT C.Id) > 0 OR Q.FavoriteCount > 10 OR MAX(B.Name) IS NOT NULL -- Must have recent comments, favorites, or owner has recent badges
ORDER BY QuestionScore DESC, QuestionViewCount DESC, QuestionCreationDate DESC
LIMIT 200;