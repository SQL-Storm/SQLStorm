-- {"query": "50009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1051} 

WITH UserPostStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalViewCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.FavoriteCount ELSE 0 END) AS TotalFavoriteCount,
        COUNT(q.AcceptedAnswerId) AS AcceptedAnswerCount,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    LEFT JOIN Posts q ON p.Id = q.AcceptedAnswerId AND p.PostTypeId = 2
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.TotalQuestionScore,
        ups.TotalAnswerScore,
        ups.TotalViewCount,
        ups.AcceptedAnswerCount,
        (ups.LastPostDate - ups.FirstPostDate) AS UserActivePeriod,
        (
            SELECT COUNT(*)
            FROM Badges b
            WHERE b.UserId = u.Id AND b.Class = 1
        ) AS GoldBadges,
        (
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.UserId = u.Id
        ) AS CommentCount,
        (
            SELECT SUM(v.BountyAmount)
            FROM Votes v
            WHERE v.UserId = u.Id AND v.VoteTypeId = 8
        ) AS TotalBountyGiven
    FROM Users u
    JOIN UserPostStats ups ON u.Id = ups.OwnerUserId
    WHERE u.Reputation > 75000 AND ups.AnswerCount > ups.QuestionCount AND u.Location IS NOT NULL AND u.Location != ''
),
RankedUsers AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY Location
            ORDER BY Reputation DESC, GoldBadges DESC
        ) as LocationRank
    FROM UserEngagement
    WHERE GoldBadges > 10 AND AcceptedAnswerCount > 50
)
SELECT
    ru.DisplayName,
    ru.Location,
    ru.Reputation,
    ru.LocationRank,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.AcceptedAnswerCount,
    CAST(ru.AcceptedAnswerCount AS REAL) / ru.AnswerCount AS AcceptanceRatio,
    ru.TotalViewCount,
    (ru.TotalQuestionScore + ru.TotalAnswerScore) AS TotalScore,
    ru.CommentCount,
    ru.GoldBadges,
    ru.TotalBountyGiven,
    ru.UserActivePeriod,
    p_last.Title AS LastQuestionTitle,
    p_last.CreationDate AS LastQuestionDate,
    (
        SELECT STRING_AGG(t.TagName, ', ')
        FROM Posts p_tags
        CROSS JOIN UNNEST(string_to_array(substring(p_tags.Tags, 2, length(p_tags.Tags)-2), '><')) AS tag_name
        JOIN Tags t ON t.TagName = tag_name
        WHERE p_tags.OwnerUserId = ru.UserId AND p_tags.PostTypeId = 1
        GROUP BY p_tags.OwnerUserId
        ORDER BY COUNT(*) DESC
        LIMIT 1
    ) AS MostUsedTag
FROM RankedUsers ru
LEFT JOIN LATERAL (
    SELECT p.Title, p.CreationDate
    FROM Posts p
    WHERE p.OwnerUserId = ru.UserId AND p.PostTypeId = 1
    ORDER BY p.CreationDate DESC
    LIMIT 1
) p_last ON TRUE
WHERE ru.LocationRank <= 5 AND EXISTS (
    SELECT 1
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE p.OwnerUserId = ru.UserId
      AND ph.PostHistoryTypeId = 10 -- Post Closed
      AND ph.Comment = '101' -- Duplicate
)
ORDER BY ru.Location, ru.LocationRank;
