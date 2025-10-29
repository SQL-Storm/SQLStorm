WITH
    TopUsers AS (
        SELECT u.Id,
               u.DisplayName,
               u.Reputation,
               COALESCE(u.Location, 'Unknown') AS Location,
               COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
               COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
               SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteTotal,
               SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteTotal,
               MAX(p.CreationDate) AS LastPostDate
        FROM Users u
        LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v   ON v.PostId = p.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
        HAVING COUNT(p.Id) > 0
    ),
    RecentBadges AS (
        SELECT b.UserId,
               STRING_AGG(b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadges,
               STRING_AGG(b.Name, ', ') FILTER (WHERE b.Class = 2) AS SilverBadges,
               STRING_AGG(b.Name, ', ') FILTER (WHERE b.Class = 3) AS BronzeBadges,
               COUNT(*) AS TotalBadges
        FROM Badges b
        WHERE b.Date >= DATE '2024-10-01' - INTERVAL '90' DAY
        GROUP BY b.UserId
    ),
    TagMentions AS (
        SELECT p.OwnerUserId AS UserId,
               tag AS Tag,
               COUNT(*) AS TagUseCount
        FROM Posts p,
             LATERAL (
               SELECT UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag
             ) t
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, tag
    ),
    TopTagsPerUser AS (
        SELECT tmu.UserId,
               STRING_AGG(tmu.Tag || ':' || tmu.TagUseCount, ', ' ORDER BY tmu.TagUseCount DESC) AS TopTags
        FROM (
            SELECT tm.UserId,
                   tm.Tag,
                   tm.TagUseCount,
                   ROW_NUMBER() OVER (PARTITION BY tm.UserId ORDER BY tm.TagUseCount DESC) AS rn
            FROM TagMentions tm
        ) tmu
        WHERE rn <= 5
        GROUP BY tmu.UserId
    ),
    ClosureStats AS (
        SELECT ph.UserId,
               COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS ClosedCount,
               COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS ReopenedCount,
               MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId = 10) AS LastCloseDate
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (10,11)
        GROUP BY ph.UserId
    ),
    Detailed AS (
        SELECT
            tu.Id,
            tu.DisplayName,
            tu.Reputation,
            tu.Location,
            tu.QuestionCount,
            tu.AnswerCount,
            tu.UpVoteTotal - tu.DownVoteTotal AS NetScore,
            COALESCE(rb.GoldBadges, '')   AS GoldBadges,
            COALESCE(rb.SilverBadges, '') AS SilverBadges,
            COALESCE(rb.BronzeBadges, '') AS BronzeBadges,
            COALESCE(rb.TotalBadges, 0)   AS TotalBadges,
            COALESCE(tt.TopTags, '')      AS TopTags,
            COALESCE(cs.ClosedCount, 0)   AS ClosedCount,
            COALESCE(cs.ReopenedCount, 0) AS ReopenedCount,
            cs.LastCloseDate,
            (SELECT MAX(p.Score)
             FROM Posts p
             WHERE p.OwnerUserId = tu.Id AND p.PostTypeId = 2) AS MaxAnswerScore,
            ROW_NUMBER() OVER (PARTITION BY tu.Location ORDER BY tu.Reputation DESC) AS RankInLocation
        FROM TopUsers tu
        LEFT JOIN RecentBadges rb   ON rb.UserId = tu.Id
        LEFT JOIN TopTagsPerUser tt ON tt.UserId = tu.Id
        LEFT JOIN ClosureStats cs   ON cs.UserId = tu.Id
        WHERE (tu.Reputation > 1000 OR tu.QuestionCount > 10)
    ),
    AggregatedTotals AS (
        SELECT
            -1                                 AS Id,
            'Aggregated Totals'                AS DisplayName,
            SUM(d.Reputation)                  AS Reputation,
            NULL::text                          AS Location,
            SUM(d.QuestionCount)               AS QuestionCount,
            SUM(d.AnswerCount)                 AS AnswerCount,
            SUM(d.NetScore)                    AS NetScore,
            NULL::text                          AS GoldBadges,
            NULL::text                          AS SilverBadges,
            NULL::text                          AS BronzeBadges,
            SUM(d.TotalBadges)                 AS TotalBadges,
            NULL::text                          AS TopTags,
            SUM(d.ClosedCount)                 AS ClosedCount,
            SUM(d.ReopenedCount)               AS ReopenedCount,
            MAX(d.LastCloseDate)               AS LastCloseDate,
            NULL::integer                       AS MaxAnswerScore,
            NULL::integer                       AS RankInLocation
        FROM Detailed d
    )
SELECT *
FROM (
    SELECT *
    FROM Detailed
    ORDER BY Reputation DESC
    LIMIT 100
) d
UNION ALL
SELECT *
FROM AggregatedTotals;