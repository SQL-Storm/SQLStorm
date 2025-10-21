-- {"query": "45077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 361}
WITH TopUserTags AS (
    SELECT u.Id, u.DisplayName, t.TagName, 
           COUNT(p.Id) AS PostCount,
           RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (SELECT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName FROM Posts) t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE u.Reputation > 1000 AND p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, t.TagName
)
SELECT 
    DisplayName,
    STRING_AGG(TagName || ' (' || PostCount || ')', ', ' ORDER BY PostCount DESC) AS TopTags,
    (SELECT AVG(v.Score) 
     FROM Posts p 
     JOIN Votes v ON p.Id = v.PostId 
     WHERE p.OwnerUserId = tut.Id AND v.VoteTypeId = 2) AS AvgUpvotes
FROM TopUserTags tut
WHERE TagRank <= 3
GROUP BY Id, DisplayName
ORDER BY 
    (SELECT COUNT(*) 
     FROM Posts p 
     WHERE p.OwnerUserId = tut.Id AND p.Score > 10) DESC
LIMIT 100;
