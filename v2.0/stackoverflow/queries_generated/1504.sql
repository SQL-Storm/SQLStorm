-- {"query": "1504.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3045} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Deleted User') AS UserDisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.UpVotes AS TotalUpvotesGiven,
        NULLIF(U.DownVotes, 0) AS TotalDownvotesGiven, -- NULLIF for zero downvotes
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - U.CreationDate)) / (3600 * 24) AS AccountAgeDays,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - U.LastAccessDate)) / (3600 * 24) AS LastAccessRecencyDays,
        -- Correlated Subquery: Average score of questions owned by this user
        (SELECT AVG(SubP.Score) FROM Posts SubP WHERE SubP.OwnerUserId = U.Id AND SubP.PostTypeId = 1) AS AvgQuestionScore,
        -- String expression and window function for location-based rank
        UPPER(SUBSTRING(COALESCE(U.Location, 'Unknown'), 1, 15)) AS LocationPrefix,
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC, COUNT(DISTINCT P.Id) DESC) AS UserOverallActivityRank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.Location
),
PostDetailedMetrics AS (
    SELECT
        P.Id AS PostId,
        PT.Name AS PostType,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        COALESCE(P.AnswerCount, 0) AS AnswerCount, -- NULL logic COALESCE
        COALESCE(P.CommentCount, 0) AS PostCommentCount,
        COALESCE(P.FavoriteCount, 0) AS FavoriteCount,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Title AS PostTitle,
        P.Body AS PostBody,
        P.Tags,
        P.ClosedDate,
        P.LastEditDate,
        P.LastActivityDate,
        CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer,
        -- Correlated Subquery: Total upvotes for this post
        COALESCE((SELECT SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) FROM Votes V WHERE V.PostId = P.Id), 0) AS PostUpvoteCount,
        -- Correlated Subquery: Total downvotes for this post
        COALESCE((SELECT SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) FROM Votes V WHERE V.PostId = P.Id), 0) AS PostDownvoteCount,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - P.LastEditDate)) / 3600 AS LastEditAgeHours,
        (SELECT COUNT(DISTINCT PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS PostEditCount, -- Correlated Subquery for edit history
        P.ClosedDate IS NOT NULL AS IsClosed,
        -- Window function: Average score of posts by the same owner in the same year
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId, EXTRACT(YEAR FROM P.CreationDate)) AS AvgOwnerYearlyPostScore,
        -- Window function: NTILE to categorize posts by view count within their type
        NTILE(10) OVER (PARTITION BY P.PostTypeId ORDER BY P.ViewCount DESC) AS PostViewScoreDecile,
        -- String expression: Count number of tags
        ARRAY_LENGTH(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><'), 1) AS TagCount,
        COALESCE(P.ContentLicense, 'Unknown License') AS ContentLicenseType
    FROM Posts P
    LEFT JOIN PostTypes PT ON P.PostTypeId = PT.Id
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions and Answers
),
CommentQualityMetrics AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalCommentsOnPost,
        AVG(C.Score) AS AvgCommentScore,
        MAX(LENGTH(C.Text)) AS MaxCommentLength,
        MIN(LENGTH(C.Text)) AS MinCommentLength,
        -- String expressions for simple sentiment analysis
        SUM(CASE WHEN C.Text LIKE '%thank%' OR C.Text LIKE '%helpful%' OR C.Text LIKE '%appreciate%' THEN 1 ELSE 0 END) AS PositiveCommentCount,
        SUM(CASE WHEN C.Text LIKE '%error%' OR C.Text LIKE '%bug%' OR C.Text LIKE '%incorrect%' THEN 1 ELSE 0 END) AS NegativeCommentCount
    FROM Comments C
    GROUP BY C.PostId
),
RecentHighlyVotedContent AS (
    -- Set operator (UNION ALL) to combine recent high-score questions and answers
    SELECT
        P.Id AS ContentId,
        COALESCE(P.Title, SUBSTRING(P.Body, 1, 100) || '...') AS ContentTitle, -- String expression for answer title
        P.Score AS ContentScore,
        P.CreationDate AS ContentDate,
        'Question' AS ContentType,
        U.DisplayName AS OwnerDisplayName
    FROM Posts P
    LEFT JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostTypeId = 1 -- Questions
      AND P.Score > 20
      AND P.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year'

    UNION ALL

    SELECT
        P.Id AS ContentId,
        COALESCE(P.Title, SUBSTRING(P.Body, 1, 100) || '...') AS ContentTitle,
        P.Score AS ContentScore,
        P.CreationDate AS ContentDate,
        'Answer' AS ContentType,
        U.DisplayName AS OwnerDisplayName
    FROM Posts P
    LEFT JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostTypeId = 2 -- Answers
      AND P.Score > 15
      AND P.CreationDate > CURRENT_TIMESTAMP - INTERVAL '6 months'
)
SELECT
    UAS.UserDisplayName,
    UAS.Reputation,
    UAS.LocationPrefix,
    UAS.AccountAgeDays,
    UAS.LastAccessRecencyDays,
    UAS.UserOverallActivityRank,
    PDM.PostTitle,
    PDM.PostType,
    PDM.PostCreationDate,
    PDM.PostScore,
    PDM.ViewCount,
    PDM.HasAcceptedAnswer,
    PDM.PostUpvoteCount,
    PDM.PostDownvoteCount,
    PDM.PostEditCount,
    PDM.LastEditAgeHours,
    PDM.IsClosed,
    PDM.TagCount,
    PDM.PostViewScoreDecile,
    PDM.ContentLicenseType,
    CQM.TotalCommentsOnPost,
    COALESCE(CQM.AvgCommentScore, 0.0) AS AvgCommentScore, -- NULL logic COALESCE
    CQM.PositiveCommentCount,
    CQM.NegativeCommentCount,
    RHC.ContentTitle AS RelatedHighlyVotedContent,
    RHC.ContentScore AS RelatedContentScore,
    RHC.ContentType AS RelatedContentType,
    -- Complex Calculation: User Engagement Score
    (
        UAS.Reputation * 0.1
        + UAS.TotalUpvotesGiven * 0.05
        - COALESCE(UAS.TotalDownvotesGiven, 0) * 0.02 -- NULL logic on NULLIF'd column
        + UAS.TotalPostsOwned * 0.03
        + UAS.TotalCommentsMade * 0.01
        + (UAS.GoldBadges * 5 + UAS.SilverBadges * 2 + UAS.BronzeBadges * 0.5)
        + COALESCE(UAS.AvgQuestionScore, 0) * 0.05
        - UAS.LastAccessRecencyDays * 0.001
    ) AS UserEngagementScore,
    -- Complex Calculation: Post Impact Factor
    (
        PDM.PostScore * 0.2
        + PDM.ViewCount * 0.005
        + PDM.AnswerCount * 0.1
        + PDM.PostCommentCount * 0.05
        + PDM.FavoriteCount * 0.15
        + (CASE WHEN PDM.HasAcceptedAnswer THEN 10 ELSE 0 END)
        - PDM.LastEditAgeHours * 0.001
        + PDM.PostEditCount * 0.02
        + COALESCE(CQM.AvgCommentScore, 0) * 0.03
        + (CASE WHEN PDM.IsClosed THEN -5 ELSE 0 END) -- NULL logic within CASE
        + (PDM.TagCount * 0.1)
    ) AS PostImpactFactor,
    -- Window function: Rank combined user and post scores
    RANK() OVER (
        ORDER BY
            (
                UAS.Reputation * 0.1
                + UAS.TotalUpvotesGiven * 0.05
                - COALESCE(UAS.TotalDownvotesGiven, 0) * 0.02
                + UAS.TotalPostsOwned * 0.03
                + UAS.TotalCommentsMade * 0.01
                + (UAS.GoldBadges * 5 + UAS.SilverBadges * 2 + UAS.BronzeBadges * 0.5)
                + COALESCE(UAS.AvgQuestionScore, 0) * 0.05
                - UAS.LastAccessRecencyDays * 0.001
            ) DESC,
            (
                PDM.PostScore * 0.2
                + PDM.ViewCount * 0.005
                + PDM.AnswerCount * 0.1
                + PDM.PostCommentCount * 0.05
                + PDM.FavoriteCount * 0.15
                + (CASE WHEN PDM.HasAcceptedAnswer THEN 10 ELSE 0 END)
                - PDM.LastEditAgeHours * 0.001
                + PDM.PostEditCount * 0.02
                + COALESCE(CQM.AvgCommentScore, 0) * 0.03
                + (CASE WHEN PDM.IsClosed THEN -5 ELSE 0 END)
                + (PDM.TagCount * 0.1)
            ) DESC
    ) AS OverallCombinedRank
FROM UserActivitySummary UAS
LEFT JOIN PostDetailedMetrics PDM ON UAS.UserId = PDM.OwnerUserId
LEFT JOIN CommentQualityMetrics CQM ON PDM.PostId = CQM.PostId
LEFT JOIN RecentHighlyVotedContent RHC ON PDM.PostId = RHC.ContentId -- Join with set operation CTE
WHERE
    UAS.AccountAgeDays > 365 -- Filter for established users
    AND PDM.PostCreationDate > CURRENT_TIMESTAMP - INTERVAL '2 year' -- Filter for relatively recent posts
    AND PDM.ViewCount > 1000 -- Posts with significant visibility
    -- Complicated predicate with string expressions for tag relevance
    AND (PDM.Tags LIKE '%<sql>%' OR PDM.Tags LIKE '%<database>%' OR PDM.Tags LIKE '%<performance-tuning>%')
    -- Correlated NOT EXISTS subquery for non-deleted posts
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory PH
        WHERE PH.PostId = PDM.PostId
          AND PH.PostHistoryTypeId = 12 -- Post Deleted
          AND PH.CreationDate > PDM.PostCreationDate -- Ensure deletion happened after creation
    )
    -- Complicated predicate using OR for different post type score thresholds
    AND (
        (PDM.PostType = 'Question' AND PDM.PostScore >= 50 AND PDM.AnswerCount >= 1)
        OR (PDM.PostType = 'Answer' AND PDM.PostScore >= 25)
    )
    AND UAS.Reputation > 5000 -- Filter for users with substantial reputation
ORDER BY OverallCombinedRank ASC, UAS.Reputation DESC, PDM.PostScore DESC
LIMIT 100;
