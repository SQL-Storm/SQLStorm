-- {"query": "23096.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 933} 

WITH TopTags AS (
    SELECT 
        t.Id, 
        t.TagName, 
        t.Count AS TagCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 1000
),
UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
    HAVING COUNT(b.Id) > 5
),
RecentPosts AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><') AS TagArray,
        COALESCE(p.AnswerCount, 0) AS Answers,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM Posts p
    WHERE p.PostTypeId = 1  -- Questions
    AND p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year'
    AND p.Tags IS NOT NULL
),
PostActivity AS (
    SELECT 
        rp.PostId,
        rp.OwnerUserId,
        rp.Score,
        rp.ViewCount,
        rp.Answers,
        rp.PostRank,
        COUNT(DISTINCT v.Id) AS Upvotes,
        AVG(CASE WHEN c.Score > 0 THEN c.Score ELSE NULL END) AS AvgCommentScore,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = rp.PostId AND ph.PostHistoryTypeId IN (4,5,6)) AS EditCount
    FROM RecentPosts rp
    LEFT JOIN Votes v ON rp.PostId = v.PostId AND v.VoteTypeId = 2  -- Upvotes
    LEFT JOIN Comments c ON rp.PostId = c.PostId
    GROUP BY rp.PostId, rp.OwnerUserId, rp.Score, rp.ViewCount, rp.Answers, rp.PostRank
    HAVING COUNT(v.Id) > 10 OR AVG(c.Score) > 1
)
SELECT 
    u.DisplayName,
    u.Reputation,
    ubs.GoldBadges,
    ubs.SilverBadges,
    pa.PostId,
    pa.Score,
    pa.ViewCount,
    pa.Upvotes,
    pa.AvgCommentScore,
    pa.EditCount,
    tt.TagName AS TopTag,
    CASE 
        WHEN pa.Answers > 0 THEN pa.Score / NULLIF(pa.Answers, 0) 
        ELSE 0 
    END AS ScorePerAnswer,
    CONCAT_WS(' ', u.Location, 'Reputation:', u.Reputation) AS UserInfo,
    EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = pa.PostId AND pl.LinkTypeId = 3) AS IsDuplicate
FROM Users u
INNER JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
RIGHT OUTER JOIN PostActivity pa ON u.Id = pa.OwnerUserId
LEFT JOIN TopTags tt ON tt.TagName = ANY(pa.TagArray) AND tt.TagRank <= 10
WHERE u.Reputation > 10000
AND (pa.PostRank = 1 OR pa.EditCount > 3)
AND (u.AboutMe IS NULL OR LENGTH(u.AboutMe) > 100)
UNION
SELECT 
    NULL AS DisplayName,
    NULL AS Reputation,
    NULL AS GoldBadges,
    NULL AS SilverBadges,
    p.Id AS PostId,
    p.Score,
    p.ViewCount,
    COUNT(v.Id) AS Upvotes,
    NULL AS AvgCommentScore,
    NULL AS EditCount,
    NULL AS TopTag,
    NULL AS ScorePerAnswer,
    'Anonymous Posts' AS UserInfo,
    FALSE AS IsDuplicate
FROM Posts p
LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 2
WHERE p.OwnerUserId IS NULL
AND p.PostTypeId = 1
GROUP BY p.Id, p.Score, p.ViewCount
HAVING COUNT(v.Id) > 5
ORDER BY Reputation DESC NULLS LAST, Score DESC;
