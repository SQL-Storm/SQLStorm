WITH RecentHighReputationUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > 50000
      AND CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3' YEAR
),
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    WHERE b.UserId IN (SELECT Id FROM RecentHighReputationUsers)
    GROUP BY b.UserId
),
UserQuestions AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) AS TotalQuestions,
        AVG(p.Score) AS AvgQuestionScore,
        SUM(p.ViewCount) AS TotalQuestionViews,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.PostId END) AS TotalClosedQuestions
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IN (SELECT Id FROM RecentHighReputationUsers)
    GROUP BY p.OwnerUserId
),
UserAnswers AS (
    SELECT 
        p.OwnerUserId,
        COUNT(*) AS TotalAnswers,
        AVG(p.Score) AS AvgAnswerScore,
        COUNT(DISTINCT p.AcceptedAnswerId) AS AcceptedAnswers
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.OwnerUserId IN (SELECT Id FROM RecentHighReputationUsers)
    GROUP BY p.OwnerUserId
),
TopTagsPerUser AS (
    SELECT 
        u.Id AS UserId,
        tag,
        COUNT(*) AS TagUsage
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    CROSS JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(REGEXP_REPLACE(COALESCE(p.Tags, ''), '[<>]', '', 'g'), ',')) AS tag
    ) t
    WHERE u.Id IN (SELECT Id FROM RecentHighReputationUsers)
      AND p.PostTypeId = 1
    GROUP BY u.Id, tag
),
TopThreeTags AS (
    SELECT UserId, tag, TagUsage,
           ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagUsage DESC) AS rn
    FROM TopTagsPerUser
),
UserVotesAndComments AS (
    SELECT
        v.UserId,
        COUNT(DISTINCT CASE WHEN vt.Name IN ('UpMod', 'DownMod') THEN v.Id END) AS VoteCount,
        COUNT(DISTINCT c.Id) AS CommentCount
    FROM Votes v
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN Comments c ON c.UserId = v.UserId
    WHERE v.UserId IN (SELECT Id FROM RecentHighReputationUsers)
    GROUP BY v.UserId
)
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(ubs.GoldBadges,0) AS GoldBadges,
    COALESCE(ubs.SilverBadges,0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges,0) AS BronzeBadges,
    COALESCE(us.TotalQuestions,0) AS TotalQuestions,
    COALESCE(us.AvgQuestionScore,0) AS AvgQuestionScore,
    COALESCE(us.TotalQuestionViews,0) AS TotalQuestionViews,
    COALESCE(us.TotalClosedQuestions,0) AS TotalClosedQuestions,
    COALESCE(ua.TotalAnswers,0) AS TotalAnswers,
    COALESCE(ua.AvgAnswerScore,0) AS AvgAnswerScore,
    COALESCE(ua.AcceptedAnswers,0) AS AcceptedAnswers,
    COALESCE(uv.VoteCount,0) AS TotalVotesCast,
    COALESCE(uv.CommentCount,0) AS TotalCommentsMade,
    STRING_AGG(t3.tag, ', ' ORDER BY t3.TagUsage DESC) AS TopTags
FROM RecentHighReputationUsers u
LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
LEFT JOIN UserQuestions us ON u.Id = us.OwnerUserId
LEFT JOIN UserAnswers ua ON u.Id = ua.OwnerUserId
LEFT JOIN UserVotesAndComments uv ON u.Id = uv.UserId
LEFT JOIN (
    SELECT UserId, tag, TagUsage
    FROM TopThreeTags
    WHERE rn <= 3
) t3 ON u.Id = t3.UserId
GROUP BY u.Id, u.DisplayName, u.Reputation, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, us.TotalQuestions, us.AvgQuestionScore, us.TotalQuestionViews, us.TotalClosedQuestions, ua.TotalAnswers, ua.AvgAnswerScore, ua.AcceptedAnswers, uv.VoteCount, uv.CommentCount
ORDER BY u.Reputation DESC
LIMIT 20;