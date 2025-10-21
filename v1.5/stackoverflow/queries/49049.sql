-- {"query": "49049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1831} 
WITH UserOverallPostActivity AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers, -- Questions asked by user with an accepted answer
        SUM(p.Score) AS TotalPostScore,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) AS AvgQuestionViewCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.FavoriteCount END) AS TotalQuestionFavoriteCount,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        SUM(CASE WHEN q_accepted.AcceptedAnswerId = p.Id AND p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AcceptedAnswersGivenByThisUser -- Answers by this user that were accepted
    FROM Posts p
    LEFT JOIN Posts q_accepted ON p.PostTypeId = 2 AND p.Id = q_accepted.AcceptedAnswerId -- Join to find questions that accepted *this* answer
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentSummary AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserHistoryActivity AS (
    SELECT
        ph.UserId,
        COUNT(ph.Id) AS TotalHistoryEntries,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN ph.Id END) AS EditHistoryEntries, -- Specific edit types including rollbacks
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 12) THEN ph.Id END) AS CloseDeleteHistoryEntries -- Close/Delete votes/actions
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserTagDominance AS (
    SELECT
        u.Id AS UserId,
        t.TagName,
        COUNT(pt.TagName) AS TagUsageCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(pt.TagName) DESC, t.Count DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN LATERAL (SELECT UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS TagName) AS pt ON TRUE
    JOIN Tags t ON pt.TagName = t.TagName
    WHERE p.PostTypeId = 1 -- Only consider questions for tags
    AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 -- Ensure tags exist and are not empty
    GROUP BY u.Id, t.TagName, t.Count
),
TopUserTags AS (
    SELECT
        UserId,
        MAX(CASE WHEN TagRank = 1 THEN TagName END) AS TopTag1,
        MAX(CASE WHEN TagRank = 1 THEN TagUsageCount END) AS TopTag1Count,
        MAX(CASE WHEN TagRank = 2 THEN TagName END) AS TopTag2,
        MAX(CASE WHEN TagRank = 2 THEN TagUsageCount END) AS TopTag2Count,
        MAX(CASE WHEN TagRank = 3 THEN TagName END) AS TopTag3,
        MAX(CASE WHEN TagRank = 3 THEN TagUsageCount END) AS TopTag3Count
    FROM UserTagDominance
    WHERE TagRank <= 3
    GROUP BY UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    COALESCE(u.Views, 0) AS UserProfileViews,
    COALESCE(u.UpVotes, 0) AS UserUpVotes,
    COALESCE(u.DownVotes, 0) AS UserDownVotes,
    COALESCE(ua.QuestionCount, 0) AS QuestionCount,
    COALESCE(ua.AnswerCount, 0) AS AnswerCount,
    COALESCE(ua.AcceptedAnswersGivenByThisUser, 0) AS AcceptedAnswersGiven,
    ROUND(CAST(COALESCE(ua.AcceptedAnswersGivenByThisUser, 0) AS NUMERIC) / NULLIF(COALESCE(ua.AnswerCount, 0), 0) * 100, 2) AS AcceptedAnswerRatio,
    COALESCE(ua.TotalPostScore, 0) AS TotalPostScore,
    COALESCE(uc.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(uh.EditHistoryEntries, 0) AS EditHistoryCount,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    (
        COALESCE(ua.QuestionCount, 0) * 5 +
        COALESCE(ua.AnswerCount, 0) * 3 +
        COALESCE(ua.AcceptedAnswersGivenByThisUser, 0) * 10 +
        COALESCE(ua.TotalPostScore, 0) +
        COALESCE(uc.TotalCommentScore, 0) / 2 +
        COALESCE(uh.EditHistoryEntries, 0) +
        COALESCE(ub.GoldBadges, 0) * 50 +
        COALESCE(ub.SilverBadges, 0) * 20 +
        COALESCE(ub.BronzeBadges, 0) * 5
    ) AS EngagementScore, -- Custom weighted metric
    t.TopTag1,
    t.TopTag1Count,
    t.TopTag2,
    t.TopTag2Count,
    t.TopTag3,
    t.TopTag3Count,
    AGE(cast('2024-10-01 12:34:56' as timestamp), u.CreationDate) AS AccountAge,
    EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / (60 * 60 * 24) AS DaysActiveSinceCreation -- Days between last access and creation
FROM Users u
LEFT JOIN UserOverallPostActivity ua ON u.Id = ua.UserId
LEFT JOIN UserCommentSummary uc ON u.Id = uc.UserId
LEFT JOIN UserHistoryActivity uh ON u.Id = uh.UserId
LEFT JOIN UserBadgeSummary ub ON u.Id = ub.UserId
LEFT JOIN TopUserTags t ON u.Id = t.UserId
WHERE
    u.Reputation > 500 -- Filter for reasonably active users
    AND u.LastAccessDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months' -- Recently active users
    AND (COALESCE(ua.QuestionCount, 0) > 2 OR COALESCE(ua.AnswerCount, 0) > 5) -- Must have some significant post contribution
ORDER BY
    EngagementScore DESC,
    u.Reputation DESC,
    COALESCE(ua.AcceptedAnswersGivenByThisUser, 0) DESC
LIMIT 250;