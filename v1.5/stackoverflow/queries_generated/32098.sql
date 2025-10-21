-- {"query": "32098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 441} 

SELECT
    u.DisplayName,
    u.Reputation,
    u.Location,
    p.PostCount,
    b.BadgeCount,
    COALESCE(q.AcceptedAnswerCount, 0) AS AcceptedAnswerCount,
    COALESCE(a.AnswerScoreSum, 0) AS AnswerScoreSum,
    t.Tags
FROM
    Users u
LEFT JOIN (
    SELECT
        OwnerUserId,
        COUNT(*) AS PostCount
    FROM
        Posts
    GROUP BY
        OwnerUserId
) p ON u.Id = p.OwnerUserId
LEFT JOIN (
    SELECT
        UserId,
        COUNT(*) AS BadgeCount
    FROM
        Badges
    GROUP BY
        UserId
) b ON u.Id = b.UserId
LEFT JOIN (
    SELECT
        OwnerUserId,
        COUNT(*) AS AcceptedAnswerCount
    FROM
        Posts
    WHERE
        PostTypeId = 1
        AND AcceptedAnswerId IS NOT NULL
    GROUP BY
        OwnerUserId
) q ON u.Id = q.OwnerUserId
LEFT JOIN (
    SELECT
        ParentId,
        SUM(Score) AS AnswerScoreSum
    FROM
        Posts
    WHERE
        PostTypeId = 2
    GROUP BY
        ParentId
) a ON u.Id = a.ParentId
LEFT JOIN (
    SELECT
        OwnerUserId,
        STRING_AGG(DISTINCT t.TagName, ', ') AS Tags
    FROM
        Posts p
    JOIN (
        SELECT
            unnest(string_to_array(substring(Tags, 2, length(Tags) - 2), '><')) AS TagName,
            OwnerUserId
        FROM
            Posts
        WHERE
            PostTypeId = 1
    ) t ON p.OwnerUserId = t.OwnerUserId
    GROUP BY
        OwnerUserId
) t ON u.Id = t.OwnerUserId
WHERE
    u.CreationDate > CURRENT_DATE - INTERVAL '1 year'
ORDER BY
    u.Reputation DESC,
    p.PostCount DESC;
