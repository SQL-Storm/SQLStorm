-- {"query": "1857.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3460} 

WITH UserInteractionSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.WebsiteUrl,
        U.Location,
        U.AboutMe,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN PH_edit.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS PostEditsMadeBySelf,
        SUM(CASE WHEN V_cast.VoteTypeId IN (2, 5) THEN 1 ELSE 0 END) AS UpVotesCastBySelf, -- UpMod, Favorite
        SUM(CASE WHEN V_cast.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCastBySelf,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViewsOwned,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScoreOwned,
        MAX(P.CreationDate) AS LatestPostDate,
        MIN(P.CreationDate) AS EarliestPostDate,
        MAX(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        COUNT(B.Id) AS TotalBadges,
        AGE(NOW(), U.CreationDate) AS AccountAge
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V_cast ON U.Id = V_cast.UserId
    LEFT JOIN PostHistory PH_edit ON U.Id = PH_edit.UserId AND PH_edit.PostId = P.Id AND PH_edit.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.WebsiteUrl, U.Location, U.AboutMe, U.Views, U.UpVotes, U.DownVotes
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate,
        P.Score,
        P.ViewCount,
        COALESCE(P.AnswerCount, 0) AS AnswerCount,
        COALESCE(P.CommentCount, 0) AS CommentCount,
        COALESCE(P.FavoriteCount, 0) AS FavoriteCount,
        P.ClosedDate,
        P.LastEditDate,
        P.LastActivityDate,
        COALESCE(P.Title, SUBSTRING(P.Body, 1, 75) || '...') AS DisplayTitleSnippet,
        TRIM(BOTH '>' FROM TRIM(BOTH '<' FROM P.Tags)) AS RawTags,
        COALESCE(ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'), 1), 0) AS TagCount,
        -- Correlated subquery for Accepted Answer PostId (if exists for a question)
        (SELECT PA.Id FROM Posts PA WHERE PA.Id = P.AcceptedAnswerId AND P.PostTypeId = 1 LIMIT 1) AS AcceptedAnswerPostId,
        -- Correlated subquery for distinct users who commented, excluding owner
        (SELECT COUNT(DISTINCT C_post.UserId) FROM Comments C_post WHERE C_post.PostId = P.Id AND C_post.UserId IS NOT NULL AND C_post.UserId != P.OwnerUserId) AS UniqueCommentersExcludingOwner,
        -- Complex CASE expression for close reason category, handling NULLs and invalid string casts
        CASE
            WHEN PH_closed.PostHistoryTypeId = 10 AND PH_closed.Comment ~ '^[0-9]+$' THEN
                CASE CAST(PH_closed.Comment AS smallint)
                    WHEN 1 THEN 'Duplicate_Old'
                    WHEN 2 THEN 'OffTopic_Old'
                    WHEN 3 THEN 'Subjective_Old'
                    WHEN 4 THEN 'NotARealQuestion_Old'
                    WHEN 101 THEN 'Duplicate_New'
                    WHEN 102 THEN 'OffTopic_New'
                    WHEN 103 THEN 'NeedsDetailsOrClarity_New'
                    WHEN 104 THEN 'NeedsMoreFocus_New'
                    WHEN 105 THEN 'OpinionBased_New'
                    ELSE 'Other_Closed_Specific'
                END
            WHEN P.ClosedDate IS NOT NULL THEN 'Generic_Closed_ReasonUnknown'
            ELSE 'NotClosed'
        END AS CloseReasonCategory,
        COALESCE(CR.Name, 'N/A') AS CloseReasonTypeName,
        SUM(CASE WHEN V_post.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN V_post.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN V_post.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesReceived
    FROM Posts P
    LEFT JOIN PostHistory PH_closed ON P.Id = PH_closed.PostId AND PH_closed.PostHistoryTypeId = 10 AND P.ClosedDate IS NOT NULL
    LEFT JOIN CloseReasonTypes CR ON PH_closed.PostHistoryTypeId = 10 AND PH_closed.Comment ~ '^[0-9]+$' AND CAST(PH_closed.Comment AS smallint) = CR.Id
    LEFT JOIN Votes V_post ON P.Id = V_post.PostId
    WHERE P.PostTypeId IN (1, 2) -- Only Questions (1) and Answers (2)
      AND P.CreationDate >= NOW() - INTERVAL '5 years'
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.LastEditDate, P.LastActivityDate, P.Title, P.Body, P.Tags, PH_closed.PostHistoryTypeId, PH_closed.Comment, CR.Name
),
TagPerformanceMetrics AS (
    SELECT
        T.Id AS TagId,
        T.TagName,
        T.Count AS TagUseCount,
        COUNT(DISTINCT P.Id) AS QuestionsTagged,
        SUM(PQM.Score) AS TotalScoreFromTaggedQuestions,
        SUM(PQM.ViewCount) AS TotalViewsFromTaggedQuestions,
        AVG(PQM.Score) AS AvgScorePerQuestion,
        AVG(PQM.ViewCount) AS AvgViewsPerQuestion,
        -- Correlated subquery to find the top user for this tag based on question score
        (
            SELECT U_tag.DisplayName
            FROM Users U_tag
            INNER JOIN Posts P_tag_user ON U_tag.Id = P_tag_user.OwnerUserId
            WHERE P_tag_user.PostTypeId = 1
              AND P_tag_user.Tags IS NOT NULL
              AND P_tag_user.Tags LIKE '%' || '<' || T.TagName || '>' || '%'
            GROUP BY U_tag.Id, U_tag.DisplayName
            ORDER BY SUM(P_tag_user.Score) DESC, COUNT(P_tag_user.Id) DESC
            LIMIT 1
        ) AS TopUserForTagByScore,
        COUNT(DISTINCT PL.Id) AS TotalLinksInvolvingPostsWithTag,
        COUNT(DISTINCT CASE WHEN PQM.CloseReasonCategory LIKE '%Closed%' THEN PQM.PostId ELSE NULL END) AS ClosedQuestionsWithTag,
        SUM(PQM.CommentCount) AS TotalCommentsOnTaggedQuestions
    FROM Tags T
    INNER JOIN Posts P ON P.PostTypeId = 1 AND P.Tags IS NOT NULL AND P.Tags LIKE '%' || '<' || T.TagName || '>' || '%'
    LEFT JOIN PostEngagementMetrics PQM ON P.Id = PQM.PostId
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId OR P.Id = PL.RelatedPostId
    WHERE P.CreationDate >= NOW() - INTERVAL '3 years'
    GROUP BY T.Id, T.TagName, T.Count
)
SELECT
    'High_Reputation_ActiveUser_Performance' AS AnalysisCategory,
    UIS.UserId,
    UIS.DisplayName,
    UIS.Reputation,
    UIS.TotalPostsOwned,
    UIS.QuestionsPosted,
    UIS.AnswersPosted,
    UIS.TotalCommentsMade,
    UIS.TotalPostScoreOwned,
    UIS.TotalPostViewsOwned,
    UIS.LatestPostDate,
    UIS.HasGoldBadge,
    UIS.AccountAge,
    NULL::varchar(50) AS TagName, -- Explicitly cast to avoid type conflicts in UNION
    NULL::integer AS TagUseCount,
    NULL::varchar(40) AS TopUserForTagIdentifier,
    RANK() OVER (ORDER BY UIS.Reputation DESC, UIS.TotalPostScoreOwned DESC, UIS.PostEditsMadeBySelf DESC) AS OverallUserRank,
    NTILE(5) OVER (ORDER BY UIS.TotalCommentsMade DESC) AS CommenterActivityQuintile,
    AVG(PQM.Score) OVER (PARTITION BY UIS.UserId) AS AvgPostScoreByUser,
    SUM(CASE WHEN PQM.CloseReasonCategory != 'NotClosed' THEN 1 ELSE 0 END) OVER (PARTITION BY UIS.UserId) AS TotalClosedPostsByUser,
    ROUND(CAST(SUM(PQM.UpVotesReceived) AS NUMERIC) / NULLIF(SUM(PQM.DownVotesReceived), 0), 2) AS UpToDownVoteRatioByUser,
    COUNT(DISTINCT PQM.PostId) OVER (PARTITION BY UIS.UserId) AS UniquePostsAnalyzedForUser,
    ROW_NUMBER() OVER (PARTITION BY UIS.Reputation / 10000 ORDER BY UIS.TotalPostsOwned DESC) AS RankWithinReputationTier
FROM UserInteractionSummary UIS
LEFT JOIN PostEngagementMetrics PQM ON UIS.UserId = PQM.OwnerUserId
WHERE UIS.Reputation > 5000
  AND UIS.TotalPostsOwned > 20
  AND UIS.LatestPostDate >= NOW() - INTERVAL '6 months'
  AND (UIS.WebsiteUrl IS NOT NULL OR UIS.AboutMe IS NOT NULL) -- At least one personal detail
  AND UIS.HasGoldBadge = 1 -- Only consider users with at least one gold badge
GROUP BY
    UIS.UserId, UIS.DisplayName, UIS.Reputation, UIS.TotalPostsOwned, UIS.QuestionsPosted, UIS.AnswersPosted,
    UIS.TotalCommentsMade, UIS.TotalPostScoreOwned, UIS.TotalPostViewsOwned, UIS.LatestPostDate, UIS.HasGoldBadge,
    UIS.AccountAge, PQM.PostId, PQM.Score, PQM.UpVotesReceived, PQM.DownVotesReceived, PQM.CloseReasonCategory -- Include PQM attributes for window functions
HAVING
    COUNT(DISTINCT PQM.PostId) > 5 -- Ensure user has at least 5 posts captured by PQM
    AND (AVG(PQM.UpVotesReceived) - AVG(PQM.DownVotesReceived)) > 2 -- Net upvotes average on their posts
    AND SUM(LENGTH(COALESCE(U.AboutMe, ''))) > 100 -- Users with substantial 'AboutMe'
UNION ALL
SELECT
    'Top_Performing_Tag_Contributor_Analysis' AS AnalysisCategory,
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    UIS.TotalPostsOwned,
    UIS.QuestionsPosted,
    UIS.AnswersPosted,
    UIS.TotalCommentsMade,
    UIS.TotalPostScoreOwned,
    UIS.TotalPostViewsOwned,
    UIS.LatestPostDate,
    UIS.HasGoldBadge,
    UIS.AccountAge,
    TPM.TagName,
    TPM.TagUseCount,
    TPM.TopUserForTagByScore AS TopUserForTagIdentifier,
    NULL::bigint AS OverallUserRank, -- NULL for fields not applicable to this UNION branch
    NULL::integer AS CommenterActivityQuintile,
    NULL::numeric AS AvgPostScoreByUser,
    NULL::bigint AS TotalClosedPostsByUser,
    ROUND(CAST(SUM(PQM.UpVotesReceived) AS NUMERIC) / NULLIF(SUM(PQM.DownVotesReceived), 0), 2) AS UpToDownVoteRatioByUser,
    COUNT(DISTINCT P.Id) AS UniquePostsAnalyzedForUser,
    DENSE_RANK() OVER (PARTITION BY TPM.TagName ORDER BY SUM(PQM.Score) DESC, U.Reputation DESC) AS RankWithinReputationTier -- Rank within tag based on score
FROM Users U
INNER JOIN UserInteractionSummary UIS ON U.Id = UIS.UserId
INNER JOIN Posts P ON U.Id = P.OwnerUserId AND P.PostTypeId = 1 -- Only questions
INNER JOIN PostEngagementMetrics PQM ON P.Id = PQM.PostId
INNER JOIN TagPerformanceMetrics TPM ON P.Tags IS NOT NULL AND P.Tags LIKE '%' || '<' || TPM.TagName || '>' || '%'
WHERE P.CreationDate >= NOW() - INTERVAL '1 year'
  AND PQM.UpVotesReceived > COALESCE(PQM.DownVotesReceived, 0) * 1.5 -- Posts with significantly more upvotes than downvotes
  AND TPM.TagUseCount > 500 -- Popular tags only
  AND U.Location IS NOT NULL AND U.Location LIKE '%United States%' -- Filter by location
  AND POSITION('data science' IN LOWER(COALESCE(U.AboutMe, ''))) > 0 -- Users interested in data science
GROUP BY
    U.Id, U.DisplayName, U.Reputation, UIS.TotalPostsOwned, UIS.QuestionsPosted, UIS.AnswersPosted,
    UIS.TotalCommentsMade, UIS.TotalPostScoreOwned, UIS.TotalPostViewsOwned, UIS.LatestPostDate,
    UIS.HasGoldBadge, UIS.AccountAge, TPM.TagName, TPM.TagUseCount, TPM.TopUserForTagByScore
HAVING
    COUNT(DISTINCT P.Id) >= 3 -- User has contributed at least 3 high-quality questions to this tag
    AND SUM(PQM.Score) >= 30 -- And accumulated at least 30 score in this tag for this period
    AND SUM(PQM.UniqueCommentersExcludingOwner) > 0 -- At least one unique commenter
ORDER BY AnalysisCategory, OverallUserRank, RankWithinReputationTier, UserId
LIMIT 1000;
