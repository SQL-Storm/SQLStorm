-- {"query": "3684.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2335} 

WITH TagPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS TagName,
        p.CreationDate,
        p.Score
    FROM Posts p
    WHERE p.PostTypeId = 1          -- questions only
      AND p.Tags IS NOT NULL
),
UserTagStats AS (
    SELECT
        tp.TagName,
        tp.OwnerUserId,
        COUNT(*) FILTER (WHERE tp.Score > 0)                     AS PosScoreCount,
        COUNT(*) FILTER (WHERE tp.Score <= 0)                    AS NonPosScoreCount,
        SUM(tp.Score)                                            AS TotalScore,
        MAX(tp.CreationDate)                                     AS LastPostDate
    FROM TagPosts tp
    GROUP BY tp.TagName, tp.OwnerUserId
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1)                     AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2)                     AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3)                     AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2)                AS UpVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3)                AS DownVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5)                AS Favorites
    FROM Votes v
    JOIN Posts p ON p.Id = v.PostId
    GROUP BY p.OwnerUserId
),
RankedTagUsers AS (
    SELECT
        uts.TagName,
        uts.OwnerUserId,
        uts.TotalScore,
        COALESCE(ubc.GoldBadges,0)                               AS GoldBadges,
        COALESCE(ubc.SilverBadges,0)                             AS SilverBadges,
        COALESCE(ubc.BronzeBadges,0)                             AS BronzeBadges,
        COALESCE(u.Reputation,0)                                 AS Reputation,
        ROW_NUMBER() OVER (PARTITION BY uts.TagName
                           ORDER BY uts.TotalScore DESC,
                                    u.Reputation DESC)         AS TagRank
    FROM UserTagStats uts
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = uts.OwnerUserId
    LEFT JOIN Users u ON u.Id = uts.OwnerUserId
    WHERE uts.TotalScore IS NOT NULL
)
SELECT
    rt.TagName,
    rt.OwnerUserId,
    u.DisplayName,
    rt.TotalScore,
    rt.GoldBadges,
    rt.SilverBadges,
    rt.BronzeBadges,
    rt.Reputation,
    uv.UpVotes,
    uv.DownVotes,
    uv.Favorites,
    CASE
        WHEN uv.UpVotes + uv.DownVotes = 0 THEN NULL
        ELSE ROUND(100.0 * uv.UpVotes::numeric
                 / NULLIF(uv.UpVotes + uv.DownVotes,0), 2)
    END                                                              AS UpVotePercent,
    rt.TagRank
FROM RankedTagUsers rt
LEFT JOIN LATERAL (
    SELECT
        SUM(vs.UpVotes)    AS UpVotes,
        SUM(vs.DownVotes)  AS DownVotes,
        SUM(vs.Favorites)  AS Favorites
    FROM UserVoteStats vs
    WHERE vs.OwnerUserId = rt.OwnerUserId
) uv ON TRUE
LEFT JOIN Users u ON u.Id = rt.OwnerUserId
WHERE rt.TagRank <= 10

UNION ALL

SELECT
    'overall'                                                AS TagName,
    u.Id                                                     AS OwnerUserId,
    u.DisplayName,
    SUM(p.Score)                                             AS TotalScore,
    COALESCE(bc.GoldBadges,0)                                 AS GoldBadges,
    COALESCE(bc.SilverBadges,0)                               AS SilverBadges,
    COALESCE(bc.BronzeBadges,0)                               AS BronzeBadges,
    u.Reputation,
    SUM(vs.UpVotes)                                          AS UpVotes,
    SUM(vs.DownVotes)                                        AS DownVotes,
    SUM(vs.Favorites)                                        AS Favorites,
    CASE
        WHEN SUM(vs.UpVotes + vs.DownVotes) = 0 THEN NULL
        ELSE ROUND(100.0 * SUM(vs.UpVotes)::numeric
                 / NULLIF(SUM(vs.UpVotes + vs.DownVotes),0), 2)
    END                                                      AS UpVotePercent,
    ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC)           AS TagRank
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN UserBadgeCounts bc ON bc.UserId = u.Id
LEFT JOIN UserVoteStats vs ON vs.OwnerUserId = u.Id
GROUP BY u.Id, u.DisplayName, bc.GoldBadges, bc.SilverBadges,
         bc.BronzeBadges, u.Reputation
HAVING SUM(p.Score) IS NOT NULL
ORDER BY TagName, TagRank;
