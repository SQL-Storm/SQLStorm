-- {"query": "50024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1024} 
WITH TopTags AS (
    SELECT
        TagName
    FROM Tags
    ORDER BY
        Count DESC
    LIMIT 5
),
UserAnswerStats AS (
    SELECT
        a.OwnerUserId AS UserId,
        tt.TagName,
        SUM(a.Score) AS TotalAnswerScore,
        COUNT(a.Id) AS AnswerCount,
        SUM(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS AcceptedAnswerCount
    FROM Posts q
    JOIN TopTags tt ON q.Tags LIKE '%' || '<' || tt.TagName || '>' || '%'
    JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1
      AND a.PostTypeId = 2
      AND a.OwnerUserId IS NOT NULL
    GROUP BY
        a.OwnerUserId,
        tt.TagName
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        tt.TagName,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    JOIN TopTags tt ON b.Name = tt.TagName
    WHERE
        b.TagBased = TRUE
    GROUP BY
        b.UserId,
        tt.TagName
),
ExpertiseScore AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(uas.TagName, ubs.TagName) AS TagName,
        COALESCE(uas.TotalAnswerScore, 0) AS TotalAnswerScore,
        COALESCE(uas.AnswerCount, 0) AS AnswerCount,
        COALESCE(uas.AcceptedAnswerCount, 0) AS AcceptedAnswerCount,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
        (
            (COALESCE(uas.TotalAnswerScore, 0) * 0.2) +
            (COALESCE(uas.AcceptedAnswerCount, 0) * 20) +
            (COALESCE(ubs.GoldBadges, 0) * 100) +
            (COALESCE(ubs.SilverBadges, 0) * 50) +
            (COALESCE(ubs.BronzeBadges, 0) * 10)
        ) AS Score
    FROM UserAnswerStats uas
    FULL OUTER JOIN UserBadgeStats ubs ON uas.UserId = ubs.UserId AND uas.TagName = ubs.TagName
    JOIN Users u ON u.Id = COALESCE(uas.UserId, ubs.UserId)
),
RankedExperts AS (
    SELECT
        es.*,
        RANK() OVER (PARTITION BY es.TagName ORDER BY es.Score DESC, es.Reputation DESC) AS Rank,
        (
            SELECT MIN(p.CreationDate)
            FROM Posts p
            WHERE p.OwnerUserId = es.UserId
              AND p.Tags LIKE '%' || '<' || es.TagName || '>' || '%'
        ) AS FirstPostDateInTag
    FROM ExpertiseScore es
    WHERE es.Score > 50
)
SELECT
    re.TagName,
    re.Rank,
    re.DisplayName,
    re.Reputation,
    CAST(re.Score AS INT) AS ExpertiseScore,
    re.AnswerCount,
    re.AcceptedAnswerCount,
    re.GoldBadges,
    re.SilverBadges,
    re.BronzeBadges,
    re.FirstPostDateInTag,
    (
        SELECT AVG(c.Score)
        FROM Comments c
        JOIN Posts a ON c.PostId = a.Id
        JOIN Posts q ON a.ParentId = q.Id
        WHERE a.OwnerUserId = re.UserId
          AND q.Tags LIKE '%' || '<' || re.TagName || '>' || '%'
    ) AS AvgCommentScoreOnAnswers
FROM RankedExperts re
WHERE re.Rank <= 10
ORDER BY
    re.TagName,
    re.Rank;