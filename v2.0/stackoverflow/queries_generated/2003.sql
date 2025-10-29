-- {"query": "2003.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1449} 

WITH RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, t.Count, t.IsModeratorOnly, t.IsRequired, p.Id AS ExcerptPostId, p.Title AS ExcerptTitle
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
    WHERE t.IsModeratorOnly = 0

    UNION ALL

    SELECT t.Id, t.TagName, t.Count, t.IsModeratorOnly, t.IsRequired, p.Id, p.Title
    FROM Tags t
    INNER JOIN RecursiveTagHierarchy rth ON t.Id <> rth.Id AND t.Count < rth.Count
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
    WHERE t.IsModeratorOnly = 0
),
UserReputationRanked AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST, u.CreationDate ASC) AS RepRank,
           COALESCE(u.Location, 'Unknown') AS LocationNormalized,
           u.CreationDate,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
    WHERE u.Reputation IS NOT NULL
),
PostsWithActivity AS (
    SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Title, p.Tags, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount,
           p.AcceptedAnswerId,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostOrderDesc,
           COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS UserPostCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
TopAnswersWithParent AS (
    SELECT a.Id, a.ParentId, a.Score AS AnswerScore, a.CreationDate AS AnswerCreationDate,
           q.Id AS QuestionId, q.Title AS QuestionTitle, q.Score AS QuestionScore, q.ViewCount AS QuestionViewCount,
           u.DisplayName AS AnswererName, u.Reputation AS AnswererRep,
           COALESCE(u.Location, 'Unknown') AS AnswererLocation
    FROM Posts a
    LEFT JOIN Posts q ON a.ParentId = q.Id AND q.PostTypeId = 1
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2 AND a.Score > 10
),
UserBadgeStats AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldCount,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverCount,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeCount
    FROM Badges b
    GROUP BY b.UserId
),
UserCommentCounts AS (
    SELECT c.UserId, COUNT(*) AS CommentCount
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
FinalUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.LocationNormalized, u.CreationDate, u.RepRank,
           COALESCE(ubs.GoldCount,0) AS GoldBadges, COALESCE(ubs.SilverCount,0) AS SilverBadges, COALESCE(ubs.BronzeCount,0) AS BronzeBadges,
           COALESCE(uc.CommentCount,0) AS CommentCount
    FROM UserReputationRanked u
    LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
    LEFT JOIN UserCommentCounts uc ON u.Id = uc.UserId
    WHERE u.RepRank <= 1000
)
SELECT DISTINCT
       f.Id AS UserId,
       f.DisplayName,
       f.Reputation,
       f.LocationNormalized,
       f.GoldBadges,
       f.SilverBadges,
       f.BronzeBadges,
       f.CommentCount,
       p.Id AS PostId,
       p.PostTypeId,
       p.CreationDate AS PostCreationDate,
       p.Title AS PostTitle,
       p.Score AS PostScore,
       p.ViewCount AS PostViewCount,
       p.AnswerCount,
       p.FavoriteCount,
       COALESCE(pa.AnswerScore, 0) AS AnswerScore,
       pa.QuestionTitle,
       pa.QuestionScore,
       pa.QuestionViewCount,
       pa.AnswererName,
       CASE 
           WHEN pa.AnswerCreationDate > p.CreationDate THEN 'After Question'
           ELSE 'Before or Same Date'
       END AS AnswerTimingRelativeToQuestion,
       CONCAT_WS(' | ', 
            COALESCE(p.Tags, ''),
            CONCAT('AnswersByUser:', CAST(p.UserPostCount AS VARCHAR)),
            CONCAT('PostOrder:', CAST(p.UserPostOrderDesc AS VARCHAR))
        ) AS TagAndPostInfo,
       STRING_AGG(ph.Name || ': ' || COALESCE(phx.Text, 'N/A'), '; ' ORDER BY ph.Name) AS PostHistorySummary
FROM FinalUsers f
LEFT JOIN PostsWithActivity p ON p.OwnerUserId = f.Id
LEFT JOIN TopAnswersWithParent pa ON pa.ParentId = p.Id
LEFT JOIN PostHistoryTypes ph ON ph.Id = (
    SELECT ph2.PostHistoryTypeId 
    FROM PostHistory ph2 
    WHERE ph2.PostId = p.Id 
    ORDER BY ph2.CreationDate DESC 
    LIMIT 1
)
LEFT JOIN PostHistory phx ON phx.PostHistoryTypeId = ph.Id AND phx.PostId = p.Id
WHERE p.Score > (
    SELECT AVG(p2.Score) * 0.5 
    FROM Posts p2 
    WHERE p2.OwnerUserId = f.Id AND p2.PostTypeId = p.PostTypeId
)
AND (
    f.LocationNormalized LIKE '%United%'
    OR f.LocationNormalized LIKE '%States%'
)
AND EXISTS (
    SELECT 1 FROM Votes v
    WHERE v.PostId = p.Id
    AND v.VoteTypeId = 2 -- UpMod
    AND v.CreationDate > p.CreationDate
    AND v.UserId IS NOT NULL
    AND v.UserId <> f.Id
)
AND NOT EXISTS (
    SELECT 1 FROM PostLinks pl
    WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3 -- Duplicates
)
ORDER BY f.Reputation DESC, p.Score DESC
LIMIT 500
;
