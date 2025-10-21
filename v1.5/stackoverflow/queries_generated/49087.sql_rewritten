-- {"query": "49087.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1858} 
WITH UserPostStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(p.Score) AS TotalPostScore,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) AS QuestionsWithAnswers,
        SUM(p.ViewCount) AS TotalPostViews
    FROM Posts AS p
    WHERE
        p.PostTypeId IN (1, 2) -- Questions or Answers
        AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
        AND p.CreationDate >= '2020-01-01' AND p.CreationDate < '2023-01-01'
    GROUP BY p.OwnerUserId
),
UserCommentMetrics AS (
    SELECT
        c.UserId,
        AVG(c.Score) AS AvgPositiveCommentScore,
        COUNT(c.Id) AS TotalPositiveCommentsMade
    FROM Comments AS c
    WHERE
        c.Score > 0
        AND c.UserId IS NOT NULL AND c.UserId > 0
        AND c.CreationDate >= '2020-01-01' AND c.CreationDate < '2023-01-01'
    GROUP BY c.UserId
),
UserBadgeBreakdown AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges
    FROM Badges AS b
    WHERE
        b.UserId IS NOT NULL AND b.UserId > 0
        AND b.Date >= '2020-01-01' AND b.Date < '2023-01-01'
    GROUP BY b.UserId
),
UserPostEditAnalysis AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT ph.PostId) AS DistinctPostsEditedByOthers,
        COUNT(ph.Id) AS TotalEditsByOthersOnPosts
    FROM PostHistory AS ph
    JOIN Posts AS p ON ph.PostId = p.Id
    WHERE
        ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
        AND ph.UserId IS NOT NULL AND ph.UserId > 0
        AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
        AND ph.UserId <> p.OwnerUserId -- Edited by someone other than the owner
        AND ph.CreationDate >= '2020-01-01' AND ph.CreationDate < '2023-01-01'
    GROUP BY p.OwnerUserId
),
UserTopTag AS (
    SELECT
        UserId,
        TagName AS MostPopularTagName,
        TagCount AS MostPopularTagCount
    FROM (
        SELECT
            p.OwnerUserId AS UserId,
            TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><'))) AS TagName,
            COUNT(*) AS TagCount,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC, TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><'))) ASC) AS rn
        FROM Posts AS p
        WHERE
            p.PostTypeId = 1 -- Only questions have meaningful tags for this purpose
            AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
            AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
            AND p.CreationDate >= '2020-01-01' AND p.CreationDate < '2023-01-01'
        GROUP BY p.OwnerUserId, TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')))
    ) AS TagCountsRanked
    WHERE rn = 1
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(ups.TotalPostScore, 0) AS TotalPostScore,
        COALESCE(ups.QuestionsWithAnswers, 0) AS TotalQuestionsWithAnswers,
        COALESCE(ups.TotalPostViews, 0) AS TotalPostsViewed,
        COALESCE(ucm.AvgPositiveCommentScore, 0.0) AS AveragePositiveCommentScore,
        COALESCE(ucm.TotalPositiveCommentsMade, 0) AS TotalPositiveComments,
        COALESCE(ubb.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubb.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubb.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(upea.DistinctPostsEditedByOthers, 0) AS PostsEditedByOthersCount,
        COALESCE(upea.TotalEditsByOthersOnPosts, 0) AS TotalPostEditsByOthers,
        utt.MostPopularTagName,
        utt.MostPopularTagCount,
        -- Custom Performance Score calculation
        (COALESCE(ups.TotalPostScore, 0) * 0.7) +
        (COALESCE(ups.QuestionsWithAnswers, 0) * 10) +
        (COALESCE(ups.TotalPostViews, 0) * 0.01) +
        (COALESCE(ucm.AvgPositiveCommentScore, 0.0) * 5) +
        (COALESCE(ubb.GoldBadges, 0) * 100) +
        (COALESCE(ubb.SilverBadges, 0) * 50) +
        (COALESCE(ubb.BronzeBadges, 0) * 10) -
        (COALESCE(upea.TotalEditsByOthersOnPosts, 0) * 2) +
        (u.UpVotes * 0.1) - (u.DownVotes * 0.5) AS CustomPerformanceScore
    FROM Users AS u
    LEFT JOIN UserPostStats AS ups ON u.Id = ups.UserId
    LEFT JOIN UserCommentMetrics AS ucm ON u.Id = ucm.UserId
    LEFT JOIN UserBadgeBreakdown AS ubb ON u.Id = ubb.UserId
    LEFT JOIN UserPostEditAnalysis AS upea ON u.Id = upea.UserId
    LEFT JOIN UserTopTag AS utt ON u.Id = utt.UserId
    WHERE u.DisplayName IS NOT NULL AND u.DisplayName <> ''
      AND u.LastAccessDate >= '2020-01-01' AND u.LastAccessDate < '2023-01-01' -- Filter users active in the period
)
SELECT
    UserId,
    DisplayName,
    Reputation,
    UserCreationDate,
    LastAccessDate,
    TotalPostScore,
    TotalQuestionsWithAnswers,
    TotalPostsViewed,
    AveragePositiveCommentScore,
    TotalPositiveComments,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    PostsEditedByOthersCount,
    TotalPostEditsByOthers,
    MostPopularTagName,
    MostPopularTagCount,
    CustomPerformanceScore,
    RANK() OVER (ORDER BY CustomPerformanceScore DESC, Reputation DESC, UserId ASC) AS RankByPerformance,
    DENSE_RANK() OVER (ORDER BY TotalPostScore DESC, TotalPostsViewed DESC, UserId ASC) AS RankByPostContribution
FROM UserActivitySummary
WHERE CustomPerformanceScore > 0 -- Only show users with a positive custom performance score
ORDER BY RankByPerformance ASC
LIMIT 200;