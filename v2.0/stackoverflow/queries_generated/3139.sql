-- {"query": "3139.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2206} 

/*  Benchmark Query – combines CTEs, window functions, outer joins,
    correlated sub‑queries, set operators, string handling and NULL logic */
WITH TopUsers AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)               AS rn,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM   Users u
    WHERE  u.Reputation IS NOT NULL
),
RecentPosts AS (
    SELECT p.Id,
           p.OwnerUserId,
           p.PostTypeId,
           p.CreationDate,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_recent
    FROM   Posts p
    WHERE  p.CreationDate >= DATEADD(DAY, -30, CURRENT_TIMESTAMP)
),
TagStats AS (
    SELECT t.TagName,
           COUNT(p.Id)                                                  AS TotalPosts,
           SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END)            AS Questions,
           SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END)            AS Answers,
           MAX(p.Score)                                                AS MaxScore,
           MIN(p.Score)                                                AS MinScore,
           AVG(p.Score)                                                AS AvgScore
    FROM   Tags t
    LEFT JOIN Posts p
           ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY t.TagName
    HAVING COUNT(p.Id) > 0
),
VotesAgg AS (
    SELECT v.PostId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)          AS UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)          AS DownVotes,
           COUNT(*) FILTER (WHERE v.VoteTypeId = 5)                    AS Favorites,
           MAX(v.CreationDate)                                        AS LastVoteDate
    FROM   Votes v
    GROUP BY v.PostId
),
ClosedDuplicate AS (
    SELECT ph.PostId,
           MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReason,
           MAX(CASE WHEN ph.PostHistoryTypeId = 3  THEN ph.Comment END) AS DuplicateInfo
    FROM   PostHistory ph
    WHERE  ph.PostHistoryTypeId IN (10, 3)
    GROUP BY ph.PostId
)

SELECT
    tu.Id                                      AS UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    rp.Id                                      AS RecentPostId,
    rp.PostTypeId,
    rp.CreationDate                            AS PostCreated,
    ts.TagName,
    ts.TotalPosts,
    ts.Questions,
    ts.Answers,
    ts.AvgScore,
    va.UpVotes,
    va.DownVotes,
    va.Favorites,
    cd.CloseReason,
    cd.DuplicateInfo,
    ROW_NUMBER() OVER (PARTITION BY tu.Id ORDER BY rp.CreationDate DESC) AS UserPostRank,
    CASE
        WHEN va.UpVotes - va.DownVotes > 0 THEN 'Positive'
        WHEN va.UpVotes - va.DownVotes = 0 THEN 'Neutral'
        ELSE 'Negative'
    END                                        AS VoteSentiment,
    COALESCE(NULLIF(p.Title, ''), p.Body)      AS TitleOrBodySnippet,
    LEFT(p.Tags, 50)                           AS TagSnippet
FROM   TopUsers tu
LEFT   JOIN RecentPosts rp
       ON rp.OwnerUserId = tu.Id AND rp.rn_recent = 1
LEFT   JOIN Posts p
       ON p.Id = rp.Id
LEFT   JOIN LATERAL (
           SELECT TRIM(BOTH '<>' FROM unnest(string_to_array(p.Tags, '><'))) AS tag_raw
       ) AS tags_split ON TRUE
LEFT   JOIN TagStats ts
       ON ts.TagName = tags_split.tag_raw
LEFT   JOIN VotesAgg va
       ON va.PostId = p.Id
LEFT   JOIN ClosedDuplicate cd
       ON cd.PostId = p.Id
WHERE  tu.rn <= 100
ORDER  BY tu.Reputation DESC, UserPostRank ASC
LIMIT  200

UNION ALL

SELECT
    NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL,
    t.TagName,
    t.TotalPosts,
    t.Questions,
    t.Answers,
    t.AvgScore,
    NULL, NULL, NULL,
    NULL, NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM   TagStats t
WHERE  t.AvgScore > 5
ORDER  BY TotalPosts DESC
OFFSET 0;
