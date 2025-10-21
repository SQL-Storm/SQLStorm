WITH UserReputationRanks AS (
    SELECT
        Id,
        Reputation,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) as ReputationRank
    FROM Users
),
QuestionStats AS (
    SELECT
        p.Id as QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        COUNT(DISTINCT a.Id) FILTER (WHERE a.PostTypeId = 2) as ActualAnswerCount,
        AVG(a.Score) FILTER (WHERE a.PostTypeId = 2) as AvgAnswerScore,
        MAX(a.Score) FILTER (WHERE a.PostTypeId = 2) as MaxAnswerScore,
        COUNT(DISTINCT c.Id) as CommentCount
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.Tags
),
UserBadgeCounts AS (
    SELECT
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE Class = 3) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges
    GROUP BY UserId
),
TopTags AS (
    SELECT
        Tag,
        COUNT(*) AS TagCount
    FROM (
        SELECT unnest(string_to_array(substring(Tags, 2, length(Tags) - 2), '><')) AS Tag
        FROM Posts
        WHERE PostTypeId = 1 AND Tags IS NOT NULL
    ) t
    GROUP BY Tag
    ORDER BY TagCount DESC
    LIMIT 10
),
PostLinkCounts AS (
    SELECT
        PostId,
        COUNT(*) FILTER (WHERE LinkTypeId = 1) AS LinkedCount,
        COUNT(*) FILTER (WHERE LinkTypeId = 3) AS DuplicateCount
    FROM PostLinks
    GROUP BY PostId
),
UserActivitySummary AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId IN (2,3)) AS VotesCast
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id
),
ComplexPosts AS (
    SELECT
        q.QuestionId,
        q.OwnerUserId,
        ur.Reputation,
        ur.ReputationRank,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.ActualAnswerCount,
        q.AvgAnswerScore,
        q.MaxAnswerScore,
        q.CommentCount,
        plc.LinkedCount,
        plc.DuplicateCount,
        uas.QuestionsAsked,
        uas.AnswersGiven,
        uas.CommentsMade,
        uas.VotesCast,
        tt.Tag
    FROM QuestionStats q
    INNER JOIN UserReputationRanks ur ON ur.Id = q.OwnerUserId
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = q.OwnerUserId
    LEFT JOIN PostLinkCounts plc ON plc.PostId = q.QuestionId
    LEFT JOIN UserActivitySummary uas ON uas.UserId = q.OwnerUserId
    LEFT JOIN LATERAL (
        SELECT Tag
        FROM (SELECT unnest(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><')) AS Tag) AS t
        WHERE t.Tag IN (SELECT Tag FROM TopTags)
        LIMIT 1
    ) tt ON true
    WHERE q.AnswerCount >= 3
      AND q.ViewCount > 1000
      AND q.Score >= 5
      AND ur.ReputationRank <= 1000
)
SELECT
    cp.QuestionId,
    u.DisplayName AS QuestionOwner,
    cp.Reputation,
    cp.ReputationRank,
    cp.GoldBadges,
    cp.SilverBadges,
    cp.BronzeBadges,
    cp.Score AS QuestionScore,
    cp.ViewCount,
    cp.AnswerCount,
    cp.ActualAnswerCount,
    ROUND(cp.AvgAnswerScore,2) AS AvgAnswerScore,
    cp.MaxAnswerScore,
    cp.CommentCount,
    cp.LinkedCount,
    cp.DuplicateCount,
    cp.QuestionsAsked,
    cp.AnswersGiven,
    cp.CommentsMade,
    cp.VotesCast,
    cp.Tag
FROM ComplexPosts cp
JOIN Users u ON u.Id = cp.OwnerUserId
ORDER BY cp.Score DESC, cp.ViewCount DESC
LIMIT 50;