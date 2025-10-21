-- {"query": "50076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 845} 

WITH UserTagActivity AS (
    SELECT
        a.OwnerUserId,
        t.TagName,
        SUM(a.Score) AS TotalAnswerScore,
        COUNT(CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 END) AS AcceptedAnswersCount,
        SUM(q.ViewCount) AS TotalQuestionViews
    FROM
        Posts AS a
    JOIN
        Posts AS q ON a.ParentId = q.Id
    CROSS JOIN LATERAL
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS t(TagName)
    WHERE
        a.PostTypeId = 2 -- Answer
        AND q.PostTypeId = 1 -- Question
        AND a.OwnerUserId IS NOT NULL
    GROUP BY
        a.OwnerUserId,
        t.TagName
),
UserTagBadges AS (
    SELECT
        b.UserId,
        b.Name AS TagName,
        SUM(CASE b.Class
            WHEN 1 THEN 15 -- Gold
            WHEN 2 THEN 5  -- Silver
            WHEN 3 THEN 1  -- Bronze
            ELSE 0
        END) AS BadgeWeight
    FROM
        Badges AS b
    WHERE
        b.TagBased = TRUE
    GROUP BY
        b.UserId,
        b.Name
),
UserInfluence AS (
    SELECT
        uta.OwnerUserId,
        u.DisplayName,
        u.Reputation,
        uta.TagName,
        (uta.TotalAnswerScore * 0.4) + (uta.AcceptedAnswersCount * 20) + (uta.TotalQuestionViews / 500.0) + COALESCE(utb.BadgeWeight, 0) AS InfluenceScore,
        uta.TotalAnswerScore,
        uta.AcceptedAnswersCount,
        uta.TotalQuestionViews,
        COALESCE(utb.BadgeWeight, 0) AS BadgeScore
    FROM
        UserTagActivity uta
    JOIN
        Users u ON uta.OwnerUserId = u.Id
    LEFT JOIN
        UserTagBadges utb ON uta.OwnerUserId = utb.UserId AND uta.TagName = utb.TagName
    WHERE u.Reputation > 1000
),
RankedInfluence AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY TagName ORDER BY InfluenceScore DESC, Reputation DESC) as RankInTag
    FROM
        UserInfluence
)
SELECT
    ri.TagName,
    ri.RankInTag,
    ri.DisplayName,
    ri.Reputation,
    CAST(ri.InfluenceScore AS integer) AS InfluenceScore,
    ri.TotalAnswerScore,
    ri.AcceptedAnswersCount,
    ri.TotalQuestionViews,
    ri.BadgeScore,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = ri.OwnerUserId AND c.Score > 5) AS HighScoreCommentCount,
    (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.UserId = ri.OwnerUserId AND ph.PostHistoryTypeId IN (4, 5, 6)) AS LastEditActivity
FROM
    RankedInfluence ri
JOIN
    Tags t ON ri.TagName = t.TagName
WHERE
    ri.RankInTag <= 10
    AND t.Count > 5000 -- Only consider tags with significant activity
    AND ri.TagName IN ( -- Only include tags where at least one of the top 10 users has received a 'gold' tag badge for it
        SELECT DISTINCT Name FROM Badges WHERE Class = 1 AND TagBased = TRUE
    )
ORDER BY
    ri.TagName,
    ri.RankInTag;
