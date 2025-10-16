-- {"query": "28010.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1560} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        STRING_AGG(DISTINCT SUBSTRING(b.Name FROM 1 FOR 3), ';') AS BadgePrefixes
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate BETWEEN '2010-01-01' AND '2020-12-31'
    GROUP BY u.Id
),
PostAnalysis AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        ph.CreationDate AS LastEditDate,
        COALESCE(ph.UserId, -1) AS LastEditorId,
        LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<code>', '')) AS CodeBlockCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinks,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserPostRank
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
        AND ph.PostHistoryTypeId IN (5,6,7)
        AND ph.CreationDate = (
            SELECT MAX(CreationDate)
            FROM PostHistory
            WHERE PostId = p.Id
            AND PostHistoryTypeId IN (5,6,7)
        )
    WHERE p.PostTypeId IN (1,2)
)
SELECT 
    us.Id AS UserId,
    us.Reputation,
    us.ReputationRank,
    us.AvgPostScore,
    pa.PostTypeId,
    pa.Score AS PostScore,
    pa.UserPostRank,
    pa.Upvotes,
    pa.DuplicateLinks,
    pa.CodeBlockCount,
    (us.QuestionsAsked * 2 + us.AnswersProvided) * us.Reputation / 1000 AS EngagementIndex,
    ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(pa.Tags FROM 2 FOR LENGTH(pa.Tags)-2), '><'), 1) AS TagCount,
    EXTRACT(YEAR FROM AGE(pa.LastEditDate, pa.CreationDate)) * 12 +
    EXTRACT(MONTH FROM AGE(pa.LastEditDate, pa.CreationDate)) AS EditMonthsAfterCreation,
    CASE 
        WHEN us.Reputation > 100000 THEN 'Legendary'
        WHEN us.Reputation BETWEEN 50000 AND 100000 THEN 'Epic'
        WHEN us.Reputation BETWEEN 10000 AND 49999 THEN 'Advanced'
        ELSE 'Regular'
    END AS ReputationTier,
    COALESCE(ph.Comment, 'No edit reason') AS LastEditComment,
    (SELECT STRING_AGG(Name, ', ' ORDER BY Date DESC LIMIT 3) 
     FROM Badges 
     WHERE UserId = us.Id AND Class = 1) AS Top3GoldBadges
FROM UserStats us
JOIN PostAnalysis pa ON us.Id = (SELECT OwnerUserId FROM Posts WHERE Id = pa.Id)
LEFT JOIN PostHistory ph ON pa.Id = ph.PostId
    AND ph.CreationDate = pa.LastEditDate
WHERE us.Reputation > 1000
    AND (pa.Score > 100 OR pa.ViewCount > 1000)
    AND (pa.Tags LIKE '%<sql>%' OR pa.Tags IS NULL)
    AND (us.BadgePrefixes LIKE '%exp%' OR us.BadgePrefixes IS NULL)
ORDER BY 
    us.ReputationRank,
    pa.UserPostRank,
    EngagementIndex DESC
LIMIT 500;
