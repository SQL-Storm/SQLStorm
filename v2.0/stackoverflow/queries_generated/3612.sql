-- {"query": "3612.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1987} 

WITH UserAgg AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, '[unknown]')                              AS Location,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)                    AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)                    AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2))              AS AvgScore,
        MAX(p.CreationDate)                                            AS LastPostDate,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)                  AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)                  AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)                  AS BronzeBadges,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2)                   AS UpVoteCount,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3)                   AS DownVoteCount
    FROM Users u
    LEFT JOIN Posts   p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges  b ON b.UserId     = u.Id
    LEFT JOIN Votes   v ON v.UserId     = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
TagStats AS (
    SELECT 
        t.TagName,
        t.Count                                 AS TagUseCount,
        COALESCE(e.Title, '')                   AS ExcerptTitle,
        COALESCE(w.Title, '')                   AS WikiTitle,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
    WHERE t.TagName IS NOT NULL
)
SELECT
    ua.Id,
    ua.DisplayName,
    ua.Reputation,
    ua.Location,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.AvgScore,
    ua.LastPostDate,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.UpVoteCount,
    ua.DownVoteCount,
    COALESCE((
        SELECT STRING_AGG(DISTINCT TRIM(BOTH '><' FROM ph.Text), ';')
        FROM PostHistory ph
        WHERE ph.PostId = (
            SELECT p.Id
            FROM Posts p
            WHERE p.OwnerUserId = ua.Id
              AND p.PostTypeId = 1
            ORDER BY p.CreationDate DESC
            LIMIT 1
        )
          AND ph.PostHistoryTypeId = 5
    ), '[no edits]')                                   AS RecentEditSnippets,
    ROW_NUMBER() OVER (
        ORDER BY (ua.Reputation 
                  + ua.GoldBadges   * 1000 
                  + ua.SilverBadges * 500 
                  + ua.BronzeBadges * 100) DESC
    )                                                  AS UserScoreRank
FROM UserAgg ua
WHERE ua.Reputation > 1000
  AND (ua.QuestionCount > 0 OR ua.AnswerCount > 0)

UNION ALL

SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(u.Location, '[unknown]')                  AS Location,
    0                                                AS QuestionCount,
    0                                                AS AnswerCount,
    NULL                                             AS AvgScore,
    NULL                                             AS LastPostDate,
    0                                                AS GoldBadges,
    0                                                AS SilverBadges,
    0                                                AS BronzeBadges,
    0                                                AS UpVoteCount,
    0                                                AS DownVoteCount,
    '[no activity]'                                  AS RecentEditSnippets,
    NULL                                             AS UserScoreRank
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND u.Reputation BETWEEN 0 AND 500

ORDER BY UserScoreRank NULLS LAST, Reputation DESC
LIMIT 100 OFFSET 0;
