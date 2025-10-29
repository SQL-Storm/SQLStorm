-- {"query": "3948.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2142} 

WITH
    TopReputation AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
        FROM Users u
        WHERE u.Reputation IS NOT NULL
    ),
    RecentBadges AS (
        SELECT
            b.UserId,
            COUNT(*) FILTER (WHERE b.Class = 1) AS gold,
            COUNT(*) FILTER (WHERE b.Class = 2) AS silver,
            COUNT(*) FILTER (WHERE b.Class = 3) AS bronze,
            MAX(b.Date) AS last_badge_date
        FROM Badges b
        WHERE b.Date >= CURRENT_DATE - INTERVAL '180 days'
        GROUP BY b.UserId
    ),
    TagActivity AS (
        SELECT
            t.TagName,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers,
            SUM(COALESCE(p.Score, 0)) AS total_score,
            STRING_AGG(DISTINCT u.DisplayName, ', ') AS participating_users
        FROM Tags t
        LEFT JOIN Posts p
            ON (',' || p.Tags || ',') LIKE ('%,' || t.TagName || ',%')
        LEFT JOIN Users u
            ON u.Id = p.OwnerUserId
        WHERE t.IsModeratorOnly = 0
        GROUP BY t.TagName
        HAVING COUNT(p.Id) > 10
    ),
    DuplicateLinks AS (
        SELECT
            pl.PostId,
            pl.RelatedPostId,
            COUNT(*) AS dup_cnt
        FROM PostLinks pl
        JOIN LinkTypes lt
            ON lt.Id = pl.LinkTypeId
            AND lt.Name = 'Duplicate'
        GROUP BY pl.PostId, pl.RelatedPostId
    )
SELECT
    tu.Id                              AS UserId,
    tu.DisplayName,
    tu.Reputation,
    tb.gold,
    tb.silver,
    tb.bronze,
    COALESCE(tb.last_badge_date, '1970-01-01') AS LastBadgeDate,
    p.Id                               AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    CASE
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
        WHEN p.ClosedDate IS NOT NULL        THEN 'Closed'
        ELSE 'Open'
    END                               AS Status,
    COALESCE(vc.UpVotes, 0) - COALESCE(vc.DownVotes, 0) AS NetVotes,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS RankInType,
    STRING_AGG(DISTINCT t.TagName, ';') AS TagsList,
    dl.dup_cnt
FROM TopReputation tu
LEFT JOIN RecentBadges tb
    ON tb.UserId = tu.Id
LEFT JOIN Posts p
    ON p.OwnerUserId = tu.Id
LEFT JOIN (
    SELECT
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
) vc
    ON vc.PostId = p.Id
LEFT JOIN LATERAL (
    SELECT
        UNNEST(string_to_array(p.Tags, '><')) AS TagName
) t
    ON true
LEFT JOIN DuplicateLinks dl
    ON dl.PostId = p.Id
WHERE tu.rn <= 100
  AND p.PostTypeId IN (1, 2)
  AND p.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
GROUP BY
    tu.Id, tu.DisplayName, tu.Reputation,
    tb.gold, tb.silver, tb.bronze, tb.last_badge_date,
    p.Id, p.Title, p.CreationDate, p.Score,
    p.AcceptedAnswerId, p.ClosedDate,
    vc.UpVotes, vc.DownVotes,
    dl.dup_cnt
UNION ALL
SELECT
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    t.TagName,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    ta.questions,
    ta.answers,
    ta.total_score,
    NULL,
    NULL,
    NULL
FROM TagActivity ta
JOIN Tags t
    ON t.TagName = ta.TagName
WHERE ta.total_score > 0
ORDER BY
    Reputation DESC NULLS LAST,
    NetVotes DESC,
    RankInType ASC
LIMIT 200;
