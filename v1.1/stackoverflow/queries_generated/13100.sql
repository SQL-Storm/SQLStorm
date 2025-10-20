-- {"query": "13100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 653} 

WITH RankedAnswers AS (
    SELECT 
        p.Id,
        p.ParentId,
        p.CreationDate,
        p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnswerRank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 2 AND p.Score > 0
),
TopContributors AS (
    SELECT 
        u.Id,
        u.DisplayName,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (5, 8) THEN LENGTH(ph.Text) ELSE 0 END) AS TotalEditLength,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges
    FROM 
        Users u
    LEFT JOIN 
        PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName
    HAVING 
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) > 0
),
FilteredPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.Score,
        COALESCE(STRING_AGG(DISTINCT t.TagName, ', '), 'No Tags') AS TagNames
    FROM 
        Posts p
    LEFT JOIN 
        Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE 
        p.PostTypeId = 1 AND p.Score > 10 AND p.ClosedDate IS NULL
    GROUP BY 
        p.Id, p.Title, p.Tags, p.OwnerUserId, p.Score
)
SELECT 
    fp.Id AS QuestionId,
    fp.Title,
    fp.TagNames,
    u.DisplayName AS OwnerDisplayName,
    tc.DisplayName AS TopContributorDisplayName,
    tc.GoldBadges,
    ra.AnswerRank,
    ra.Score AS AnswerScore,
    RANK() OVER (ORDER BY fp.Score DESC, tc.TotalEditLength DESC) AS OverallRank
FROM 
    FilteredPosts fp
JOIN 
    RankedAnswers ra ON fp.Id = ra.ParentId AND ra.AnswerRank = 1
LEFT JOIN 
    Users u ON fp.OwnerUserId = u.Id
LEFT JOIN 
    TopContributors tc ON fp.OwnerUserId = tc.Id
WHERE 
    LENGTH(fp.Title) > 15
ORDER BY 
    OverallRank
LIMIT 100;
