-- {"query": "3304.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1999} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(p.Score), 0)                                      AS TotalPostScore,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)                    AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)                    AS AnswerCount,
        SUM(CASE b.Class WHEN 1 THEN 100 WHEN 2 THEN 50 ELSE 10 END)   AS BadgePoints,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)                AS RepRank
    FROM Users u
    LEFT JOIN Posts   p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges  b ON b.UserId      = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

TagPopularity AS (
    SELECT
        t.TagName,
        t.Count                                            AS TagUseCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)        AS QuestionPosts,
        SUM(p.Score)                                      AS TotalScore,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC)         AS TagRank
    FROM Tags t
    LEFT JOIN PostLinks pl ON pl.RelatedPostId = t.ExcerptPostId
    LEFT JOIN Posts p     ON p.Id = pl.PostId
    GROUP BY t.Id, t.TagName, t.Count
),

TopUsers AS (
    SELECT *
    FROM UserStats
    WHERE RepRank <= 100
),

UserTagActivity AS (
    SELECT
        u.Id                                            AS UserId,
        UNNEST(string_to_array(p.Tags, '><'))           AS Tag,
        COUNT(*)                                        AS PostsWithTag,
        SUM(p.Score)                                    AS ScoreWithTag
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.Tags IS NOT NULL
    GROUP BY u.Id, Tag
),

Combined AS (
    SELECT
        tu.Id,
        tu.DisplayName,
        tu.Reputation,
        tu.TotalPostScore,
        tu.BadgePoints,
        COALESCE(uta.PostsWithTopTag, 0)                 AS PostsWithTopTag,
        COALESCE(uta.ScoreWithTopTag, 0)                 AS ScoreWithTopTag,
        CASE
            WHEN tu.TotalPostScore + tu.BadgePoints > 10000 THEN 'PowerUser'
            WHEN tu.Reputation > 2000                         THEN 'Experienced'
            ELSE                                               'Novice'
        END                                               AS UserTier
    FROM TopUsers tu
    LEFT JOIN (
        SELECT
            UserId,
            SUM(PostsWithTag) AS PostsWithTopTag,
            SUM(ScoreWithTag) AS ScoreWithTopTag
        FROM UserTagActivity
        WHERE Tag IN (SELECT TagName FROM TagPopularity WHERE TagRank <= 10)
        GROUP BY UserId
    ) uta ON uta.UserId = tu.Id
)

SELECT
    c.Id,
    c.DisplayName,
    c.Reputation,
    c.TotalPostScore,
    c.BadgePoints,
    c.PostsWithTopTag,
    c.ScoreWithTopTag,
    c.UserTier,
    COALESCE(v.UpVotes, 0) - COALESCE(v.DownVotes, 0)         AS NetVotes,
    (SELECT COUNT(*) FROM Comments cm WHERE cm.UserId = c.Id) AS CommentCount
FROM Combined c
LEFT JOIN (
    SELECT
        u.Id,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Users u
    JOIN Votes v   ON v.UserId = u.Id
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY u.Id
) v ON v.Id = c.Id
WHERE c.UserTier <> 'Novice'
ORDER BY c.TotalPostScore DESC, c.BadgePoints DESC
LIMIT 50

UNION ALL

SELECT
    NULL                AS Id,
    'Aggregate'         AS DisplayName,
    NULL                AS Reputation,
    SUM(TotalPostScore) AS TotalPostScore,
    SUM(BadgePoints)    AS BadgePoints,
    SUM(PostsWithTopTag) AS PostsWithTopTag,
    SUM(ScoreWithTopTag) AS ScoreWithTopTag,
    NULL                AS UserTier,
    NULL                AS NetVotes,
    NULL                AS CommentCount
FROM Combined
WHERE UserTier = 'PowerUser';
