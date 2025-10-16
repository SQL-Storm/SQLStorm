-- {"query": "28016.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1460} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE b.Class WHEN 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE b.Class WHEN 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE b.Class WHEN 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        RANK() OVER (PARTITION BY b.Class ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, b.Class
), PostAnalysis AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.AnswerCount,
        p.Tags,
        ph.CreationDate AS LastCloseAttempt,
        crt.Name AS CloseReason,
        COUNT(c.Id) FILTER (WHERE c.Score > 0) AS HighScoreComments,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserPostRank
    FROM Posts p
    LEFT JOIN PostHistory ph 
        ON p.Id = ph.PostId 
        AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes crt 
        ON CAST(ph.Comment AS SMALLINT) = crt.Id
    LEFT JOIN Comments c 
        ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
        AND (p.ClosedDate IS NOT NULL OR p.AnswerCount > 5)
        AND p.OwnerUserId != -1
    GROUP BY p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.AnswerCount, p.Tags, ph.CreationDate, crt.Name
)
SELECT 
    pa.Title,
    pa.Score,
    pa.CloseReason,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.ReputationRank,
    (SELECT COUNT(*) FROM Comments WHERE PostId = pa.Id) AS TotalComments,
    (SELECT AVG(Score) FROM Posts WHERE ParentId = pa.Id) AS AvgAnswerScore,
    COALESCE(SUBSTRING(pa.Tags FROM 2 FOR POSITION('>' IN pa.Tags) - 2), 'untagged') AS PrimaryTag,
    EXTRACT(YEAR FROM pa.CreationDate) AS PostYear,
    CASE 
        WHEN pa.UserPostRank = 1 THEN 'Top User Post'
        WHEN pa.UserPostRank <= 5 THEN 'High User Post' 
        ELSE 'Regular Post' 
    END AS PostSignificance,
    COALESCE(u.DisplayName, 'Deleted User') AS Author,
    (u.UpVotes * 1.0 / NULLIF(u.DownVotes, 0)) AS VoteRatio
FROM PostAnalysis pa
JOIN UserStats u ON pa.OwnerUserId = u.Id
WHERE pa.Score > 50 OR pa.CloseReason IS NOT NULL
UNION
SELECT 
    p.Title,
    p.Score,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    EXTRACT(YEAR FROM p.CreationDate),
    'Legacy Post',
    'Community',
    NULL
FROM Posts p
WHERE p.OwnerUserId = -1 AND p.Score > 100
ORDER BY PostYear DESC, Score DESC;
