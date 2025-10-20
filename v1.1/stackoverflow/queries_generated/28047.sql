-- {"query": "28047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1508} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserJoinDate,
        COALESCE(u.DisplayName, 'Anonymous') AS DisplayName,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.Tags,
        STRING_AGG(DISTINCT ph.Text, ' | ') AS EditHistory,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRecencyRank
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (2,5,8)
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.ClosedDate IS NULL OR p.ClosedDate > CURRENT_TIMESTAMP - INTERVAL '1 YEAR'
    GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate, p.Score, p.AnswerCount, p.Tags
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    pa.PostId,
    pa.Score AS PostScore,
    pa.Upvotes - pa.Downvotes AS NetVotes,
    pa.Tags,
    CASE 
        WHEN pa.Tags LIKE '%<sql>%' THEN 'SQL Expert'
        WHEN pa.Tags LIKE '%<python>%' THEN 'Python Expert'
        ELSE 'Generalist'
    END AS TagCategory,
    LENGTH(pa.EditHistory) - LENGTH(REPLACE(pa.EditHistory, '|', '')) + 1 AS EditCount,
    (SELECT AVG(AnswerCount) FROM Posts WHERE OwnerUserId = us.UserId AND PostTypeId = 1) AS AvgAnswersPerQuestion,
    COALESCE(pl.RelatedPostCount, 0) AS RelatedPosts,
    us.AvgPostScore / NULLIF(us.TotalPosts, 0) AS EngagementRatio
FROM UserStats us
INNER JOIN PostAnalysis pa ON us.UserId = pa.OwnerUserId AND pa.PostRecencyRank = 1
LEFT JOIN (
    SELECT 
        PostId,
        COUNT(DISTINCT RelatedPostId) AS RelatedPostCount
    FROM PostLinks 
    WHERE LinkTypeId = 1
    GROUP BY PostId
) pl ON pa.PostId = pl.PostId
WHERE us.Reputation > 1000
    AND us.UserJoinDate < CURRENT_TIMESTAMP - INTERVAL '3 YEARS'
    AND EXISTS (
        SELECT 1 
        FROM Votes 
        WHERE UserId = us.UserId 
        AND CreationDate > CURRENT_TIMESTAMP - INTERVAL '6 MONTHS'
    )
ORDER BY 
    us.Reputation DESC, 
    EngagementRatio DESC NULLS LAST
LIMIT 100;
