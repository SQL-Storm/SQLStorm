-- {"query": "15078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 184465, "output_tokens": 54299} 
WITH ActiveUserTags AS (
    SELECT u.Id AS UserId, 
           t.TagName, 
           COUNT(p.Id) AS PostCount,
           ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(p.Id) DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN (SELECT unnest(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName, Id FROM Posts) t ON t.Id = p.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, t.TagName
),
RankedPostActivity AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        u.DisplayName,
        v.VoteCount,
        DENSE_RANK() OVER (ORDER BY p.ViewCount * p.Score DESC) AS PostPopularityRank,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community'
            ELSE 'Active'
        END AS PostStatus
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VoteCount 
        FROM Votes 
        WHERE VoteTypeId IN (2, 3) 
        GROUP BY PostId
    ) v ON p.Id = v.PostId
)
SELECT 
    rpa.Id AS PostId,
    rpa.Title,
    rpa.DisplayName AS Author,
    rpa.Score,
    rpa.ViewCount,
    rpa.VoteCount,
    rpa.PostPopularityRank,
    rpa.PostStatus,
    COALESCE(aut.TagName, 'No Dominant Tag') AS DominantTag,
    ROUND(
        (rpa.Score * 1.5 + rpa.ViewCount * 0.5 + COALESCE(rpa.VoteCount, 0) * 2.0) / 
        NULLIF(EXTRACT(EPOCH FROM (NOW() - p.CreationDate)) / 86400, 0), 
        2
    ) AS ActivityDensityScore
FROM RankedPostActivity rpa
LEFT JOIN ActiveUserTags aut ON rpa.DisplayName = u.DisplayName AND aut.TagRank = 1
JOIN Posts p ON rpa.Id = p.Id
WHERE 
    rpa.PostPopularityRank <= 500
    AND (
        p.Tags LIKE '%<sql>%' 
        OR p.Tags LIKE '%<database>%' 
        OR p.Title ILIKE '%query%performance%'
    )
ORDER BY ActivityDensityScore DESC
LIMIT 100;