-- {"query": "49072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1650} 

WITH TopPopularTags AS (
    SELECT
        unnested_tag AS TagName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(p.ViewCount) AS TotalViewCount
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS unnested_tag
    WHERE p.PostTypeId = 1 -- Questions
      AND p.Tags IS NOT NULL
      AND p.Tags != ''
      AND p.ViewCount > 0
    GROUP BY unnested_tag
    HAVING COUNT(DISTINCT p.Id) > 500 -- Minimum questions for a tag to be considered popular
    ORDER BY QuestionCount DESC, TotalViewCount DESC
    LIMIT 200 -- Top N most popular tags
),
UserAnswerPerformance AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS TotalAnswers,
        COALESCE(AVG(p.Score), 0) AS AvgAnswerScore,
        SUM(CASE WHEN q.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoriteCountOnAnswers,
        SUM(CASE WHEN EXISTS (
            SELECT 1
            FROM TopPopularTags tpt
            CROSS JOIN LATERAL unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS q_tag
            WHERE q.Id = p.ParentId AND q_tag = tpt.TagName
        ) THEN 1 ELSE 0 END) AS AnswersToPopularTagsCount,
        COUNT(DISTINCT ph.Id) AS TotalAnswerEdits, -- Count of unique edit history records for their answers
        SUM(CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END) AS CommunityOwnedAnswers
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN Posts q ON p.ParentId = q.Id AND q.PostTypeId = 1 -- Join to parent question
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 8, 24) -- Edit Body, Rollback Body, Suggested Edit Applied
    WHERE p.PostTypeId = 2 -- Answers
      AND p.CreationDate >= '2020-01-01' -- Focus on recent activity
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) >= 10 -- Minimum 10 answers to be considered
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    uap.TotalAnswers,
    uap.AvgAnswerScore,
    uap.AcceptedAnswerCount,
    uap.TotalFavoriteCountOnAnswers,
    uap.AnswersToPopularTagsCount,
    COALESCE(ubs.TotalBadges, 0) AS TotalBadges,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    uap.TotalAnswerEdits,
    uap.CommunityOwnedAnswers,
    (
        (u.Reputation / 1000.0) * 1.0 +
        (uap.AvgAnswerScore * 0.75) +
        (uap.AcceptedAnswerCount * 3.0) +
        (uap.TotalFavoriteCountOnAnswers * 0.15) +
        (uap.AnswersToPopularTagsCount * 2.0) +
        (COALESCE(ubs.GoldBadges, 0) * 15.0) +
        (COALESCE(ubs.SilverBadges, 0) * 7.5) +
        (COALESCE(ubs.BronzeBadges, 0) * 1.5) +
        (uap.TotalAnswerEdits * 0.08) +
        (uap.CommunityOwnedAnswers * 1.0)
    ) AS InfluenceScore,
    NTILE(5) OVER (ORDER BY (
        (u.Reputation / 1000.0) * 1.0 +
        (uap.AvgAnswerScore * 0.75) +
        (uap.AcceptedAnswerCount * 3.0) +
        (uap.TotalFavoriteCountOnAnswers * 0.15) +
        (uap.AnswersToPopularTagsCount * 2.0) +
        (COALESCE(ubs.GoldBadges, 0) * 15.0) +
        (COALESCE(ubs.SilverBadges, 0) * 7.5) +
        (COALESCE(ubs.BronzeBadges, 0) * 1.5) +
        (uap.TotalAnswerEdits * 0.08) +
        (uap.CommunityOwnedAnswers * 1.0)
    ) DESC) AS InfluenceQuintileRank,
    RANK() OVER (ORDER BY (
        (u.Reputation / 1000.0) * 1.0 +
        (uap.AvgAnswerScore * 0.75) +
        (uap.AcceptedAnswerCount * 3.0) +
        (uap.TotalFavoriteCountOnAnswers * 0.15) +
        (uap.AnswersToPopularTagsCount * 2.0) +
        (COALESCE(ubs.GoldBadges, 0) * 15.0) +
        (COALESCE(ubs.SilverBadges, 0) * 7.5) +
        (COALESCE(ubs.BronzeBadges, 0) * 1.5) +
        (uap.TotalAnswerEdits * 0.08) +
        (uap.CommunityOwnedAnswers * 1.0)
    ) DESC) AS OverallInfluenceRank
FROM Users u
JOIN UserAnswerPerformance uap ON u.Id = uap.UserId
LEFT JOIN UserBadgeSummary ubs ON u.Id = ubs.UserId
WHERE u.Reputation >= 2500
  AND uap.TotalAnswers >= 25
  AND uap.AcceptedAnswerCount >= 5
ORDER BY InfluenceScore DESC, u.Reputation DESC
LIMIT 500;
