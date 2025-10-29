-- {"query": "3600.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2591} 

WITH TagPosts AS (
    SELECT
        t.Id                                    AS TagId,
        t.TagName,
        p.Id                                    AS PostId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.Title,
        p.Tags
    FROM Tags t
    JOIN Posts p
        ON (',' || REPLACE(REPLACE(p.Tags, '><', ','), '<', '') || ',')
           LIKE '%,' || t.TagName || ',%'
       AND p.PostTypeId = 2               -- answers only
    WHERE t.IsModeratorOnly = 0
),
UserTagStats AS (
    SELECT
        tp.TagId,
        tp.TagName,
        tp.OwnerUserId,
        COUNT(*)                                     AS AnswerCount,
        SUM(tp.Score)                               AS TotalScore,
        AVG(tp.Score)                               AS AvgScore,
        MAX(tp.CreationDate)                        AS LastAnswerDate,
        ROW_NUMBER() OVER (
            PARTITION BY tp.TagId
            ORDER BY SUM(tp.Score) DESC, COUNT(*) DESC
        )                                            AS RankByScore
    FROM TagPosts tp
    GROUP BY tp.TagId, tp.TagName, tp.OwnerUserId
),
UserBadgeAgg AS (
    SELECT
        u.Id                                          AS UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END)      AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END)      AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END)      AS BronzeBadges,
        COUNT(b.Id)                                   AS TotalBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
RecentVotes AS (
    SELECT
        v.PostId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        MAX(v.CreationDate)                      AS LastVoteDate
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.PostId
),
Combined AS (
    SELECT
        uts.TagId,
        uts.TagName,
        uts.OwnerUserId,
        COALESCE(u.DisplayName, 'Deleted User')               AS OwnerDisplayName,
        uts.AnswerCount,
        uts.TotalScore,
        uts.AvgScore,
        uts.LastAnswerDate,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges,
        rv.UpVotes,
        rv.DownVotes,
        rv.LastVoteDate,
        CASE
            WHEN uts.TotalScore > 1000 THEN 'Legendary'
            WHEN uts.TotalScore >  500 THEN 'Expert'
            WHEN uts.TotalScore >  100 THEN 'Active'
            ELSE                         'Novice'
        END                                                   AS ContributorLevel
    FROM UserTagStats uts
    LEFT JOIN Users u            ON u.Id = uts.OwnerUserId
    LEFT JOIN UserBadgeAgg ub    ON ub.UserId = uts.OwnerUserId
    LEFT JOIN (
        SELECT
            p.OwnerUserId,
            SUM(rv.UpVotes)   AS UpVotes,
            SUM(rv.DownVotes) AS DownVotes,
            MAX(rv.LastVoteDate) AS LastVoteDate
        FROM RecentVotes rv
        JOIN Posts p ON p.Id = rv.PostId
        GROUP BY p.OwnerUserId
    ) rv ON rv.OwnerUserId = uts.OwnerUserId
    WHERE uts.RankByScore <= 5
)
SELECT *
FROM Combined
WHERE ContributorLevel <> 'Novice'

UNION ALL

SELECT
    NULL                               AS TagId,
    'Overall'                          AS TagName,
    u.Id                               AS OwnerUserId,
    COALESCE(u.DisplayName, 'Deleted User') AS OwnerDisplayName,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)    AS AnswerCount,
    SUM(p.Score)                                 AS TotalScore,
    AVG(p.Score)                                 AS AvgScore,
    MAX(p.CreationDate)                          AS LastAnswerDate,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TotalBadges,
    rv.UpVotes,
    rv.DownVotes,
    rv.LastVoteDate,
    CASE
        WHEN SUM(p.Score) > 5000 THEN 'Legendary'
        WHEN SUM(p.Score) > 2000 THEN 'Expert'
        WHEN SUM(p.Score) >  500 THEN 'Active'
        ELSE                           'Novice'
    END                                          AS ContributorLevel
FROM Users u
LEFT JOIN Posts p
    ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
LEFT JOIN UserBadgeAgg ub
    ON ub.UserId = u.Id
LEFT JOIN (
    SELECT
        p.OwnerUserId,
        SUM(rv.UpVotes)   AS UpVotes,
        SUM(rv.DownVotes) AS DownVotes,
        MAX(rv.LastVoteDate) AS LastVoteDate
    FROM RecentVotes rv
    JOIN Posts p ON p.Id = rv.PostId
    GROUP BY p.OwnerUserId
) rv ON rv.OwnerUserId = u.Id
GROUP BY
    u.Id,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TotalBadges,
    rv.UpVotes,
    rv.DownVotes,
    rv.LastVoteDate
HAVING COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) > 0
ORDER BY TotalScore DESC NULLS LAST, AnswerCount DESC;
