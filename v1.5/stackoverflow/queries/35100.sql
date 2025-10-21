WITH UserAnswerStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(a.Id) AS TotalAnswers,
        SUM(a.Score) AS TotalAnswerScore,
        COUNT(DISTINCT a.ParentId) AS UniqueQuestionsAnswered,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) AS MinAnswerScore
    FROM Users u
    JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    GROUP BY u.Id, u.DisplayName
),
UserBadges AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
TopTags AS (
    SELECT
        p.OwnerUserId,
        LOWER(tag) AS TagName,
        COUNT(*) AS UsageCount
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS tag
    ) AS t
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId, LOWER(tag)
),
UserTopTag AS (
    SELECT DISTINCT ON (OwnerUserId)
        OwnerUserId,
        TagName,
        UsageCount
    FROM TopTags
    ORDER BY OwnerUserId, UsageCount DESC
),
VoteStats AS (
    SELECT 
        p.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(*) AS TotalVotesReceived
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
)
SELECT
    uas.UserId,
    uas.DisplayName,
    u.Reputation,
    uas.TotalAnswers,
    uas.UniqueQuestionsAnswered,
    uas.TotalAnswerScore,
    uas.MaxAnswerScore,
    uas.MinAnswerScore,
    COALESCE(b.TotalBadges, 0) AS TotalBadges,
    COALESCE(b.GoldBadges, 0) AS GoldBadges,
    COALESCE(b.SilverBadges, 0) AS SilverBadges,
    COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(tt.TagName, '-') AS TopAnsweredTag,
    COALESCE(tt.UsageCount, 0) AS TopTagAnswerCount,
    COALESCE(vs.UpVotesReceived, 0) AS UpVotesReceived,
    COALESCE(vs.DownVotesReceived, 0) AS DownVotesReceived,
    COALESCE(vs.TotalVotesReceived, 0) AS TotalVotesReceived
FROM UserAnswerStats uas
JOIN Users u ON u.Id = uas.UserId
LEFT JOIN UserBadges b ON b.UserId = uas.UserId
LEFT JOIN UserTopTag tt ON tt.OwnerUserId = uas.UserId
LEFT JOIN VoteStats vs ON vs.OwnerUserId = uas.UserId
WHERE uas.TotalAnswers > 50
  AND uas.TotalAnswerScore > 200
  AND u.Reputation > 1000
GROUP BY
    uas.UserId,
    uas.DisplayName,
    u.Reputation,
    uas.TotalAnswers,
    uas.UniqueQuestionsAnswered,
    uas.TotalAnswerScore,
    uas.MaxAnswerScore,
    uas.MinAnswerScore,
    COALESCE(b.TotalBadges, 0),
    COALESCE(b.GoldBadges, 0),
    COALESCE(b.SilverBadges, 0),
    COALESCE(b.BronzeBadges, 0),
    COALESCE(tt.TagName, '-'),
    COALESCE(tt.UsageCount, 0),
    COALESCE(vs.UpVotesReceived, 0),
    COALESCE(vs.DownVotesReceived, 0),
    COALESCE(vs.TotalVotesReceived, 0)
ORDER BY uas.TotalAnswerScore DESC, uas.TotalAnswers DESC
LIMIT 100;