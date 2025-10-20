WITH TopUsersByReputation AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    WHERE u.Reputation > 10000
    -- LIMIT moved to outer query or handled by caller for compatibility; remove here
),
UserPostMetrics AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswers
    FROM Posts p
    WHERE p.OwnerUserId IN (SELECT Id FROM TopUsersByReputation)
        AND p.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY p.OwnerUserId
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(CASE WHEN b.TagBased = TRUE THEN 1 END) AS TagBasedBadges
    FROM Badges b
    WHERE b.UserId IN (SELECT Id FROM TopUsersByReputation)
    GROUP BY b.UserId
),
UserInteractionMetrics AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvotesCast,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownvotesCast,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoritesCast,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount, 0) ELSE 0 END) AS TotalBountyOffered
    FROM Votes v
    WHERE v.UserId IN (SELECT Id FROM TopUsersByReputation)
        AND v.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY v.UserId
),
PostEngagementMetrics AS (
    SELECT 
        p.OwnerUserId,
        AVG(p.CommentCount) AS AvgCommentsPerPost,
        AVG(p.FavoriteCount) AS AvgFavoritesPerPost,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.OwnerUserId IN (SELECT Id FROM TopUsersByReputation)
        AND p.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY p.OwnerUserId
),
TagExpertise AS (
    SELECT 
        sub.OwnerUserId,
        sub.tag AS Tag,
        COUNT(*) AS TagUsageCount,
        AVG(sub.Score) AS AvgScoreInTag
    FROM (
        SELECT p.OwnerUserId, p.Score,
               TRIM(x) AS tag
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT UNNEST(string_to_array(REPLACE(REPLACE(p.Tags, '<', ''), '>', '|'), '|')) AS x
        ) AS t
        WHERE p.OwnerUserId IN (SELECT Id FROM TopUsersByReputation)
            AND p.PostTypeId = 1
            AND p.Tags IS NOT NULL
            AND p.CreationDate >= TIMESTAMP '2020-01-01'
    ) sub
    GROUP BY sub.OwnerUserId, sub.tag
),
TopTagsPerUser AS (
    SELECT 
        OwnerUserId,
        Tag,
        TagUsageCount,
        AvgScoreInTag,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY TagUsageCount DESC, AvgScoreInTag DESC) AS TagRank
    FROM TagExpertise
)
SELECT 
    tu.Id AS UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.ReputationRank,
    EXTRACT(DAY FROM (TIMESTAMP '2024-10-01 12:34:56' - tu.CreationDate)) AS AccountAgeDays,
    COALESCE(upm.QuestionCount, 0) AS QuestionsAsked,
    COALESCE(upm.AnswerCount, 0) AS AnswersGiven,
    ROUND(COALESCE(upm.AvgQuestionScore, 0), 2) AS AvgQuestionScore,
    ROUND(COALESCE(upm.AvgAnswerScore, 0), 2) AS AvgAnswerScore,
    COALESCE(upm.TotalViews, 0) AS TotalViewsOnPosts,
    COALESCE(upm.QuestionsWithAcceptedAnswers, 0) AS QuestionsWithAccepted,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadgeCount,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadgeCount,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadgeCount,
    COALESCE(ubs.TagBasedBadges, 0) AS TagBasedBadgeCount,
    COALESCE(uim.UpvotesCast, 0) AS UpvotesCast,
    COALESCE(uim.DownvotesCast, 0) AS DownvotesCast,
    COALESCE(uim.TotalBountyOffered, 0) AS BountyPointsOffered,
    ROUND(COALESCE(pem.AvgCommentsPerPost, 0), 2) AS AvgCommentsPerPost,
    ROUND(COALESCE(pem.AvgFavoritesPerPost, 0), 2) AS AvgFavoritesPerPost,
    COALESCE(pem.TotalComments, 0) AS TotalCommentsReceived,
    STRING_AGG(ttp.Tag || ':' || CAST(ttp.TagUsageCount AS VARCHAR), ', ' ORDER BY ttp.Tag || ':' || CAST(ttp.TagUsageCount AS VARCHAR)) 
        FILTER (WHERE ttp.TagRank <= 5) AS Top5Tags,
    CASE 
        WHEN COALESCE(upm.AnswerCount, 0) > COALESCE(upm.QuestionCount, 0) * 3 THEN 'Answer-Focused'
        WHEN COALESCE(upm.QuestionCount, 0) > COALESCE(upm.AnswerCount, 0) * 3 THEN 'Question-Focused'
        ELSE 'Balanced'
    END AS UserActivityType
FROM TopUsersByReputation tu
LEFT JOIN UserPostMetrics upm ON tu.Id = upm.OwnerUserId
LEFT JOIN UserBadgeStats ubs ON tu.Id = ubs.UserId
LEFT JOIN UserInteractionMetrics uim ON tu.Id = uim.UserId
LEFT JOIN PostEngagementMetrics pem ON tu.Id = pem.OwnerUserId
LEFT JOIN TopTagsPerUser ttp ON tu.Id = ttp.OwnerUserId AND ttp.TagRank <= 5
GROUP BY 
    tu.Id, tu.DisplayName, tu.Reputation, tu.ReputationRank, tu.CreationDate,
    upm.QuestionCount, upm.AnswerCount, upm.AvgQuestionScore, upm.AvgAnswerScore,
    upm.TotalViews, upm.QuestionsWithAcceptedAnswers,
    ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.TagBasedBadges,
    uim.UpvotesCast, uim.DownvotesCast, uim.TotalBountyOffered,
    pem.AvgCommentsPerPost, pem.AvgFavoritesPerPost, pem.TotalComments, pem.AvgCommentScore,
    ttp.Tag, ttp.TagUsageCount, ttp.AvgScoreInTag, ttp.TagRank
HAVING COUNT(DISTINCT ttp.Tag) > 0
ORDER BY tu.Reputation DESC, upm.AnswerCount DESC
LIMIT 500;