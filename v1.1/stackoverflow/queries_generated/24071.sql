-- {"query": "24071.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1709} 

WITH UserTagStats AS (
    SELECT
        u.Id                             AS UserId,
        t.TagName                        AS TagName,
        COUNT(DISTINCT p.Id)             AS TagPostCount,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS Questions,
        SUM(CASE WHEN pt.Name = 'Answer'   THEN 1 ELSE 0 END) AS Answers,
        MAX(u.LastAccessDate)            AS LastAccess,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes
    FROM Users u
    JOIN Posts p
        ON p.OwnerUserId = u.Id
    JOIN PostTypes pt
        ON p.PostTypeId = pt.Id
    LEFT JOIN Votes v
        ON v.PostId = p.Id
    LEFT JOIN PostLinks pl
        ON pl.PostId = p.Id
    LEFT JOIN Tags t
        ON t.Id = pl.RelatedPostId
    GROUP BY u.Id, t.TagName
),
TagRank AS (
    SELECT
        UserId,
        TagName,
        TagPostCount,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagPostCount DESC, TagName) AS Rank
    FROM UserTagStats
),
UserBadges AS (
    SELECT
        ub.UserId,
        COUNT(CASE WHEN ub.Class = 1 THEN 1 END) AS Gold,
        COUNT(CASE WHEN ub.Class = 2 THEN 1 END) AS Silver,
        COUNT(CASE WHEN ub.Class = 3 THEN 1 END) AS Bronze,
        COUNT(CASE WHEN ub.TagBased = 1 THEN 1 END) AS TagBasedBadges
    FROM Badges ub
    GROUP BY ub.UserId
),
LatestBadge AS (
    SELECT
        ub.UserId,
        MAX(ub.Date) AS LatestBadgeDate
    FROM Badges ub
    GROUP BY ub.UserId
)
SELECT
    u.Id                 AS UserId,
    u.DisplayName,
    u.Reputation,
    ub.Gold,
    ub.Silver,
    ub.Bronze,
    ub.TagBasedBadges,
    lbd.LatestBadgeDate,
    COUNT(*) OVER (PARTITION BY u.Id) AS AllPosts,
    stm.TagName,
    stm.TagPostCount,
    stm.Questions,
    stm.Answers,
    stm.TotalUpvotes,
    stm.TotalDownvotes,
    stm.LastAccess,
    tr.Rank
FROM Users u
LEFT JOIN UserBadges ub
    ON ub.UserId = u.Id
LEFT JOIN LatestBadge lbd
    ON lbd.UserId = u.Id
LEFT JOIN TagRank tr
    ON tr.UserId = u.Id
LEFT JOIN UserTagStats stm
    ON stm.UserId = u.Id
    AND stm.TagName = tr.TagName
WHERE tr.Rank <= 3
ORDER BY u.Reputation DESC, tr.TagPostCount DESC
LIMIT 200;
