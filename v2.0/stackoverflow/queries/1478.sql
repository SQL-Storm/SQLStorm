-- {"query": "1478.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2401} 
WITH UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        SUM(CASE WHEN p.PostTypeId = 2 AND p.Id IN (SELECT q.AcceptedAnswerId FROM Posts q WHERE q.PostTypeId = 1) THEN 1 ELSE 0 END) AS AcceptedAnswersGivenByMe,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(p.Score), 0.0) AS AvgPostScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalViewCount,
        COALESCE(SUM(p.CommentCount), 0) AS TotalPostCommentCount,
        MAX(p.CreationDate) AS LatestPostCreation,
        MAX(p.LastActivityDate) AS LatestPostActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.DisplayName IS NOT NULL AND LENGTH(TRIM(u.DisplayName)) > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) > 0
       AND SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) > 0
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteCommentStats AS (
    SELECT
        u.Id AS UserId,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesReceivedOnPosts,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesReceivedOnPosts,
        COALESCE(AVG(c.Score), 0.0) AS AverageCommentScoreOnUserPosts,
        COUNT(DISTINCT c.Id) AS TotalCommentsOnUserPosts
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY u.Id
),
UserQuestionDuplicateClosures AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT ph.PostId) AS QuestionsClosedAsDuplicate
    FROM Posts p
    INNER JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1
      AND ph.PostHistoryTypeId = 10 -- Post Closed
      AND ph.Comment IN ('1', '101') -- Specific close reasons for duplicates
      AND ph.Text IS NOT NULL -- The 'Text' field contains JSON for duplicates
    GROUP BY p.OwnerUserId
),
UserTagActivity AS (
    WITH UserTagCounts AS (
        SELECT
            p.OwnerUserId AS UserId,
            TRIM(LOWER(unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')))) AS TagName,
            COUNT(*) AS TagUsageCount
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
          AND p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId, TRIM(LOWER(unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))))
    )
    SELECT
        utc.UserId,
        utc.TagName AS MostActiveTag,
        utc.TagUsageCount
    FROM (
        SELECT
            UserId,
            TagName,
            TagUsageCount,
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagUsageCount DESC, TagName ASC) AS rn
        FROM UserTagCounts
    ) AS utc
    WHERE utc.rn = 1
),
AggregatedUserMetrics AS (
    SELECT
        ups.UserId,
        ups.DisplayName,
        ups.Reputation,
        ups.TotalPosts,
        ups.TotalQuestions,
        ups.TotalAnswers,
        ups.AcceptedAnswersGivenByMe,
        ups.TotalPostScore,
        ups.AvgPostScore,
        ups.TotalViewCount,
        ups.TotalPostCommentCount,
        ups.LatestPostCreation,
        ups.LatestPostActivity,
        COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(uvcs.TotalUpvotesReceivedOnPosts, 0) AS TotalUpvotesReceivedOnPosts,
        COALESCE(uvcs.TotalDownvotesReceivedOnPosts, 0) AS TotalDownvotesReceivedOnPosts,
        COALESCE(uvcs.AverageCommentScoreOnUserPosts, 0.0) AS AverageCommentScoreOnUserPosts,
        COALESCE(uvcs.TotalCommentsOnUserPosts, 0) AS TotalCommentsOnUserPosts,
        COALESCE(uqdc.QuestionsClosedAsDuplicate, 0) AS QuestionsClosedAsDuplicate,
        uta.MostActiveTag,
        uta.TagUsageCount,
        (
            (ups.Reputation * 0.15) +
            (ups.TotalPostScore * 0.05) +
            (ups.AcceptedAnswersGivenByMe * 1.5) +
            (COALESCE(ubs.GoldBadges, 0) * 5) +
            (COALESCE(ubs.SilverBadges, 0) * 2) +
            (COALESCE(ubs.BronzeBadges, 0) * 0.5) +
            (COALESCE(uvcs.TotalUpvotesReceivedOnPosts, 0) * 0.7) -
            (COALESCE(uvcs.TotalDownvotesReceivedOnPosts, 0) * 0.5) +
            (COALESCE(uvcs.AverageCommentScoreOnUserPosts, 0.0) * 0.1) -
            (COALESCE(uqdc.QuestionsClosedAsDuplicate, 0) * 3) +
            (CASE WHEN cast('2024-10-01 12:34:56' as timestamp) - ups.LatestPostActivity < INTERVAL '6 months' THEN 100 ELSE 0 END) +
            (CASE WHEN LENGTH(ups.DisplayName) > 20 THEN 10 ELSE 0 END) +
            (CASE WHEN ups.DisplayName LIKE '%Admin%' OR ups.DisplayName LIKE '%Mod%' THEN 50 ELSE 0 END)
        ) AS CompositeInfluenceScore
    FROM UserPostStats ups
    LEFT JOIN UserBadgeStats ubs ON ups.UserId = ubs.UserId
    LEFT JOIN UserVoteCommentStats uvcs ON ups.UserId = uvcs.UserId
    LEFT JOIN UserQuestionDuplicateClosures uqdc ON ups.UserId = uqdc.UserId
    LEFT JOIN UserTagActivity uta ON ups.UserId = uta.UserId
),
RankedInfluentialUsers AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        AcceptedAnswersGivenByMe,
        TotalPostScore,
        TotalViewCount,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        TotalUpvotesReceivedOnPosts,
        TotalDownvotesReceivedOnPosts,
        AverageCommentScoreOnUserPosts,
        QuestionsClosedAsDuplicate,
        MostActiveTag,
        LatestPostActivity,
        CompositeInfluenceScore,
        RANK() OVER (ORDER BY CompositeInfluenceScore DESC, Reputation DESC, LatestPostActivity DESC) AS InfluenceRank,
        NTILE(100) OVER (ORDER BY CompositeInfluenceScore DESC) AS InfluencePercentile
    FROM AggregatedUserMetrics
)
SELECT
    riu.InfluenceRank,
    riu.DisplayName,
    SUBSTRING(riu.DisplayName, 1, 1) AS DisplayNameInitial,
    riu.Reputation,
    ROUND(riu.CompositeInfluenceScore, 2) AS CompositeInfluenceScore,
    riu.TotalQuestions,
    riu.TotalAnswers,
    riu.AcceptedAnswersGivenByMe,
    riu.TotalPostScore,
    riu.GoldBadges,
    riu.SilverBadges,
    COALESCE(riu.MostActiveTag, 'No Tag Data') AS MostActiveTag,
    COALESCE(CAST(ROUND(riu.AverageCommentScoreOnUserPosts, 2) AS VARCHAR), 'N/A') AS AvgCommentScore,
    riu.TotalUpvotesReceivedOnPosts,
    riu.TotalDownvotesReceivedOnPosts,
    CASE
        WHEN riu.LatestPostActivity IS NULL THEN 'Inactive'
        WHEN cast('2024-10-01 12:34:56' as timestamp) - riu.LatestPostActivity < INTERVAL '1 month' THEN 'Very Active'
        WHEN cast('2024-10-01 12:34:56' as timestamp) - riu.LatestPostActivity < INTERVAL '6 months' THEN 'Active'
        WHEN cast('2024-10-01 12:34:56' as timestamp) - riu.LatestPostActivity < INTERVAL '1 year' THEN 'Moderately Active'
        ELSE 'Less Active'
    END AS ActivityStatus,
    riu.QuestionsClosedAsDuplicate,
    riu.InfluencePercentile
FROM RankedInfluentialUsers riu
WHERE riu.InfluenceRank <= 25
   AND riu.Reputation > 1000
ORDER BY riu.InfluenceRank ASC, riu.Reputation DESC
LIMIT 25;