-- {"query": "2007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 414} 

WITH RecentHighReputationUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) AS BadgeCount
    FROM
        Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE
        u.Reputation > 10000
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation
    HAVING
        COUNT(b.Id) > 5
),
TagUsage AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT t.Id) AS UniqueTagsCount
    FROM
        Posts p
    INNER JOIN LATERAL (
        SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) AS TagNames ON TRUE
    INNER JOIN Tags t ON t.TagName = TagNames.TagName
    WHERE
        p.PostTypeId = 1
    GROUP BY
        p.OwnerUserId
),
TopQuestionsByViews AS (
    SELECT
        p.Id,
        p.Title,
        p.ViewCount,
        RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewRank
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
)
SELECT
    rhu.UserId,
    rhu.DisplayName,
    rhu.Reputation,
    tu.UniqueTagsCount,
    tq.Id AS TopQuestionId,
    tq.Title AS TopQuestionTitle,
    tq.ViewCount AS QuestionViews
FROM
    RecentHighReputationUsers rhu
LEFT JOIN TagUsage tu ON rhu.UserId = tu.OwnerUserId
LEFT JOIN TopQuestionsByViews tq ON tq.ViewRank <= 5
WHERE
    rhu.Reputation > (SELECT AVG(u.Reputation) FROM Users u WHERE u.Reputation > 0)
ORDER BY
    rhu.Reputation DESC,
    tq.ViewCount DESC;
