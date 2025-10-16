WITH
    TopUsers AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate,
            COALESCE(u.Location, 'unknown') AS Location,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
        FROM Users u
        WHERE u.Reputation > 10000
    ),

    BadgeCounts AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS Gold,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS Silver,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS Bronze,
            COUNT(*)                                            AS TotalBadges
        FROM Badges b
        GROUP BY b.UserId
    ),

    PostAgg AS (
        SELECT
            p.OwnerUserId               AS UserId,
            SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
            SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
            SUM(p.Score)                               AS TotalScore,
            MAX(p.CreationDate)                        AS LastPostDate,
            STRING_AGG(DISTINCT COALESCE(NULLIF(p.Tags, ''), ''), ';') AS AllTags
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    VoteAgg AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
            MAX(v.CreationDate)                               AS LastVoteDate
        FROM Votes v
        GROUP BY v.PostId
    ),

    RecentActivity AS (
        SELECT
            u.Id AS UserId,
            GREATEST(
                COALESCE((SELECT MAX(CreationDate) FROM Posts    WHERE OwnerUserId = u.Id), TIMESTAMP '1970-01-01'),
                COALESCE((SELECT MAX(CreationDate) FROM Comments WHERE UserId      = u.Id), TIMESTAMP '1970-01-01')
            ) AS LatestActivity
        FROM Users u
    ),

    TagUnion AS (
        SELECT TagName, Count FROM Tags WHERE IsModeratorOnly = FALSE
        UNION ALL
        SELECT 'AllTags' AS TagName, SUM(Count) AS Count FROM Tags
    ),

    TopTags AS (
        SELECT
            TagName,
            Count        AS TagUseCount,
            ROW_NUMBER() OVER (ORDER BY Count DESC) AS TagRank
        FROM TagUnion
        WHERE TagName <> 'AllTags'
    )

SELECT
    tu.rn,
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.Location,
    bc.Gold,
    bc.Silver,
    bc.Bronze,
    bc.TotalBadges,
    pa.Questions,
    pa.Answers,
    pa.TotalScore,
    pa.LastPostDate,
    pa.AllTags,
    COALESCE(vu.UpVotes,   0) AS UserUpVotes,
    COALESCE(vu.DownVotes, 0) AS UserDownVotes,
    ra.LatestActivity,
    CASE
        WHEN pa.TotalScore IS NULL            THEN 'NoPosts'
        WHEN pa.TotalScore > 1000             THEN 'HighScorer'
        ELSE                                      'Normal'
    END AS ScoreCategory,
    ('User_' || tu.Id) AS UserKey,
    tt.TagName,
    tt.TagUseCount,
    tt.TagRank
FROM TopUsers tu
LEFT JOIN BadgeCounts   bc ON bc.UserId = tu.Id
LEFT JOIN PostAgg       pa ON pa.UserId = tu.Id
LEFT JOIN (
    SELECT
        p.OwnerUserId AS UserId,
        SUM(vu.UpVotes)   AS UpVotes,
        SUM(vu.DownVotes) AS DownVotes
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT
            COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
            COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes
        FROM Votes v
        WHERE v.PostId = p.Id
    ) vu ON TRUE
    GROUP BY p.OwnerUserId
) vu ON vu.UserId = tu.Id
LEFT JOIN RecentActivity ra ON ra.UserId = tu.Id
FULL OUTER JOIN TopTags tt   ON tt.TagRank = tu.rn
WHERE tu.rn <= 100
ORDER BY tu.rn;