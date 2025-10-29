-- {"query": "3930.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2512} 

WITH
    TopUsers AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank,
            COALESCE(b.GoldCnt,0)   AS GoldBadges,
            COALESCE(b.SilverCnt,0) AS SilverBadges,
            COALESCE(b.BronzeCnt,0) AS BronzeBadges
        FROM Users u
        LEFT JOIN (
            SELECT
                UserId,
                SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldCnt,
                SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverCnt,
                SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeCnt
            FROM Badges
            GROUP BY UserId
        ) b ON u.Id = b.UserId
        WHERE u.Reputation > 1000
    ),
    RecentActivity AS (
        SELECT
            p.OwnerUserId AS UserId,
            MAX(p.CreationDate) AS LastPostDate,
            MAX(c.CreationDate) AS LastCommentDate,
            MAX(v.CreationDate) AS LastVoteDate
        FROM Posts p
        LEFT JOIN Comments c ON c.UserId = p.OwnerUserId
        LEFT JOIN Votes    v ON v.UserId = p.OwnerUserId
        GROUP BY p.OwnerUserId
    ),
    TagStats AS (
        SELECT
            t.TagName,
            t.Count                              AS TagTotalPosts,
            COUNT(p.Id) FILTER (WHERE p.Score >= 10) AS HighScorePosts,
            STRING_AGG(DISTINCT u.DisplayName, ', ') FILTER (WHERE u.Reputation > 5000) AS TopUserNames
        FROM Tags t
        LEFT JOIN Posts p ON p.Tags LIKE '%'||t.TagName||'%'
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
        GROUP BY t.TagName, t.Count
        HAVING t.Count > 50
    ),
    DuplicateLinks AS (
        SELECT
            pl.PostId,
            pl.RelatedPostId,
            pl.CreationDate,
            CASE
                WHEN ph.Comment ~ '\"CloseReasonId\":\s*101' THEN 'Duplicate'
                ELSE 'Other'
            END AS CloseReason
        FROM PostLinks pl
        JOIN PostHistory ph ON ph.PostId = pl.PostId
        WHERE pl.LinkTypeId = 3
    )
SELECT
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.RepRank,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    COALESCE(ra.LastPostDate,    TIMESTAMP '1970-01-01') AS LastPostDate,
    COALESCE(ra.LastCommentDate,TIMESTAMP '1970-01-01') AS LastCommentDate,
    COALESCE(ra.LastVoteDate,   TIMESTAMP '1970-01-01') AS LastVoteDate,
    ts.TagName,
    ts.TagTotalPosts,
    ts.HighScorePosts,
    ts.TopUserNames,
    dl.CloseReason,
    dl.CreationDate AS DuplicateLinkDate
FROM TopUsers tu
LEFT JOIN RecentActivity ra ON ra.UserId = tu.Id
LEFT JOIN LATERAL (
    SELECT *
    FROM TagStats ts
    WHERE POSITION(','||tu.DisplayName||',' IN ','||ts.TopUserNames||',') > 0
    ORDER BY ts.HighScorePosts DESC
    LIMIT 1
) ts ON TRUE
LEFT JOIN LATERAL (
    SELECT *
    FROM DuplicateLinks dl
    WHERE dl.PostId = (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = tu.Id
        ORDER BY p.CreationDate DESC
        LIMIT 1
    )
    ORDER BY dl.CreationDate DESC
    LIMIT 1
) dl ON TRUE
WHERE (tu.Reputation * (tu.GoldBadges + tu.SilverBadges + tu.BronzeBadges)) > 5000

UNION ALL

SELECT
    NULL                     AS Id,
    'Overall Summary'        AS DisplayName,
    SUM(u.Reputation)        AS Reputation,
    NULL                     AS RepRank,
    SUM(CASE WHEN b.Class=1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class=2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class=3 THEN 1 ELSE 0 END) AS BronzeBadges,
    MAX(p.CreationDate)      AS LastPostDate,
    MAX(c.CreationDate)      AS LastCommentDate,
    MAX(v.CreationDate)      AS LastVoteDate,
    NULL                     AS TagName,
    NULL                     AS TagTotalPosts,
    NULL                     AS HighScorePosts,
    NULL                     AS TopUserNames,
    NULL                     AS CloseReason,
    NULL                     AS DuplicateLinkDate
FROM Users u
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Posts   p ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON c.UserId = u.Id
LEFT JOIN Votes    v ON v.UserId = u.Id
WHERE u.CreationDate < CURRENT_DATE - INTERVAL '1 year'
GROUP BY ROLLUP(u.Id);
