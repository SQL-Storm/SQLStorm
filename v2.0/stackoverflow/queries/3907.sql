-- {"query": "3907.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1891}
WITH 
UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id)                                AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers,
        COALESCE(SUM(v.UpVotes), 0)                AS VoteScore,
        MAX(p.CreationDate)                       AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS UpVotes
        FROM Votes
        WHERE VoteTypeId = 2
        GROUP BY PostId
    ) v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeAgg AS (
    SELECT 
        b.UserId,
        SUM(CASE b.Class WHEN 1 THEN 1000 WHEN 2 THEN 500 WHEN 3 THEN 100 ELSE 0 END) AS BadgePoints,
        -- STRING_AGG name may vary by dialect; using a common form. If STRING_AGG is supported, keep it.
        STRING_AGG(DISTINCT b.Name, ',')                                   AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),
TagUsage AS (
    SELECT 
        pu.OwnerUserId                               AS UserId,
        t.tag                                        AS Tag,
        COUNT(*)                                     AS TagCount
    FROM Posts pu
    CROSS JOIN LATERAL (
        SELECT TRIM(BOTH '<>' FROM pu.Tags) AS tags_clean
    ) tc
    CROSS JOIN LATERAL (
        -- split tags by '><' into rows; function names differ by dialect. For PostgreSQL use unnest(string_to_array(...))
        -- Here use unnest(string_to_array(...)) form which is standard in PG; other dialects may require adjustment.
        SELECT UNNEST(string_to_array(tc.tags_clean, '><')) AS tag
    ) t
    WHERE pu.Tags IS NOT NULL
    GROUP BY pu.OwnerUserId, t.tag
),
TopTagPerUser AS (
    SELECT 
        tu.UserId,
        tu.Tag,
        tu.TagCount,
        RANK() OVER (PARTITION BY tu.UserId ORDER BY tu.TagCount DESC) AS rnk
    FROM TagUsage tu
),
RecentComments AS (
    SELECT 
        c.UserId,
        COUNT(*)               AS CommentCount,
        MAX(c.CreationDate)    AS LastCommentDate
    FROM Comments c
    GROUP BY c.UserId
),
Combined AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.TotalPosts,
        us.Questions,
        us.Answers,
        us.VoteScore,
        us.LastPostDate,
        COALESCE(ba.BadgePoints, 0)   AS BadgePoints,
        ba.BadgeList,
        rc.CommentCount,
        rc.LastCommentDate,
        tp.Tag                         AS TopTag,
        tp.TagCount                    AS TopTagCount,
        ROW_NUMBER() OVER (ORDER BY (us.Reputation + COALESCE(ba.BadgePoints,0) + us.VoteScore) DESC) AS GlobalRank
    FROM UserStats us
    LEFT JOIN BadgeAgg ba      ON ba.UserId = us.Id
    LEFT JOIN RecentComments rc ON rc.UserId = us.Id
    LEFT JOIN (
        SELECT UserId, Tag, TagCount
        FROM TopTagPerUser
        WHERE rnk = 1
    ) tp ON tp.UserId = us.Id
    WHERE us.Reputation > 1000
      AND (us.LastPostDate IS NULL OR us.LastPostDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'))
      AND COALESCE(ba.BadgePoints,0) > 0
),
BadgeOnlyUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        0                               AS TotalPosts,
        0                               AS Questions,
        0                               AS Answers,
        0                               AS VoteScore,
        CAST(NULL AS timestamp)         AS LastPostDate,
        ba.BadgePoints,
        ba.BadgeList,
        0                               AS CommentCount,
        CAST(NULL AS timestamp)         AS LastCommentDate,
        CAST(NULL AS varchar)           AS TopTag,
        0                               AS TopTagCount,
        ROW_NUMBER() OVER (ORDER BY ba.BadgePoints DESC) AS GlobalRank
    FROM Users u
    LEFT JOIN BadgeAgg ba ON ba.UserId = u.Id
    LEFT JOIN Posts p    ON p.OwnerUserId = u.Id
    WHERE p.Id IS NULL
      AND ba.BadgePoints > 2000
)
SELECT *
FROM (
    SELECT Id,
           DisplayName,
           Reputation,
           TotalPosts,
           Questions,
           Answers,
           VoteScore,
           LastPostDate,
           BadgePoints,
           BadgeList,
           CommentCount,
           LastCommentDate,
           TopTag,
           TopTagCount,
           GlobalRank
    FROM Combined
    UNION ALL
    SELECT Id,
           DisplayName,
           Reputation,
           TotalPosts,
           Questions,
           Answers,
           VoteScore,
           LastPostDate,
           BadgePoints,
           BadgeList,
           CommentCount,
           LastCommentDate,
           TopTag,
           TopTagCount,
           GlobalRank
    FROM BadgeOnlyUsers
) AS unified
WHERE GlobalRank <= 150
ORDER BY GlobalRank;