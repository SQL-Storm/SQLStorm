-- {"query": "2027.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 646} 

WITH TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesCount
    FROM
        Users u
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, u.DisplayName
    HAVING
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) >= 1000
),
PostProximity AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate DESC) AS Rn
    FROM
        PostLinks pl
    WHERE
        pl.LinkTypeId = 1
),
ActivePostUsers AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS ActivePostsCount
    FROM
        Posts p
    WHERE
        p.LastActivityDate > NOW() - INTERVAL '1 year'
    GROUP BY
        p.OwnerUserId
),
CorelationExample AS (
    SELECT
        p.Id AS PostId,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS PositiveComments
    FROM
        Posts p
),
LatestQuestionsTags AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        STRING_AGG(t.TagName, ', ') AS Tags
    FROM
        Posts q
    JOIN
        Tags t ON q.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE
        q.PostTypeId = 1
        AND q.CreationDate > NOW() - INTERVAL '30 days'
    GROUP BY
        q.Id, q.Title
)
SELECT
    u.DisplayName,
    tu.UpVotesCount,
    apu.ActivePostsCount,
    pq.ProximityPostId,
    ce.PositiveComments,
    lqt.Tags
FROM
    TopUsers tu
JOIN
    Users u ON tu.UserId = u.Id
LEFT JOIN
    ActivePostUsers apu ON u.Id = apu.OwnerUserId
LEFT JOIN (
    SELECT
        p.PostId,
        p.RelatedPostId AS ProximityPostId
    FROM
        PostProximity p
    WHERE
        p.Rn = 1
) pq ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = pq.PostId)
LEFT JOIN
    CorelationExample ce ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = ce.PostId)
LEFT JOIN
    LatestQuestionsTags lqt ON lqt.QuestionId = (SELECT Id FROM Posts WHERE OwnerUserId = u.Id ORDER BY CreationDate DESC LIMIT 1)
WHERE
    tu.UpVotesCount > 2000
    OR apu.ActivePostsCount > 50
ORDER BY
    tu.UpVotesCount DESC, apu.ActivePostsCount DESC
LIMIT 100;
