-- {"query": "28085.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1483} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        (u.UpVotes * 1.0 / NULLIF(u.UpVotes + u.DownVotes, 0)) AS ScoreRatio,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        COALESCE(COUNT(b.Id) FILTER (WHERE b.Class = 1), 0) AS GoldBadges,
        COALESCE(COUNT(b.Id) FILTER (WHERE b.Class = 2), 0) AS SilverBadges,
        COALESCE(COUNT(b.Id) FILTER (WHERE b.Class = 3), 0) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
PostAnalysis AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<code>', '')) AS CodeSnippetCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        AVG(p.AnswerCount) OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate)) AS AvgMonthlyAnswers,
        STRING_AGG(DISTINCT t.TagName, ', ' ORDER BY t.TagName) AS AggregatedTags
    FROM Posts p
    LEFT JOIN LATERAL UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><')) AS tag
    ON TRUE
    LEFT JOIN Tags t ON t.TagName = tag
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    CONCAT(SUBSTRING(u.Location FROM 1 FOR 20), ' (', COALESCE(u.WebsiteUrl, 'no website'), ')') AS LocationInfo,
    pa.AggregatedTags,
    ph.CreationDate AS LastClosureDate,
    crt.Name AS CloseReason,
    SUM(pa.Score * (1 + pa.ViewCount * 0.001)) OVER (PARTITION BY u.Id) AS WeightedPostImpact,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = pa.Id AND v.VoteTypeId = 2) AS Upvotes,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = pa.Id AND pl.LinkTypeId = 3) AS DuplicateLinks,
    CASE 
        WHEN u.GoldBadges > 0 THEN 'Expert'
        WHEN u.SilverBadges + u.BronzeBadges > 10 THEN 'Active'
        ELSE 'Standard'
    END AS UserCategory
FROM UserStats u
JOIN PostAnalysis pa ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = pa.Id)
LEFT JOIN PostHistory ph 
    ON pa.Id = ph.PostId 
    AND ph.PostHistoryTypeId = 10
    AND ph.CreationDate = (SELECT MAX(CreationDate) FROM PostHistory WHERE PostId = pa.Id AND PostHistoryTypeId = 10)
LEFT JOIN CloseReasonTypes crt 
    ON CAST(ph.Comment AS INTEGER) = crt.Id
WHERE u.Reputation > 1000
    AND pa.CodeSnippetCount > 5
    AND EXISTS (
        SELECT 1 
        FROM Posts p2 
        WHERE p2.OwnerUserId = u.Id 
        AND p2.PostTypeId = 1 
        AND p2.ClosedDate IS NULL
    )
    AND pa.AvgMonthlyAnswers BETWEEN 5 AND 50
ORDER BY 
    u.ReputationRank, 
    WeightedPostImpact DESC
LIMIT 100;
