WITH users_cte AS (
    SELECT
        u.Id          AS UserId,
        u.DisplayName,
        u.Reputation
    FROM Users u
),
post_stats AS (
    SELECT
        p.OwnerUserId                 AS UserId,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS ACount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score END)   AS QScoreSum,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score END)   AS AScoreSum,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END)   AS QScoreAvg,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END)   AS AScoreAvg
    FROM Posts p
    GROUP BY p.OwnerUserId
),
tag_lists AS (
    SELECT
        p.OwnerUserId,
        STRING_AGG(trim(both '<' FROM trim(both '>' FROM ut.tag)), ',' ) AS TagIdentifiers
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT value AS tag
        FROM UNNEST(string_to_array(REGEXP_REPLACE(p.Tags, '[<>]', '', 'g'), '>')) AS t(value)
    ) ut
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
badge_counts AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS Gold,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS Silver,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS Bronze
    FROM Badges b
    GROUP BY b.UserId
),
duplicate_counts AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) AS Duplicates
    FROM Posts p
    JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 3
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
vote_counts AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) AS TotalVotes
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
),
final AS (
    SELECT
        u.UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(ps.QCount, 0)       AS Questions,
        COALESCE(ps.ACount, 0)       AS Answers,
        COALESCE(ps.QScoreSum, 0)    AS QScoreSum,
        COALESCE(ps.AScoreSum, 0)    AS AScoreSum,
        COALESCE(ps.QScoreAvg, 0)    AS QAvgScore,
        COALESCE(ps.AScoreAvg, 0)    AS AAvgScore,
        COALESCE(bd.Gold, 0)        AS GoldBadges,
        COALESCE(bd.Silver, 0)      AS SilverBadges,
        COALESCE(bd.Bronze, 0)      AS BronzeBadges,
        COALESCE(dc.Duplicates, 0)  AS DuplicateQuestions,
        COALESCE(vc.TotalVotes, 0)  AS VotesReceived,
        COALESCE(tl.TagIdentifiers, '') AS TagList,
        (COALESCE(bd.Gold, 0) * 200
         + COALESCE(bd.Silver, 0) * 100
         + COALESCE(bd.Bronze, 0) * 50
         + u.Reputation)          AS CompositeScore
    FROM users_cte u
    LEFT JOIN post_stats ps      ON ps.UserId = u.UserId
    LEFT JOIN badge_counts bd    ON bd.UserId = u.UserId
    LEFT JOIN duplicate_counts dc ON dc.OwnerUserId = u.UserId
    LEFT JOIN vote_counts vc     ON vc.OwnerUserId = u.UserId
    LEFT JOIN tag_lists tl       ON tl.OwnerUserId = u.UserId
)
SELECT
    f.UserId,
    f.DisplayName,
    f.Reputation,
    f.Questions,
    f.Answers,
    f.QScoreSum,
    f.AScoreSum,
    f.QAvgScore,
    f.AAvgScore,
    f.GoldBadges,
    f.SilverBadges,
    f.BronzeBadges,
    f.DuplicateQuestions,
    f.VotesReceived,
    f.TagList,
    f.CompositeScore,
    (SELECT COUNT(*) FROM Votes v2
     WHERE v2.VoteTypeId = 1 AND v2.UserId = f.UserId) AS AcceptsByUser,
    ROW_NUMBER() OVER (ORDER BY f.CompositeScore DESC, f.VotesReceived DESC) AS Rank,
    DENSE_RANK()  OVER (ORDER BY f.CompositeScore DESC) AS DenseRank
FROM final f
WHERE f.CompositeScore > 0
ORDER BY Rank
FETCH FIRST 50 ROWS ONLY;