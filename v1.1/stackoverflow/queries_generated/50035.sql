-- {"query": "50035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 933} 

WITH PopularTags AS (
    SELECT TagName
    FROM Tags
    ORDER BY Count DESC
    LIMIT 20
),
QuestionTags AS (
    SELECT
        Id AS QuestionId,
        unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName
    FROM Posts
    WHERE PostTypeId = 1 AND Tags IS NOT NULL
),
UserAnswerStats AS (
    SELECT
        a.OwnerUserId,
        qt.TagName,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AverageAnswerScore,
        SUM(a.CommentCount) AS TotalAnswerCommentCount,
        SUM(v.VoteCount) AS TotalUpVotes
    FROM Posts AS a
    INNER JOIN Posts AS q ON a.ParentId = q.Id
    INNER JOIN QuestionTags AS qt ON q.Id = qt.QuestionId
    INNER JOIN PopularTags AS pt ON qt.TagName = pt.TagName
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VoteCount
        FROM Votes
        WHERE VoteTypeId = 2 -- UpMod
        GROUP BY PostId
    ) AS v ON a.Id = v.PostId
    WHERE
        a.PostTypeId = 2
        AND a.OwnerUserId IS NOT NULL
        AND a.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '5 year')
    GROUP BY
        a.OwnerUserId,
        qt.TagName
    HAVING
        COUNT(a.Id) > 10 AND AVG(a.Score) > 2
),
UserBadgeStats AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        uas.TagName,
        uas.AnswerCount,
        uas.AverageAnswerScore,
        uas.TotalUpVotes,
        COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
        COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
        -- Calculate a composite influence score
        (uas.AverageAnswerScore * ln(uas.AnswerCount + 1) + u.Reputation / 1000.0 + COALESCE(ubs.GoldBadges, 0) * 10) AS InfluenceScore
    FROM UserAnswerStats AS uas
    INNER JOIN Users AS u ON uas.OwnerUserId = u.Id
    LEFT JOIN UserBadgeStats AS ubs ON u.Id = ubs.UserId
    WHERE u.Reputation > 5000
),
RankedExperts AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY TagName
            ORDER BY InfluenceScore DESC, Reputation DESC
        ) AS RankInTag
    FROM UserActivitySummary
)
SELECT
    re.TagName,
    re.RankInTag,
    re.DisplayName,
    re.Reputation,
    re.AnswerCount,
    CAST(re.AverageAnswerScore AS DECIMAL(10, 2)) AS AvgAnswerScore,
    re.TotalUpVotes,
    re.GoldBadges,
    re.SilverBadges,
    ph.LastEditDate AS LastPostEditDate,
    EXTRACT(YEAR FROM AGE(CURRENT_TIMESTAMP, re.UserCreationDate)) AS AccountAgeYears
FROM RankedExperts AS re
LEFT JOIN LATERAL (
    SELECT p.LastEditDate
    FROM Posts p
    WHERE p.OwnerUserId = re.UserId
    ORDER BY p.LastActivityDate DESC
    LIMIT 1
) AS ph ON true
WHERE re.RankInTag <= 5
ORDER BY
    re.TagName,
    re.RankInTag;
