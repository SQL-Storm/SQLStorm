-- {"query": "1581.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3257} 
WITH UserEngagement AS (
    -- CTE 1: Aggregates user activity, post creation, and basic scores.
    -- This includes counts of different post types, comments made, and score summaries.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersCreated,
        COUNT(C.Id) AS TotalCommentsMade,
        SUM(P.Score) AS SumOfPostsScore,
        AVG(P.Score) AS AvgPostScoreOverall,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN PH.Id END) AS TotalPostEditsInitiated, -- User-initiated edits
        MAX(P.CreationDate) AS LatestPostCreationDate,
        MIN(P.CreationDate) AS EarliestPostCreationDate
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN PostHistory AS PH ON U.Id = PH.UserId AND PH.PostId = P.Id
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
),
PostTaggingAndCategory AS (
    -- CTE 2: Parses tags from Posts, associates them with specific tech categories,
    -- and extracts relevant post metadata for questions.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.LastEditDate,
        P.ClosedDate,
        TRIM(LOWER(unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><')))) AS TagName,
        CASE
            WHEN P.Tags LIKE '%<sql>%' OR P.Tags LIKE '%<database>%' OR P.Tags LIKE '%<postgresql>%' OR P.Tags LIKE '%<mysql>%' THEN 'SQL_DB_Tech'
            WHEN P.Tags LIKE '%<python>%' OR P.Tags LIKE '%<django>%' OR P.Tags LIKE '%<flask>%' THEN 'PYTHON_Dev'
            WHEN P.Tags LIKE '%<java>%' OR P.Tags LIKE '%<spring>%' OR P.Tags LIKE '%<android>%' THEN 'JAVA_Dev'
            WHEN P.Tags LIKE '%<javascript>%' OR P.Tags LIKE '%<nodejs>%' OR P.Tags LIKE '%<reactjs>%' OR P.Tags LIKE '%<angular>%' THEN 'JS_Frontend_Dev'
            WHEN P.Tags LIKE '%<.net>%' OR P.Tags LIKE '%<c#>%' OR P.Tags LIKE '%<asp.net>%' THEN 'DOTNET_Dev'
            WHEN P.Tags LIKE '%<php>%' OR P.Tags LIKE '%<laravel>%' OR P.Tags LIKE '%<wordpress>%' THEN 'PHP_Dev'
            ELSE 'OTHER_General_Tech'
        END AS TechCategory
    FROM Posts AS P
    WHERE P.PostTypeId = 1 -- Focus on questions
      AND P.Tags IS NOT NULL
      AND LENGTH(P.Tags) > 2
),
UserTechContributionSummary AS (
    -- CTE 3: Combines user engagement with their contributions to specific tech categories.
    -- Calculates category-specific metrics like post count, average score, and closed posts.
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        PTC.TechCategory,
        COUNT(DISTINCT PTC.PostId) AS PostsInTechCategory,
        SUM(PTC.Score) AS SumScoresInTechCategory,
        AVG(PTC.Score) AS AvgScoreInTechCategory,
        SUM(PTC.ViewCount) AS SumViewsInTechCategory,
        SUM(PTC.AnswerCount) AS SumAnswersInTechCategory,
        COUNT(DISTINCT CASE WHEN PTC.ClosedDate IS NOT NULL THEN PTC.PostId END) AS ClosedQuestionsInTechCategory,
        COUNT(DISTINCT T.Id) AS UniqueTagsUsedInTechCategory,
        MAX(PTC.PostCreationDate) AS LatestContributionInTechCategory
    FROM UserEngagement AS UE
    INNER JOIN PostTaggingAndCategory AS PTC ON UE.UserId = PTC.OwnerUserId
    LEFT JOIN Tags AS T ON PTC.TagName = T.TagName
    WHERE PTC.TechCategory != 'OTHER_General_Tech' -- Filter out generic tech posts
    GROUP BY
        UE.UserId, UE.DisplayName, UE.Reputation, PTC.TechCategory
),
RankedUserTechPerformance AS (
    -- CTE 4: Applies various window functions to rank users within each tech category
    -- based on performance metrics like average score and post count.
    SELECT
        UTCS.UserId,
        UTCS.DisplayName,
        UTCS.Reputation,
        UTCS.TechCategory,
        UTCS.PostsInTechCategory,
        UTCS.AvgScoreInTechCategory,
        UTCS.SumViewsInTechCategory,
        UTCS.SumAnswersInTechCategory,
        UTCS.ClosedQuestionsInTechCategory,
        RANK() OVER (PARTITION BY UTCS.TechCategory ORDER BY UTCS.AvgScoreInTechCategory DESC, UTCS.PostsInTechCategory DESC, UTCS.Reputation DESC) AS RankByAvgScore,
        DENSE_RANK() OVER (PARTITION BY UTCS.TechCategory ORDER BY UTCS.PostsInTechCategory DESC, UTCS.AvgScoreInTechCategory DESC) AS RankByPostCount,
        NTILE(4) OVER (PARTITION BY UTCS.TechCategory ORDER BY UTCS.AvgScoreInTechCategory DESC) AS AvgScoreQuartile, -- Divides users into 4 performance groups
        LAG(UTCS.AvgScoreInTechCategory, 1, 0.0) OVER (PARTITION BY UTCS.TechCategory ORDER BY UTCS.AvgScoreInTechCategory DESC) AS PreviousRankAvgScore,
        AVG(UTCS.AvgScoreInTechCategory) OVER (PARTITION BY UTCS.TechCategory) AS CategoryAvgScore,
        MAX(UTCS.LatestContributionInTechCategory) OVER (PARTITION BY UTCS.UserId) AS UserLatestCategoryContribution
    FROM UserTechContributionSummary AS UTCS
    WHERE UTCS.PostsInTechCategory >= 3 -- Minimum posts for meaningful ranking
),
RelatedPostInfluence AS (
    -- CTE 5: Analyzes related posts (linked/duplicate) for each user's posts.
    SELECT
        P.OwnerUserId AS InitiatingUserId,
        PL.LinkTypeId,
        LT.Name AS LinkTypeName,
        COUNT(DISTINCT PL.PostId) AS TotalInitiatingPostsWithLink,
        COUNT(DISTINCT PL.RelatedPostId) AS TotalRelatedPostsIdentified,
        SUM(CASE WHEN RelatedP.OwnerUserId IS NOT NULL THEN 1 ELSE 0 END) AS RelatedPostsByKnownUsersCount,
        SUM(CASE WHEN RelatedP.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS RelatedPostsAreClosedCount,
        COALESCE(AVG(RelatedP.Score), 0.0) AS AvgScoreOfRelatedPosts,
        COALESCE(MAX(RelatedP.Score), 0) AS MaxScoreOfRelatedPosts
    FROM Posts AS P
    INNER JOIN PostLinks AS PL ON P.Id = PL.PostId
    INNER JOIN LinkTypes AS LT ON PL.LinkTypeId = LT.Id
    LEFT JOIN Posts AS RelatedP ON PL.RelatedPostId = RelatedP.Id
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId, PL.LinkTypeId, LT.Name
),
UserBadgeSummary AS (
    -- CTE 6: Summarizes badge achievements for each user.
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT CASE WHEN B.TagBased = TRUE THEN B.Name END) AS UniqueTagBasedBadges,
        MAX(B.Date) AS LatestBadgeAwardDate,
        MIN(B.Date) AS EarliestBadgeAwardDate
    FROM Badges AS B
    GROUP BY B.UserId
)
-- Main Query: Joins all CTEs to provide a comprehensive view of top tech contributors.
-- Includes various metrics, rankings, and deep dives into post relationships and user achievements.
SELECT
    RUTP.UserId,
    RUTP.DisplayName,
    RUTP.Reputation,
    RUTP.TechCategory,
    RUTP.PostsInTechCategory,
    RUTP.AvgScoreInTechCategory,
    RUTP.RankByAvgScore,
    RUTP.RankByPostCount,
    RUTP.AvgScoreQuartile,
    RUTP.CategoryAvgScore,
    RUTP.PreviousRankAvgScore,
    UE.UserProfileViews,
    UE.TotalQuestionsCreated,
    UE.TotalAnswersCreated,
    UE.TotalCommentsMade,
    UE.TotalPostEditsInitiated,
    UBS.TotalBadgesEarned,
    UBS.GoldBadges,
    UBS.SilverBadges,
    COALESCE(RPI_Linked.TotalInitiatingPostsWithLink, 0) AS UserPostsLinkingOthers,
    COALESCE(RPI_Linked.AvgScoreOfRelatedPosts, 0.0) AS AvgScoreOfLinkedPosts,
    COALESCE(RPI_Duplicate.TotalInitiatingPostsWithLink, 0) AS UserPostsMarkedAsDuplicate,
    COALESCE(RPI_Duplicate.RelatedPostsAreClosedCount, 0) AS CountOfDuplicateTargetPostsClosed,
    (
        -- Correlated Subquery 1: Check for recent posts owned by the user that were subsequently closed.
        SELECT COUNT(DISTINCT PH_Sub.PostId)
        FROM PostHistory AS PH_Sub
        WHERE PH_Sub.UserId = RUTP.UserId
          AND PH_Sub.PostHistoryTypeId = 10 -- Post Closed
          AND PH_Sub.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
          AND EXISTS (SELECT 1 FROM Posts AS P_Sub WHERE P_Sub.Id = PH_Sub.PostId AND P_Sub.OwnerUserId = RUTP.UserId)
    ) AS RecentOwnedPostsClosedBySelfOrOthers,
    COALESCE(NULLIF(UE.TotalPostsCreated, 0), 1) AS TotalPostsCreatedNullIfZeroForDivision, -- Example NULL logic with NULLIF and COALESCE
    (
        -- Correlated Subquery 2: Calculate average score of user's answers posted in the same tech category.
        SELECT AVG(AnsP.Score)
        FROM Posts AS AnsP
        INNER JOIN PostTaggingAndCategory AS AnsPTC ON AnsP.Id = AnsPTC.PostId
        WHERE AnsP.OwnerUserId = RUTP.UserId
          AND AnsP.PostTypeId = 2 -- Only answers
          AND AnsPTC.TechCategory = RUTP.TechCategory
          AND AnsP.CreationDate BETWEEN UE.EarliestPostCreationDate AND UE.LatestPostCreationDate
    ) AS AvgAnswerScoreInTechCategory,
    ABS(RUTP.AvgScoreInTechCategory - RUTP.CategoryAvgScore) AS ScoreDeviationFromCategoryAvg, -- Complex calculation
    (UE.UserProfileViews * 0.1 + UE.Reputation * 0.05 + RUTP.PostsInTechCategory * 2) AS CalculatedInfluenceScore -- Arbitrary complex expression
FROM RankedUserTechPerformance AS RUTP
INNER JOIN UserEngagement AS UE ON RUTP.UserId = UE.UserId
LEFT JOIN RelatedPostInfluence AS RPI_Linked ON RUTP.UserId = RPI_Linked.InitiatingUserId AND RPI_Linked.LinkTypeId = 1 -- Linked posts
LEFT JOIN RelatedPostInfluence AS RPI_Duplicate ON RUTP.UserId = RPI_Duplicate.InitiatingUserId AND RPI_Duplicate.LinkTypeId = 3 -- Duplicate posts
LEFT JOIN UserBadgeSummary AS UBS ON RUTP.UserId = UBS.UserId
WHERE
    RUTP.RankByAvgScore <= 20 -- Top 20 contributors by average score in each category
    AND RUTP.PostsInTechCategory >= 10 -- Users with significant contribution
    AND RUTP.Reputation >= 1000 -- Reputable users
    AND RUTP.TechCategory IN ('SQL_DB_Tech', 'PYTHON_Dev', 'JAVA_Dev', 'JS_Frontend_Dev') -- Focus on specific tech stacks
    AND (UBS.GoldBadges > 0 OR RUTP.Reputation >= 10000 OR UE.UserTotalUpVotes > 500) -- Complex predicate with OR
    AND RUTP.UserLatestCategoryContribution IS NOT NULL AND RUTP.UserLatestCategoryContribution > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '3 years' -- Active within last 3 years
    AND NOT EXISTS (
        -- Non-correlated subquery used with NOT EXISTS: exclude users who have been 'punished' recently (e.g., deleted posts)
        SELECT 1 FROM PostHistory AS PH_Exclude
        WHERE PH_Exclude.UserId = RUTP.UserId
          AND PH_Exclude.PostHistoryTypeId = 12 -- Post Deleted
          AND PH_Exclude.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months'
    )
ORDER BY
    RUTP.TechCategory,
    RUTP.RankByAvgScore ASC,
    RUTP.Reputation DESC,
    CalculatedInfluenceScore DESC;