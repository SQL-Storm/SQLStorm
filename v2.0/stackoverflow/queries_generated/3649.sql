-- {"query": "3649.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2646} 

WITH
    BadgeCounts AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS Gold,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS Silver,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS Bronze
        FROM Badges b
        GROUP BY b.UserId
    ),
    PostStats AS (
        SELECT
            p.OwnerUserId AS UserId,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
            AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS AvgScore,
            MAX(p.CreationDate) AS LastPostDate
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    RecentVotes AS (
        SELECT
            v.UserId,
            COUNT(*) AS RecentVoteCount
        FROM Votes v
        WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
          AND v.VoteTypeId = 2                     -- up‑vote
        GROUP BY v.UserId
    ),
    UserRank AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COALESCE(bc.Gold,0)   AS GoldBadges,
            COALESCE(bc.Silver,0) AS SilverBadges,
            COALESCE(bc.Bronze,0) AS BronzeBadges,
            COALESCE(ps.QuestionCount,0) AS Questions,
            COALESCE(ps.AnswerCount,0)   AS Answers,
            COALESCE(ps.AvgScore,0)      AS AvgPostScore,
            COALESCE(rv.RecentVoteCount,0) AS RecentUpVotes,
            ROW_NUMBER() OVER (
                ORDER BY u.Reputation DESC NULLS LAST,
                         COALESCE(bc.Gold,0) DESC,
                         COALESCE(bc.Silver,0) DESC
            ) AS Rank
        FROM Users u
        LEFT JOIN BadgeCounts bc ON bc.UserId = u.Id
        LEFT JOIN PostStats ps   ON ps.UserId = u.Id
        LEFT JOIN RecentVotes rv ON rv.UserId = u.Id
        WHERE (u.Reputation > 1000 OR u.Reputation IS NULL)
    ),
    TopActiveUsers AS (
        SELECT *
        FROM UserRank
        WHERE Rank <= 100
    ),
    TagStats AS (
        SELECT
            tu.Id,
            MAX(CASE
                WHEN tu.Tags IS NOT NULL THEN (
                    SELECT COUNT(*)
                    FROM Tags tg
                    WHERE POSITION('<' || tg.TagName || '>' IN tu.Tags) > 0
                      AND tg.Count > 5000
                )
                ELSE 0
            END) AS PopularTagCount
        FROM (
            SELECT
                u.Id,
                u.DisplayName,
                (SELECT STRING_AGG(t.TagName, ',')
                 FROM Tags t
                 JOIN Posts p ON p.Tags IS NOT NULL
                     AND p.OwnerUserId = u.Id
                     AND POSITION('<' || t.TagName || '>' IN p.Tags) > 0
                 LIMIT 5) AS Tags
            FROM Users u
        ) tu
        GROUP BY tu.Id, tu.DisplayName, tu.Tags
    )
SELECT
    ta.Id,
    ta.DisplayName,
    ta.Reputation,
    ta.GoldBadges,
    ta.SilverBadges,
    ta.BronzeBadges,
    ta.Questions,
    ta.Answers,
    ROUND(ta.AvgPostScore,2) AS AvgScore,
    ta.RecentUpVotes,
    COALESCE(ts.PopularTagCount,0) AS PopularTagCount,
    CASE WHEN u.Location IS NULL THEN 'Unknown' ELSE u.Location END AS Location,
    COALESCE(u.WebsiteUrl, 'N/A') AS Website,
    (SELECT COUNT(*)
     FROM Posts p
     WHERE p.OwnerUserId = ta.Id
       AND p.Score * (COALESCE(p.ViewCount,0)+1) > 1000) AS HighImpactPosts
FROM TopActiveUsers ta
LEFT JOIN TagStats ts ON ts.Id = ta.Id
LEFT JOIN Users u    ON u.Id = ta.Id
ORDER BY ta.Rank

UNION ALL

SELECT
    NULL AS Id,
    'Aggregated Summary' AS DisplayName,
    NULL AS Reputation,
    SUM(GoldBadges)   AS GoldBadges,
    SUM(SilverBadges) AS SilverBadges,
    SUM(BronzeBadges) AS BronzeBadges,
    SUM(Questions)    AS Questions,
    SUM(Answers)      AS Answers,
    NULL              AS AvgScore,
    SUM(RecentUpVotes) AS RecentUpVotes,
    NULL              AS PopularTagCount,
    NULL              AS Location,
    NULL              AS Website,
    NULL              AS HighImpactPosts
FROM TopActiveUsers;
