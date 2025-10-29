-- {"query": "5971.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 460} 
SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    MAX(p.CreationDate) AS LastActive,
    COALESCE(SUM(v.BountyAmount),0) AS TotalBounties,
    STRING_AGG(DISTINCT t.Name, ', ') AS TagsContributed,
    AVG(NULLIF(v4.Score,0)) OVER (PARTITION BY u.Id) AS AvgScorePerPost,
    CASE
        WHEN u.Reputation > 20000 THEN 'Elite'
        WHEN u.Reputation > 1000 THEN 'Rising'
        ELSE 'Newbie'
    END AS Tier,
    COUNT(DISTINCT bl.Id) AS BadgesEarned
FROM
    Users u
LEFT JOIN
    Posts p ON p.OwnerUserId = u.Id
LEFT JOIN
    Votes v ON v.UserId = u.Id
LEFT JOIN
    Votes v4 ON v4.UserId = u.Id
LEFT JOIN
    Badges bl ON bl.UserId = u.Id
LEFT JOIN
    (
        SELECT
            p2.OwnerUserId AS UserId,
            UNNEST(string_to_array(p2.Tags, ',')) AS t
        FROM Posts p2
        WHERE p2.Tags IS NOT NULL
    ) AS tag_exp ON tag_exp.UserId = u.Id
LEFT JOIN
    (
        SELECT
            p3.Id,
            unnest(string_to_array(p3.Tags, '>next<')) AS Name
        FROM Posts p3
        WHERE p3.Tags IS NOT NULL
    ) AS ttmp ON ttmp.Id = p.Id
LEFT JOIN
    PostLinks pl ON pl.PostId = p.Id
LEFT JOIN
    LinkTypes lt ON lt.Id = pl.LinkTypeId
GROUP BY
    u.Id, u.DisplayName, u.Reputation
ORDER BY
    LastActive DESC
LIMIT 100;