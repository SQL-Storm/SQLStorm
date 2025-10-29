-- {"query": "3083.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1854}
WITH UserAggregates AS (
    SELECT
        u.Id                                            AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, '[unknown]')               AS Location,
        /* badge counts per class */
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        /* post counts */
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        /* total up-votes (derived from Users table) */
        u.UpVotes                                        AS TotalUpVotes,
        /* most recent activity */
        (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostDate
    FROM Users u
),
RankedUsers AS (
    SELECT
        ua.*,
        ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC, ua.GoldBadges DESC, ua.SilverBadges DESC) AS RN
    FROM UserAggregates ua
    WHERE ua.Reputation IS NOT NULL
)
SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.GoldBadges,
    ru.SilverBadges,
    ru.BronzeBadges,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.TotalUpVotes,
    ru.LastPostDate,
    COALESCE(latest.Title, 'No Recent Post')                             AS RecentPostTitle,
    CASE
        WHEN latest.Score IS NULL THEN 'No Score'
        WHEN latest.Score > 0     THEN 'Positive'
        WHEN latest.Score = 0     THEN 'Neutral'
        ELSE                         'Negative'
    END                                                                 AS RecentPostScoreCategory,
    COALESCE(string_agg(t.TagName, ', '), '')                           AS RecentPostTags
FROM RankedUsers ru
LEFT JOIN LATERAL (
    SELECT p.Id, p.Title, p.Score, p.Tags
    FROM Posts p
    WHERE p.OwnerUserId = ru.UserId
    ORDER BY p.CreationDate DESC
    LIMIT 1
) latest ON TRUE
LEFT JOIN LATERAL (
    SELECT UNNEST(string_to_array(SUBSTRING(latest.Tags FROM 2 FOR CHAR_LENGTH(latest.Tags)-2), '><')) AS Tag
) taglist ON TRUE
LEFT JOIN Tags t ON t.TagName = taglist.Tag
GROUP BY
    ru.UserId, ru.DisplayName, ru.Reputation, ru.GoldBadges,
    ru.SilverBadges, ru.BronzeBadges, ru.QuestionCount, ru.AnswerCount,
    ru.TotalUpVotes, ru.LastPostDate, latest.Title, latest.Score
HAVING COUNT(t.TagName) >= 0
UNION ALL
SELECT
    NULL                        AS UserId,
    'Aggregated Totals'         AS DisplayName,
    SUM(Reputation)             AS Reputation,
    SUM(GoldBadges)             AS GoldBadges,
    SUM(SilverBadges)           AS SilverBadges,
    SUM(BronzeBadges)           AS BronzeBadges,
    SUM(QuestionCount)          AS QuestionCount,
    SUM(AnswerCount)            AS AnswerCount,
    SUM(TotalUpVotes)           AS TotalUpVotes,
    NULL                        AS LastPostDate,
    NULL                        AS RecentPostTitle,
    NULL                        AS RecentPostScoreCategory,
    NULL                        AS RecentPostTags
FROM RankedUsers
WHERE RN <= 1000
ORDER BY Reputation DESC NULLS LAST
LIMIT 2000;