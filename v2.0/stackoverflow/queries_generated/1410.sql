-- {"query": "1410.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3240} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Reputation,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        MAX(COALESCE(P.LastActivityDate, C.CreationDate, U.LastAccessDate)) AS LastUserActivityDate,
        -- Calculate average days since last activity for their posts
        AVG(EXTRACT(EPOCH FROM (NOW() - P.LastActivityDate))/86400) FILTER (WHERE P.LastActivityDate IS NOT NULL) AS AvgDaysSincePostActivity
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    WHERE U.CreationDate >= '2010-01-01' -- Filter for a specific user base timeframe
    GROUP BY U.Id, U.DisplayName, U.CreationDate, U.LastAccessDate, U.Reputation, U.UpVotes, U.DownVotes
),
PostQualityMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate AS PostLastActivityDate,
        P.ClosedDate,
        P.ParentId,
        P.AcceptedAnswerId,
        LENGTH(P.Body) AS BodyLength,
        LENGTH(P.Title) AS TitleLength,
        P.Tags,
        -- Calculate a composite quality score for posts, with NULL handling
        (COALESCE(P.Score, 0) * 5) +
        (CASE WHEN P.ViewCount IS NOT NULL THEN P.ViewCount / 100.0 ELSE 0 END) +
        (CASE WHEN P.AnswerCount IS NOT NULL THEN P.AnswerCount * 2 ELSE 0 END) +
        (CASE WHEN P.FavoriteCount IS NOT NULL THEN P.FavoriteCount * 3 ELSE 0 END) +
        (CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 10 ELSE 0 END)
        AS CompositeQualityScore,
        -- Window function: Rank posts by score within their PostType, considering CreationDate for ties
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY COALESCE(P.Score, 0) DESC, P.CreationDate DESC) AS PostTypeScoreRank,
        -- Window function: Calculate average score of posts by the same user, excluding negative scores
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId) FILTER (WHERE P.Score > 0) AS AvgOwnerPositivePostScore,
        -- Correlated subquery: Check if post has ever been closed (PostHistoryTypeId = 10)
        EXISTS (SELECT 1 FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 10 AND PH.CreationDate > P.CreationDate) AS WasEverClosed,
        -- Correlated subquery: Check if post has any linked duplicates (LinkTypeId = 3)
        EXISTS (SELECT 1 FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 3) AS HasDuplicatesLinked
    FROM Posts P
    WHERE P.CreationDate >= '2010-01-01' AND P.OwnerUserId IS NOT NULL -- Focus on owned posts within timeframe
),
TopTagsByActivity AS (
    SELECT
        Tag,
        COUNT(DISTINCT PostId) AS TagPostCount,
        SUM(COALESCE(PostScore, 0)) AS TagTotalScore,
        AVG(COALESCE(PostScore, 0)) AS TagAvgScore,
        -- Rank tags by post count, then total score
        RANK() OVER (ORDER BY COUNT(DISTINCT PostId) DESC, SUM(COALESCE(PostScore, 0)) DESC) AS TagPopularityRank
    FROM PostQualityMetrics,
    LATERAL UNNEST(string_to_array(REPLACE(REPLACE(Tags, '<', ''), '>', ''), ',')) AS Tag -- Assumes PostgreSQL string_to_array
    WHERE Tags IS NOT NULL AND Tags != '' AND PostTypeId = 1 -- Only consider tags from questions
    GROUP BY Tag
    HAVING COUNT(DISTINCT PostId) > 50 AND AVG(COALESCE(PostScore, 0)) > 5 -- Only popular and well-received tags
),
BadgeAchievementSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeDate,
        -- Calculate percentile rank based on total gold badges
        NTILE(100) OVER (ORDER BY COUNT(CASE WHEN B.Class = 1 THEN 1 END) DESC) AS GoldBadgePercentileRank
    FROM Badges B
    GROUP BY B.UserId
),
CommentSentimentProxy AS (
    SELECT
        C.PostId,
        AVG(COALESCE(C.Score, 0)) AS AvgCommentScore,
        -- Simple sentiment proxy based on comment text length, keywords, and score
        SUM(CASE
                WHEN LOWER(C.Text) LIKE '%thank%' OR LOWER(C.Text) LIKE '%great%' OR C.Score > 0 THEN 1
                WHEN LOWER(C.Text) LIKE '%bug%' OR LOWER(C.Text) LIKE '%issue%' OR LOWER(C.Text) LIKE '%error%' OR C.Score < 0 THEN -1
                WHEN LENGTH(C.Text) < 10 THEN 0.5 -- Short comments might be less substantial
                ELSE 0
            END) AS SentimentScoreSum,
        COUNT(C.Id) AS CommentCountForPost
    FROM Comments C
    GROUP BY C.PostId
)
-- Main query combining all CTEs with complex logic
SELECT
    UE.UserId,
    COALESCE(UE.DisplayName, 'Unknown User ' || UE.UserId) AS UserDisplayName, -- NULL logic for display name
    UE.Reputation,
    UE.TotalPosts,
    UE.TotalQuestions,
    UE.TotalAnswers,
    UE.TotalPostScore,
    BAS.TotalBadges,
    BAS.GoldBadges,
    BAS.SilverBadges,
    BAS.GoldBadgePercentileRank,
    PQM.PostId AS TopPostId,
    PQM.PostTypeId AS TopPostType,
    PQM.PostScore AS TopPostScore,
    PQM.ViewCount AS TopPostViewCount,
    PQM.CompositeQualityScore AS TopPostQualityScore,
    PQM.WasEverClosed,
    PQM.HasDuplicatesLinked,
    COALESCE(CSP.AvgCommentScore, 0) AS TopPostAvgCommentScore,
    COALESCE(CSP.SentimentScoreSum, 0) AS TopPostCommentSentiment,
    TTS.TagPopularityRank AS TopPostPrimaryTagPopularityRank,
    -- Complex calculation: User's average post quality relative to their total posts, reputation, and gold badges
    CAST(UE.TotalPostScore AS NUMERIC) / NULLIF(UE.TotalPosts, 0) *
    (1 + CAST(UE.Reputation AS NUMERIC) / 100000.0) * -- Amplify for high reputation
    (1 + CAST(BAS.GoldBadges AS NUMERIC) / NULLIF(BAS.TotalBadges, 0.001)) AS WeightedUserQualityMetric, -- Avoid division by zero
    -- Correlated subquery: Count user's accepted answers to questions from top-scoring distinct tags
    (SELECT COUNT(DISTINCT A.Id)
     FROM Posts Q
     INNER JOIN Posts A ON Q.AcceptedAnswerId = A.Id AND A.OwnerUserId = UE.UserId AND Q.Id = A.ParentId
     INNER JOIN TopTagsByActivity TTS_sub ON TTS_sub.TagPopularityRank <= 10
        AND Q.Tags LIKE '%<' || TTS_sub.Tag || '>%'
     WHERE Q.OwnerUserId = UE.UserId
       AND Q.PostTypeId = 1
       AND Q.CreationDate >= UE.UserCreationDate
       AND Q.Score >= 50
    ) AS AcceptedAnswersInTopTagsCount,
    -- NULL logic and complicated predicate for a 'User Impact Category'
    CASE
        WHEN UE.Reputation > 75000 AND BAS.GoldBadges >= 10 AND PQM.CompositeQualityScore > 100 THEN 'Legendary Trailblazer'
        WHEN UE.TotalAnswers > 200 AND UE.TotalPostScore > 2500 AND PQM.CompositeQualityScore > 75 AND PQM.AcceptedAnswerId IS NOT NULL THEN 'Elite Answer Architect'
        WHEN UE.TotalQuestions > 75 AND PQM.CompositeQualityScore > 120 AND PQM.ViewCount > 50000 AND PQM.WasEverClosed = FALSE THEN 'Profound Question Setter'
        WHEN UE.LastUserActivityDate > NOW() - INTERVAL '6 months' AND UE.TotalPosts > 20 AND BAS.SilverBadges >= 5 THEN 'Highly Engaged Contributor'
        WHEN UE.DisplayName IS NULL OR UE.DisplayName = '' OR LOWER(UE.DisplayName) LIKE '%guest%' THEN 'Unattributed Contributor'
        ELSE 'Active Community Member'
    END AS UserImpactCategory,
    -- String expression: Extract the first non-empty tag from the top post, handle missing tags gracefully
    COALESCE(NULLIF(SUBSTRING(PQM.Tags, POSITION('<' IN PQM.Tags) + 1, POSITION('>' IN PQM.Tags) - POSITION('<' IN PQM.Tags) - 1), ''), 'NO_TAG_SPECIFIED') AS TopPostPrimaryTag,
    -- Calculate a running average of composite quality score for user's posts, partitioned by their UserImpactCategory
    AVG(PQM.CompositeQualityScore) OVER (PARTITION BY
        CASE
            WHEN UE.Reputation > 75000 AND BAS.GoldBadges >= 10 AND PQM.CompositeQualityScore > 100 THEN 'Legendary Trailblazer'
            WHEN UE.TotalAnswers > 200 AND UE.TotalPostScore > 2500 AND PQM.CompositeQualityScore > 75 AND PQM.AcceptedAnswerId IS NOT NULL THEN 'Elite Answer Architect'
            WHEN UE.TotalQuestions > 75 AND PQM.CompositeQualityScore > 120 AND PQM.ViewCount > 50000 AND PQM.WasEverClosed = FALSE THEN 'Profound Question Setter'
            WHEN UE.LastUserActivityDate > NOW() - INTERVAL '6 months' AND UE.TotalPosts > 20 AND BAS.SilverBadges >= 5 THEN 'Highly Engaged Contributor'
            WHEN UE.DisplayName IS NULL OR UE.DisplayName = '' OR LOWER(UE.DisplayName) LIKE '%guest%' THEN 'Unattributed Contributor'
            ELSE 'Active Community Member'
        END
    ) AS AvgQualityScorePerCategory
FROM UserEngagement UE
INNER JOIN BadgeAchievementSummary BAS ON UE.UserId = BAS.UserId
INNER JOIN PostQualityMetrics PQM ON UE.UserId = PQM.OwnerUserId
LEFT JOIN CommentSentimentProxy CSP ON PQM.Id = CSP.PostId
LEFT JOIN TopTagsByActivity TTS ON (
    CASE
        WHEN PQM.Tags IS NOT NULL AND PQM.Tags != '' AND POSITION('<' IN PQM.Tags) > 0 AND POSITION('>' IN PQM.Tags) > POSITION('<' IN PQM.Tags)
        THEN SUBSTRING(PQM.Tags, POSITION('<' IN PQM.Tags) + 1, POSITION('>' IN PQM.Tags) - POSITION('<' IN PQM.Tags) - 1)
        ELSE NULL
    END
) = TTS.Tag
WHERE
    UE.Reputation >= 2000 -- Filter for users with substantial reputation
    AND UE.TotalPosts > 10 -- Ensure users have made significant contributions
    AND PQM.PostTypeScoreRank = 1 -- Only consider the single highest-scoring post of each type (Q/A) for a user as their "top post"
    AND PQM.PostTypeId IN (1, 2) -- Focus on Questions and Answers
    AND PQM.CompositeQualityScore > 40 -- Filter for posts with a minimum quality score
    AND UE.LastUserActivityDate >= NOW() - INTERVAL '2 year' -- Only recent active users
    AND (
        (UE.TotalQuestions >= 15 AND PQM.PostTypeId = 1 AND PQM.AnswerCount >= 3) OR -- Questions with at least 3 answers
        (UE.TotalAnswers >= 20 AND PQM.PostTypeId = 2 AND PQM.AcceptedAnswerId IS NOT NULL AND PQM.PostScore >= 10) -- Accepted answers with good score
    )
    AND PQM.WasEverClosed = FALSE
    AND PQM.HasDuplicatesLinked = FALSE
    AND (LOWER(UE.DisplayName) NOT LIKE '%deleted user%' OR UE.DisplayName IS NULL) -- Exclude potentially deleted or system users
    AND BAS.TotalBadges >= 5 -- Users with at least 5 badges
ORDER BY
    WeightedUserQualityMetric DESC,
    UE.Reputation DESC,
    BAS.GoldBadges DESC,
    PQM.CompositeQualityScore DESC
LIMIT 5000;
