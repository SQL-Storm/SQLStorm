-- {"query": "5041.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 905} 
WITH HighReputationUsers AS (
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation, 
           DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    WHERE u.Reputation > 10000
),
RecentQuestions AS (
    SELECT p.Id AS QuestionId, p.Title, p.OwnerUserId, p.Score, p.CreationDate,
           p.AnswerCount, p.ViewCount, p.Tags, 
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecencyRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 0 AND p.CreationDate > (CURRENT_DATE - INTERVAL '180 days')
),
UserBadges AS (
    SELECT b.UserId, COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadgeCount,
           COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadgeCount,
           COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadgeCount
    FROM Badges b
    GROUP BY b.UserId
),
CommentStats AS (
    SELECT c.PostId,
           COUNT(*) AS CommentCount,
           AVG(CASE WHEN c.Score IS NOT NULL THEN c.Score ELSE 0 END) AS AvgCommentScore
    FROM Comments c
    WHERE c.CreationDate > (CURRENT_DATE - INTERVAL '180 days')
    GROUP BY c.PostId
),
RecentEdits AS (
    SELECT ph.PostId, MAX(ph.CreationDate) AS LastEditDate,
           COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditCount
    FROM PostHistory ph
    WHERE ph.CreationDate > (CURRENT_DATE - INTERVAL '180 days')
    GROUP BY ph.PostId
)
SELECT
    hu.UserId,
    hu.DisplayName,
    hu.Reputation,
    hu.ReputationRank,
    qb.GoldBadgeCount, qb.SilverBadgeCount, qb.BronzeBadgeCount,
    rq.QuestionId,
    rq.Title,
    rq.Score AS QuestionScore,
    rq.AnswerCount,
    rq.ViewCount,
    substring(rq.Tags from 1 for 100) AS PreviewTags,
    cs.CommentCount,
    cs.AvgCommentScore,
    re.LastEditDate,
    re.EditCount,
    CASE 
        WHEN cs.CommentCount IS NULL THEN 'No Comments'
        WHEN cs.CommentCount = 0 THEN 'No Comments'
        WHEN cs.AvgCommentScore > 2 THEN 'Highly Praised'
        WHEN cs.AvgCommentScore < 0 THEN 'Controversial'
        ELSE 'Typical'
    END AS CommentStatus,
    CASE 
        WHEN EXISTS (
            SELECT 1
            FROM PostLinks pl
            WHERE pl.PostId = rq.QuestionId AND pl.LinkTypeId = 3
        ) THEN 'Has Duplicate'
        ELSE 'Original'
    END AS DupStatus,
    (
        SELECT COUNT(*)
        FROM Posts ans
        WHERE ans.ParentId = rq.QuestionId
              AND ans.Score > 0
              AND ans.OwnerUserId IS NOT NULL
    ) AS PositiveAnswerCount,
    (
        SELECT string_agg(DISTINCT t.TagName, ', ' ORDER BY t.TagName)
        FROM Tags t
        WHERE '<' || t.TagName || '>' = ANY(
            string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')
        )
    ) AS TagList
FROM HighReputationUsers hu
LEFT JOIN UserBadges qb ON hu.UserId = qb.UserId
LEFT JOIN RecentQuestions rq ON hu.UserId = rq.OwnerUserId AND rq.RecencyRank = 1
LEFT JOIN CommentStats cs ON rq.QuestionId = cs.PostId
LEFT JOIN RecentEdits re ON rq.QuestionId = re.PostId
WHERE (
        qb.GoldBadgeCount > 5 
     OR qb.SilverBadgeCount > 10
     OR qb.BronzeBadgeCount > 20
     OR (hu.ReputationRank <= 20 AND qb.GoldBadgeCount IS NOT NULL)
)
AND hu.ReputationRank <= 100
ORDER BY hu.ReputationRank, rq.CreationDate DESC NULLS LAST
LIMIT 50;