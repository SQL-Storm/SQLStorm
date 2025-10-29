-- {"query": "1981.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2764} 
WITH UserActivitySummary AS (
    -- CTE 1: Aggregates user-level post statistics, edit contributions, and includes window functions
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Location,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(CASE WHEN P.PostTypeId IN (1, 2) THEN P.Score END) AS AvgPostScore,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditsMade,
        MAX(PH.CreationDate) AS LastEditContributionDate,
        -- Calculate the percentage of questions with an accepted answer (for their own questions)
        CAST(SUM(CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS DECIMAL(5,2)) * 100.0 / NULLIF(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS PctQuestionsWithAcceptedAnswer,
        -- Window function: Minimum creation date of any user within the same location
        MIN(U.CreationDate) OVER (PARTITION BY U.Location) AS MinCreationDateInLocation,
        -- Window function: Rolling maximum reputation over the past 10 users ordered by creation date
        MAX(U.Reputation) OVER (ORDER BY U.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS RollingMaxReputation
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN PostHistory AS PH ON U.Id = PH.UserId AND PH.PostId = P.Id
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Location
),
PostEngagementAnalysis AS (
    -- CTE 2: Analyzes individual post engagement, including correlated subqueries and rank
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.LastActivityDate,
        -- Calculate the time difference between last activity and creation date in hours
        EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 3600.0 AS HoursActiveSinceCreation,
        -- Subquery: Get the average score of comments on this specific post
        (SELECT AVG(C.Score) FROM Comments AS C WHERE C.PostId = P.Id) AS AvgCommentScoreOnPost,
        -- Correlated subquery: Get the total number of upvotes on any post that this post is marked as a duplicate of
        (
            SELECT SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) -- VoteTypeId 2 = UpMod
            FROM PostLinks AS PL
            INNER JOIN Posts AS DupP ON PL.RelatedPostId = DupP.Id
            INNER JOIN Votes AS V ON DupP.Id = V.PostId
            WHERE PL.PostId = P.Id AND PL.LinkTypeId = 3 -- LinkType 3 = Duplicate
        ) AS TotalUpvotesOnDuplicateTarget,
        -- Determine close status category using PostHistory for duplicate reasons
        CASE
            WHEN P.ClosedDate IS NOT NULL AND EXISTS (
                SELECT 1
                FROM PostHistory AS PH_Close
                WHERE PH_Close.PostId = P.Id
                  AND PH_Close.PostHistoryTypeId = 10 -- Post Closed
                  AND PH_Close.Comment = '101' -- CloseReasonType 101 = Duplicate
            ) THEN 'Duplicate Closed'
            WHEN P.ClosedDate IS NOT NULL AND EXISTS (
                SELECT 1
                FROM PostHistory AS PH_Close
                WHERE PH_Close.PostId = P.Id
                  AND PH_Close.PostHistoryTypeId = 10 -- Post Closed
            ) THEN 'Other Closed Reason'
            ELSE 'Not Closed'
        END AS CloseStatusCategory,
        -- Window function: Rank posts by score within their PostTypeId
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS RankByScoreForType
    FROM Posts AS P
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions and Answers
),
TopTagsPerUser AS (
    -- CTE 3: Identifies the top tag used by each user based on their question posts
    SELECT
        U.Id AS UserId,
        T.TagName,
        COUNT(P.Id) AS PostsWithTag,
        -- Window function: Rank tags by count for each user
        ROW_NUMBER() OVER (PARTITION BY U.Id ORDER BY COUNT(P.Id) DESC, T.TagName) AS TagRankForUser
    FROM Users AS U
    INNER JOIN Posts AS P ON U.Id = P.OwnerUserId
    INNER JOIN (
        -- Subquery to parse tags from question posts
        SELECT Id, OwnerUserId,
               UNNEST(string_to_array(SUBSTRING(Tags FROM 2 FOR LENGTH(Tags)-2), '><')) AS ParsedTag
        FROM Posts
        WHERE Tags IS NOT NULL AND PostTypeId = 1 -- Only questions have tags in this format
    ) AS TaggedPosts ON P.Id = TaggedPosts.Id AND P.OwnerUserId = TaggedPosts.OwnerUserId
    INNER JOIN Tags AS T ON TaggedPosts.ParsedTag = T.TagName
    GROUP BY
        U.Id, T.TagName
),
UserBadgeAchievements AS (
    -- CTE 4: Summarizes badge achievements for each user
    SELECT
        U.Id AS UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LatestBadgeDate,
        -- Check if user received any gold badge within their first year
        MAX(CASE WHEN B.Class = 1 AND B.Date < U.CreationDate + INTERVAL '1 year' THEN 1 ELSE 0 END) AS HasEarlyGoldBadge
    FROM Users AS U
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id
)
-- Main query combining results from all CTEs
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.AvgPostScore,
    UAS.TotalEditsMade,
    UAS.PctQuestionsWithAcceptedAnswer,
    UAS.MinCreationDateInLocation,
    UAS.RollingMaxReputation,
    PEA.PostId,
    PEA.PostCreationDate,
    PEA.Score AS PostScore,
    PEA.ViewCount,
    PEA.HoursActiveSinceCreation,
    PEA.AvgCommentScoreOnPost,
    PEA.TotalUpvotesOnDuplicateTarget,
    PEA.CloseStatusCategory,
    PEA.RankByScoreForType,
    TTPU.TagName AS TopUserTag,
    TTPU.PostsWithTag AS TopUserTagCount,
    UBA.TotalBadges,
    UBA.GoldBadges,
    UBA.SilverBadges,
    UBA.BronzeBadges,
    UBA.HasEarlyGoldBadge,
    -- Complex calculated field: User Engagement Index
    (UAS.Reputation * 0.05
     + UAS.TotalPosts * 0.2
     + COALESCE(UAS.PctQuestionsWithAcceptedAnswer, 0) * 0.1
     + COALESCE(UBA.GoldBadges, 0) * 10
     + COALESCE(UBA.SilverBadges, 0) * 5
     + COALESCE(UBA.BronzeBadges, 0) * 1
     + COALESCE(PEA.Score, 0) * 0.02
     + COALESCE(PEA.AvgCommentScoreOnPost, 0) * 0.5
     + CASE WHEN UBA.HasEarlyGoldBadge = 1 THEN 20 ELSE 0 END
     + COALESCE(PEA.TotalUpvotesOnDuplicateTarget, 0) * 0.01 -- Influence from duplicate target
    ) AS UserEngagementIndex,
    -- NULL logic and string expression for Post Body Length Category
    CASE
        WHEN P_body.Body IS NULL THEN 'No Post Body Content'
        WHEN LENGTH(P_body.Body) < 100 THEN 'Very Short Body (<100 chars)'
        WHEN LENGTH(P_body.Body) BETWEEN 100 AND 500 THEN 'Medium Body (100-500 chars)'
        WHEN LENGTH(P_body.Body) > 500 AND LENGTH(P_body.Body) <= 2000 THEN 'Long Body (501-2000 chars)'
        ELSE 'Very Long Body (>2000 chars)'
    END AS PostBodyLengthCategory,
    -- String expression: Extract the first 75 characters of the post title, if exists, otherwise NULL
    SUBSTRING(P_body.Title, 1, 75) AS PostTitleSnippet,
    -- A composite flag combining multiple conditions
    CASE
        WHEN UAS.Reputation > 5000 AND PEA.Score > 50 AND UBA.GoldBadges > 0 AND PEA.CloseStatusCategory = 'Not Closed'
        THEN 'High Impact Unclosed Content Creator'
        WHEN UAS.Reputation > 1000 AND PEA.Score > 20 AND TTPU.TagName IS NOT NULL AND TTPU.PostsWithTag > 5
        THEN 'Active Niche Contributor'
        WHEN PEA.TotalUpvotesOnDuplicateTarget IS NOT NULL AND PEA.TotalUpvotesOnDuplicateTarget > 100
        THEN 'Content Related to Highly Voted Duplicates'
        ELSE 'General Contributor'
    END AS UserContentProfile
FROM UserActivitySummary AS UAS
INNER JOIN PostEngagementAnalysis AS PEA ON UAS.UserId = PEA.OwnerUserId
LEFT JOIN TopTagsPerUser AS TTPU ON UAS.UserId = TTPU.UserId AND TTPU.TagRankForUser = 1 -- Get only the highest-ranked tag for each user
LEFT JOIN UserBadgeAchievements AS UBA ON UAS.UserId = UBA.UserId
LEFT JOIN Posts AS P_body ON PEA.PostId = P_body.Id -- Re-join to Posts to get Body and Title details
WHERE
    UAS.Reputation > 500 -- Minimum reputation filter
    AND PEA.ViewCount > 100 -- Minimum view count filter for posts
    AND PEA.Score > 5 -- Minimum post score filter
    AND UAS.UserCreationDate >= '2016-01-01' -- Filter by user creation date
    AND (
        PEA.CloseStatusCategory != 'Duplicate Closed' -- Exclude posts closed as duplicates from primary analysis
        OR PEA.TotalUpvotesOnDuplicateTarget > 50 -- But include if their duplicate target was very popular
    )
    AND P_body.Body IS NOT NULL -- Ensure body content exists for length category
ORDER BY
    UserEngagementIndex DESC, UAS.UserId, PEA.PostCreationDate DESC
LIMIT 5000;