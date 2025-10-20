WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalUserPosts
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
), UserBadgesCount AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
), LatestUserActivity AS (
    SELECT 
        u.Id AS UserId,
        COALESCE(MAX(ph.CreationDate), u.LastAccessDate) AS LastActivityDate
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id, u.LastAccessDate
), TopTags AS (
    SELECT DISTINCT
        regexp_split_to_table(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><') AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1
), ActiveQuestions AS (
    SELECT 
        p1.Id,
        p1.Title,
        p1.OwnerUserId,
        p1.Score,
        p1.ViewCount,
        p1.CreationDate,
        best_ans.Len as AnswerBodyLength,
        clt.Name AS CloseReason,
        LAG(p1.Score) OVER (ORDER BY p1.CreationDate) AS PrevScore,
        LEAD(p1.Score) OVER (ORDER BY p1.CreationDate) AS NextScore,
        EXISTS (
            SELECT 1 FROM Votes v 
            WHERE v.PostId = p1.Id AND v.VoteTypeId = 2
            AND v.CreationDate > p1.CreationDate + INTERVAL '30' DAY
        ) AS HasLateUpvotes
    FROM Posts p1 
    LEFT JOIN (
        SELECT a.ParentId, LENGTH(a.Body) AS Len FROM Posts a WHERE a.PostTypeId = 2
    ) AS best_ans ON best_ans.ParentId = p1.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p1.Id AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes clt ON clt.Id = CAST(ph.Comment AS INTEGER)
    WHERE p1.PostTypeId = 1
      AND p1.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '365' DAY
), DuplicateQuestions AS (
    SELECT pl.PostId, COUNT(*) AS DuplicateCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId
)
SELECT 
    u.Id AS UserId,
    COALESCE(u.DisplayName, 'NoName') AS DisplayName,
    u.Reputation,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ua.LastActivityDate,
    rp.UserPostRank,
    rp.TotalUserPosts,
    rp.Score AS PostScore,
    rp.ViewCount,
    rp.Tags,
    dq.DuplicateCount,
    aq.Title,
    aq.CloseReason,
    aq.AnswerBodyLength,
    aq.HasLateUpvotes,
    CASE
        WHEN rp.ViewCount IS NULL OR rp.ViewCount = 0 THEN LEAST(NULL, rp.Score * 10)
        ELSE LEAST(rp.ViewCount, rp.Score * 10)
    END AS PopularityIndex,
    CASE
        WHEN u.Reputation > 10000 THEN 'Expert'
        WHEN u.Reputation BETWEEN 1000 AND 10000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserLevel,
    regexp_replace(
        COALESCE(rp.Tags, '<non-tag>'),
        '^<|>$', ''
    ) AS TagsClean,
    CASE 
        WHEN aq.CloseReason IS NOT NULL THEN 'Closed' 
        ELSE 'Open' 
    END AS QuestionStatus,
    aq.CreationDate AS QuestionCreationDate
FROM RankedPosts rp
INNER JOIN Users u ON u.Id = rp.OwnerUserId
LEFT JOIN UserBadgesCount ubc ON ubc.UserId = u.Id
LEFT JOIN LatestUserActivity ua ON ua.UserId = u.Id
LEFT JOIN ActiveQuestions aq ON aq.Id = rp.Id
LEFT JOIN DuplicateQuestions dq ON dq.PostId = rp.Id
WHERE rp.UserPostRank <= 3
  AND COALESCE(u.Reputation, 0) > 100
  AND (rp.Score > 0 OR rp.ViewCount > 1000)
ORDER BY u.Reputation DESC, rp.Score DESC, aq.CreationDate DESC
LIMIT 100;