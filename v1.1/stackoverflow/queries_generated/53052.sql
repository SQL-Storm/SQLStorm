-- {"query": "53052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 421} 

WITH Stats AS (
    SELECT 
        p.Id,
        p.Title,
        p.Tags,
        p.ViewCount,
        p.Score,
        u.DisplayName,
        u.Reputation,
        COUNT(c.Id) AS Comments,
        COUNT(v.Id) AS Votes,
        COUNT(ph.Id) AS Edits,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id OR pl.RelatedPostId = p.Id) AS Links,
        COUNT(a.Id) AS Answers,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId) AS UserBadges
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN Posts a ON a.ParentId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.Tags, p.ViewCount, p.Score, u.DisplayName, u.Reputation, p.OwnerUserId
),
TaggedStats AS (
    SELECT 
        s.*,
        t.tag,
        ROW_NUMBER() OVER (PARTITION BY t.tag ORDER BY s.ViewCount DESC, s.Score DESC) AS RankInTag
    FROM Stats s
    CROSS JOIN LATERAL unnest(string_to_array(substring(s.Tags, 2, length(s.Tags) - 2), '><')) t(tag)
)
SELECT 
    ts.Id,
    ts.Title,
    ts.tag,
    ts.ViewCount,
    ts.Score,
    ts.DisplayName,
    ts.Reputation,
    ts.Comments,
    ts.Votes,
    ts.Edits,
    ts.Links,
    ts.Answers,
    ts.UserBadges,
    ts.RankInTag
FROM TaggedStats ts
WHERE ts.RankInTag <= 10
ORDER BY ts.tag, ts.RankInTag;
