WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT MAX(CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostDate,
        (SELECT MAX(CreationDate) FROM Comments c WHERE c.UserId = u.Id) AS LastCommentDate
    FROM Users u
),
PostInfo AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        COALESCE(p.AcceptedAnswerId,0) AS AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostKind,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
),
VoteAgg AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetScore,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoriteCount,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    GROUP BY v.PostId
),
TagExplode AS (
    SELECT 
        p.Id AS PostId,
        UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
TagStats AS (
    SELECT 
        te.Tag AS Tag,
        COUNT(DISTINCT te.PostId) AS QuestionCount,
        SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreCount
    FROM TagExplode te
    JOIN Posts p ON p.Id = te.PostId
    GROUP BY te.Tag
),
Combined AS (
    SELECT 
        us.Id                                 AS UserId,
        us.DisplayName,
        us.Reputation,
        us.NetVotes,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        COALESCE(us.LastPostDate,    CAST('1970-01-01' AS timestamp)) AS LastPostDate,
        COALESCE(us.LastCommentDate, CAST('1970-01-01' AS timestamp)) AS LastCommentDate,
        pi.Id                                 AS PostId,
        pi.PostKind,
        pi.Title,
        pi.Score,
        pi.ViewCount,
        va.NetScore,
        va.FavoriteCount,
        va.LastVoteDate,
        STRING_AGG(DISTINCT te.Tag, ',')  AS TagsList,
        CASE 
            WHEN pi.Score IS NULL THEN 0
            ELSE pi.Score + COALESCE(va.NetScore,0)
        END                                   AS CombinedScore,
        CASE 
            WHEN pi.Title IS NULL THEN 'No Title'
            ELSE SUBSTRING(pi.Title FROM 1 FOR 60)
        END                                   AS ShortTitle
    FROM UserStats us
    LEFT JOIN PostInfo pi   ON pi.OwnerUserId = us.Id AND pi.rn = 1
    LEFT JOIN VoteAgg va    ON va.PostId = pi.Id
    LEFT JOIN TagExplode te ON te.PostId = pi.Id
    LEFT JOIN TagStats ts   ON ts.Tag = te.Tag
    GROUP BY 
        us.Id, us.DisplayName, us.Reputation, us.NetVotes,
        us.GoldBadges, us.SilverBadges, us.BronzeBadges,
        us.LastPostDate, us.LastCommentDate,
        pi.Id, pi.PostKind, pi.Title, pi.Score, pi.ViewCount,
        va.NetScore, va.FavoriteCount, va.LastVoteDate
),
Filtered AS (
    SELECT *
    FROM Combined
    WHERE (Reputation > 10000 OR GoldBadges >= 10)
      AND CombinedScore > 0
    ORDER BY CombinedScore DESC, Reputation DESC
    LIMIT 100
)
SELECT *
FROM Filtered

UNION ALL

SELECT 
    CAST(NULL AS bigint) AS UserId,
    'Aggregated Totals' AS DisplayName,
    SUM(Reputation)      AS Reputation,
    SUM(NetVotes)        AS NetVotes,
    SUM(GoldBadges)      AS GoldBadges,
    SUM(SilverBadges)    AS SilverBadges,
    SUM(BronzeBadges)    AS BronzeBadges,
    CAST(NULL AS timestamp) AS LastPostDate,
    CAST(NULL AS timestamp) AS LastCommentDate,
    CAST(NULL AS bigint) AS PostId,
    CAST(NULL AS text) AS PostKind,
    CAST(NULL AS text) AS Title,
    CAST(NULL AS integer) AS Score,
    CAST(NULL AS integer) AS ViewCount,
    CAST(NULL AS bigint) AS NetScore,
    CAST(NULL AS bigint) AS FavoriteCount,
    CAST(NULL AS timestamp) AS LastVoteDate,
    CAST(NULL AS text) AS TagsList,
    CAST(NULL AS integer) AS CombinedScore,
    CAST(NULL AS text) AS ShortTitle
FROM Combined
HAVING COUNT(*) > 0;