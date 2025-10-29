-- {"query": "1384.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3381} 

WITH UserInfluence AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsCreated,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersCreated,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScoreReceived,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        NTILE(5) OVER (ORDER BY U.Reputation DESC) AS ReputationQuintile,
        -- Calculate an 'influence score' combining reputation, post count, and badge count
        (U.Reputation * 0.5) + (COUNT(DISTINCT P.Id) * 0.2) + (COUNT(DISTINCT B.Id) * 0.3) AS InfluenceScore
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
    HAVING
        COUNT(DISTINCT P.Id) > 2 -- Filter for users with at least some posts
),
-- CTE 2: Detailed Metrics for Questions and Answers
PostDetailedMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.ParentId, -- Crucial for answers to link to questions
        P.AcceptedAnswerId, -- Crucial for questions to know their accepted answer
        P.Title AS PostTitle,
        P.Body AS PostBody,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount, -- Only relevant for questions
        COALESCE(P.FavoriteCount, 0) AS FavoriteCount,
        P.LastActivityDate,
        P.ClosedDate,
        P.Tags,
        -- Calculate rough word count for the body, handling NULL
        COALESCE(LENGTH(P.Body) - LENGTH(REPLACE(P.Body, ' ', '')), 0) AS BodyWordCount,
        -- Correlated subquery: Count unique editors for this post
        (SELECT COUNT(DISTINCT PH_edit.UserId)
         FROM PostHistory PH_edit
         WHERE PH_edit.PostId = P.Id
           AND PH_edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
        ) AS UniqueEditorsCount,
        -- Correlated subquery: Get the latest edit date for this post
        (SELECT MAX(PH_latest.CreationDate)
         FROM PostHistory PH_latest
         WHERE PH_latest.PostId = P.Id
           AND PH_latest.PostHistoryTypeId IN (4, 5, 6)
        ) AS LatestEditDate,
        -- Correlated subquery: Calculate average comment score on this post
        (SELECT AVG(C_p.Score)
         FROM Comments C_p
         WHERE C_p.PostId = P.Id
        ) AS AvgCommentScoreOnPost,
        -- Correlated subquery: Count incoming links (where this post is the RelatedPostId with LinkType=1)
        (SELECT COUNT(*) FROM PostLinks PL WHERE PL.RelatedPostId = P.Id AND PL.LinkTypeId = 1) AS IncomingLinksCount,
        -- Window function: Rank posts by score within a user's contributions
        RANK() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC) AS PostScoreRankByUser,
        -- Categorize posts by age using complex date logic
        CASE
            WHEN P.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '1 year') THEN 'Recent'
            WHEN P.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '3 years') THEN 'Medium Age'
            ELSE 'Old'
        END AS PostAgeCategory
    FROM
        Posts P
    WHERE
        P.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
        AND P.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 year') -- Limit data for performance
)
-- Main Query: Combine user influence and post details using UNION ALL
SELECT
    'Question' AS PostType,
    UI.UserId,
    UI.DisplayName,
    UI.Reputation,
    UI.InfluenceScore,
    UI.ReputationQuintile,
    PDM.PostId,
    PDM.PostTitle AS MainContentTitle,
    PDM.PostBody AS MainContentBody,
    PDM.PostCreationDate,
    PDM.PostScore AS MainContentScore,
    PDM.ViewCount AS MainContentViewCount,
    PDM.FavoriteCount AS MainContentFavoriteCount,
    PDM.BodyWordCount,
    PDM.UniqueEditorsCount,
    PDM.LatestEditDate,
    PDM.AvgCommentScoreOnPost,
    PDM.IncomingLinksCount,
    PDM.PostScoreRankByUser,
    PDM.PostAgeCategory,
    PDM.AnswerCount AS RelatedItemCount, -- Question's answer count
    -- Window function: Sum of scores of all answers to this question
    COALESCE(SUM(A_main.Score) OVER (PARTITION BY PDM.PostId), 0) AS RelatedItemScoreSum,
    -- NULL logic: Check if the question has an accepted answer
    MAX(CASE WHEN PDM.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) OVER (PARTITION BY PDM.PostId) AS HasAcceptedAnswer,
    NULL AS IsCurrentPostAcceptedAnswer, -- Questions are not answers
    -- Complicated calculation for combined post quality score for questions
    ROUND(
        (PDM.PostScore * 0.4) +
        (COALESCE(PDM.ViewCount, 0) * 0.01) +
        (PDM.BodyWordCount * 0.005) +
        (PDM.UniqueEditorsCount * 5) +
        (COALESCE(PDM.AvgCommentScoreOnPost, 0) * 2) +
        (PDM.IncomingLinksCount * 10) +
        (COALESCE(SUM(A_main.Score) OVER (PARTITION BY PDM.PostId), 0) * 0.05)
    , 2) AS CombinedPostQualityScore,
    -- String expression: Extract first tag from question, handling NULL
    COALESCE(
        TRIM(SUBSTRING(PDM.Tags FROM POSITION('<' IN PDM.Tags) + 1 FOR POSITION('>' IN PDM.Tags) - POSITION('<' IN PDM.Tags) -1))
        , 'No Tag'
    ) AS FirstTag,
    -- Complex predicate/NULL logic for categorizing question status
    CASE
        WHEN PDM.ClosedDate IS NOT NULL AND PDM.LastActivityDate < (CURRENT_TIMESTAMP - INTERVAL '6 months') THEN 'Stale Closed Question'
        WHEN PDM.AnswerCount = 0 AND PDM.FavoriteCount > 5 THEN 'Unanswered Popular Question'
        WHEN PDM.PostScore >= 50 AND COALESCE(PDM.ViewCount, 0) >= 10000 AND PDM.AcceptedAnswerId IS NOT NULL THEN 'High-Value Solved Question'
        ELSE 'Other Question Type'
    END AS PostStatusCategory
FROM
    UserInfluence UI
INNER JOIN
    PostDetailedMetrics PDM ON UI.UserId = PDM.OwnerUserId
LEFT JOIN
    Posts A_main ON PDM.PostId = A_main.ParentId AND A_main.PostTypeId = 2 -- All answers related to this question
WHERE
    PDM.PostTypeId = 1 -- Only questions
    AND PDM.PostScoreRankByUser <= 5 -- Consider only top N questions per user
    AND PDM.BodyWordCount > 30 -- Questions with substantial content
    AND (PDM.PostTitle LIKE '%SQL%' OR PDM.Tags LIKE '%<database>%' OR LOWER(PDM.PostBody) LIKE '%query%') -- Filter by keywords in title, tags, or body
    AND PDM.AvgCommentScoreOnPost IS DISTINCT FROM -1 -- Exclude questions with very low or negative average comment scores
    AND (PDM.LatestEditDate IS NULL OR PDM.LatestEditDate >= (CURRENT_TIMESTAMP - INTERVAL '2 year')) -- Either never edited or recently active
GROUP BY -- Grouping for SUM(A_main.Score) OVER (PARTITION BY PDM.PostId) and other window aggregates
    UI.UserId, UI.DisplayName, UI.Reputation, UI.InfluenceScore, UI.ReputationQuintile,
    PDM.PostId, PDM.PostTitle, PDM.PostBody, PDM.PostCreationDate, PDM.PostScore, PDM.ViewCount,
    PDM.FavoriteCount, PDM.BodyWordCount, PDM.UniqueEditorsCount, PDM.LatestEditDate, PDM.AvgCommentScoreOnPost,
    PDM.IncomingLinksCount, PDM.PostScoreRankByUser, PDM.PostAgeCategory, PDM.AnswerCount, PDM.AcceptedAnswerId,
    PDM.ClosedDate, PDM.LastActivityDate, PDM.Tags
HAVING
    COUNT(DISTINCT A_main.Id) < 100 -- Not excessively debated questions (for performance)

UNION ALL

SELECT
    'Answer' AS PostType,
    UI.UserId,
    UI.DisplayName,
    UI.Reputation,
    UI.InfluenceScore,
    UI.ReputationQuintile,
    PDM_ans.PostId,
    SUBSTRING(PDM_ans.PostBody, 1, 100) AS MainContentTitle, -- Use truncated body as title for answers
    PDM_ans.PostBody AS MainContentBody,
    PDM_ans.PostCreationDate,
    PDM_ans.PostScore AS MainContentScore,
    NULL AS MainContentViewCount, -- Answers don't have direct view counts
    PDM_ans.FavoriteCount AS MainContentFavoriteCount,
    PDM_ans.BodyWordCount,
    PDM_ans.UniqueEditorsCount,
    PDM_ans.LatestEditDate,
    PDM_ans.AvgCommentScoreOnPost,
    PDM_ans.IncomingLinksCount, -- Incoming links might refer to this answer directly
    PDM_ans.PostScoreRankByUser,
    PDM_ans.PostAgeCategory,
    -- Correlated subquery: Count comments on this specific answer
    (SELECT COUNT(C_ans.Id) FROM Comments C_ans WHERE C_ans.PostId = PDM_ans.PostId) AS RelatedItemCount,
    -- Correlated subquery: Sum of comment scores on this specific answer
    (SELECT SUM(C_ans.Score) FROM Comments C_ans WHERE C_ans.PostId = PDM_ans.PostId) AS RelatedItemScoreSum,
    NULL AS HasAcceptedAnswer, -- Answers don't 'have' accepted answers
    -- Check if *this* answer is the accepted answer for its parent question
    MAX(CASE WHEN P_parent.AcceptedAnswerId = PDM_ans.PostId THEN 1 ELSE 0 END) AS IsCurrentPostAcceptedAnswer,
    -- Complicated calculation for combined post quality score for answers
    ROUND(
        (PDM_ans.PostScore * 0.6) +
        (PDM_ans.BodyWordCount * 0.008) +
        (PDM_ans.UniqueEditorsCount * 8) +
        (COALESCE(PDM_ans.AvgCommentScoreOnPost, 0) * 3) +
        (PDM_ans.IncomingLinksCount * 15) +
        (CASE WHEN P_parent.AcceptedAnswerId = PDM_ans.PostId THEN 50 ELSE 0 END) -- Bonus for accepted answers
    , 2) AS CombinedPostQualityScore,
    -- Parent question's first tag (string expression)
    COALESCE(
        TRIM(SUBSTRING(P_parent.Tags FROM POSITION('<' IN P_parent.Tags) + 1 FOR POSITION('>' IN P_parent.Tags) - POSITION('<' IN P_parent.Tags) -1))
        , 'No Tag'
    ) AS FirstTag,
    -- Complex predicate/NULL logic for categorizing answer status
    CASE
        WHEN P_parent.AcceptedAnswerId = PDM_ans.PostId THEN 'Accepted Solution'
        WHEN PDM_ans.PostScore >= 20 AND PDM_ans.UniqueEditorsCount > 1 THEN 'Highly Edited Answer'
        WHEN PDM_ans.PostScore < 0 AND PDM_ans.AvgCommentScoreOnPost < 0 THEN 'Poorly Received Answer'
        ELSE 'Other Answer Type'
    END AS PostStatusCategory
FROM
    UserInfluence UI
INNER JOIN
    PostDetailedMetrics PDM_ans ON UI.UserId = PDM_ans.OwnerUserId
INNER JOIN
    Posts P_parent ON PDM_ans.ParentId = P_parent.Id -- Join to get parent question details
WHERE
    PDM_ans.PostTypeId = 2 -- Only answers
    AND PDM_ans.PostScoreRankByUser <= 2 -- Consider only top N answers per user
    AND PDM_ans.BodyWordCount > 20 -- Answers with substantial content
    AND (LOWER(PDM_ans.PostBody) LIKE '%code%' OR LOWER(PDM_ans.PostBody) LIKE '%example%') -- Filter by keywords in body
    AND PDM_ans.AvgCommentScoreOnPost IS NOT NULL -- Exclude answers with no comments or null avg score
GROUP BY -- Grouping for MAX(CASE WHEN P_parent.AcceptedAnswerId = PDM_ans.PostId THEN 1 ELSE 0 END)
    UI.UserId, UI.DisplayName, UI.Reputation, UI.InfluenceScore, UI.ReputationQuintile,
    PDM_ans.PostId, PDM_ans.PostBody, PDM_ans.PostCreationDate, PDM_ans.PostScore, PDM_ans.FavoriteCount,
    PDM_ans.BodyWordCount, PDM_ans.UniqueEditorsCount, PDM_ans.LatestEditDate, PDM_ans.AvgCommentScoreOnPost,
    PDM_ans.IncomingLinksCount, PDM_ans.PostScoreRankByUser, PDM_ans.PostAgeCategory, P_parent.AcceptedAnswerId,
    P_parent.Tags
HAVING
    (SELECT COUNT(C_ans.Id) FROM Comments C_ans WHERE C_ans.PostId = PDM_ans.PostId) < 50 -- Not excessively commented answers

ORDER BY
    InfluenceScore DESC, CombinedPostQualityScore DESC
LIMIT 2000;
