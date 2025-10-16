-- {"query": "28020.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1480} 

WITH UserBadgeStats AS (
    SELECT 
        u.Id AS UserId,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date) OVER (PARTITION BY u.Id) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
), PostStats AS (
    SELECT 
        p.OwnerUserId,
        p.PostTypeId,
        COUNT(p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        AVG(p.AnswerCount) FILTER (WHERE p.PostTypeId = 1) AS AvgAnswersPerQuestion,
        (SELECT Score FROM Posts WHERE Id = p.AcceptedAnswerId) AS AcceptedAnswerScore,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS PostRank
    FROM Posts p
    WHERE p.CreationDate BETWEEN '2010-01-01' AND '2023-12-31'
    GROUP BY p.OwnerUserId, p.PostTypeId, p.Id
), CommentActivity AS (
    SELECT 
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        STRING_AGG(LEFT(c.Text, 20), '|') AS CommentPreview
    FROM Comments c
    FULL JOIN Users u ON c.UserId = u.Id
    WHERE c.CreationDate > (NOW() - INTERVAL '5 YEARS')
    GROUP BY c.UserId
), PostCloseAnalysis AS (
    SELECT 
        ph.PostId,
        crt.Name AS CloseReason,
        COUNT(ph.Id) OVER (PARTITION BY ph.PostId) AS CloseEvents,
        ph.CreationDate AS CloseDate,
        (ph.Text::json->>'OriginalQuestionIds')::int[] AS DuplicateOriginals
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON ph.Comment::int = crt.Id
    WHERE ph.PostHistoryTypeId = 10
      AND ph.Text IS NOT NULL
)
SELECT 
    u.Id,
    u.DisplayName,
    COALESCE(ubs.GoldBadges, 0) + COALESCE(ubs.SilverBadges, 0) * 0.5 AS BadgeWeight,
    ps.TotalPosts,
    ps.AvgAnswersPerQuestion,
    ca.TotalComments,
    pca.CloseReason,
    CASE 
        WHEN ps.PostRank <= 10 THEN 'Top'
        WHEN ps.PostRank <= 100 THEN 'High'
        ELSE 'Regular'
    END AS PostRankCategory,
    ROUND(EXP(SUM(LN(NULLIF(ps.TotalScore,0))) OVER (ORDER BY u.Reputation DESC))) AS GeometricMeanScore,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS Upvotes
FROM Users u
LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
LEFT JOIN CommentActivity ca ON u.Id = ca.UserId
LEFT JOIN PostCloseAnalysis pca ON ps.OwnerUserId = u.Id
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
WHERE u.Reputation > 1000
  AND (p.CreationDate BETWEEN '2015-01-01' AND '2023-12-31' OR p.CreationDate IS NULL)
  AND (pca.DuplicateOriginals IS NOT NULL OR ps.AcceptedAnswerScore > 50)
GROUP BY ROLLUP(u.Id, u.DisplayName), ps.TotalPosts, ca.TotalComments, pca.CloseReason, ps.PostRank, p.Id
HAVING COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) > 10
UNION
SELECT 
    u.Id,
    NULL,
    0,
    0,
    0,
    0,
    NULL,
    'Inactive',
    0,
    0
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
ORDER BY BadgeWeight DESC NULLS LAST, GeometricMeanScore
LIMIT 100 OFFSET 10;
