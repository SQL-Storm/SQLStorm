-- {"query": "45041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 456}
WITH ActiveUserTags AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        t.TagName, 
        COUNT(*) AS TagPostCount,
        RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank
    FROM 
        Users u
        JOIN Posts p ON u.Id = p.OwnerUserId
        CROSS APPLY string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') tags(TagName)
        JOIN Tags t ON tags.TagName = t.TagName
    WHERE 
        p.PostTypeId = 1 
        AND u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName, t.TagName
), TopExpertUsers AS (
    SELECT 
        UserId, 
        DisplayName, 
        MAX(TagPostCount) AS MaxTagPostCount,
        STRING_AGG(TagName, ', ' ORDER BY TagPostCount DESC) AS TopTags
    FROM 
        ActiveUserTags
    WHERE 
        TagRank <= 3
    GROUP BY 
        UserId, DisplayName
)
SELECT 
    e.UserId,
    e.DisplayName,
    e.TopTags,
    e.MaxTagPostCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = e.UserId AND v.VoteTypeId = 2) AS UpVoteCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = e.UserId AND b.Class = 1) AS GoldBadgeCount
FROM 
    TopExpertUsers e
WHERE 
    e.MaxTagPostCount > 10
ORDER BY 
    e.MaxTagPostCount DESC, 
    UpVoteCount DESC
LIMIT 100;
