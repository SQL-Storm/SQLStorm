-- {"query": "2980.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1776} 

WITH RecursiveUserBadgeSummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        b.Class,
        COUNT(b.Id) AS BadgeCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 1000 AND b.Name IS NOT NULL
    GROUP BY u.Id, u.DisplayName, b.Class, b.Date
    UNION ALL
    SELECT 
        r.UserId,
        r.DisplayName,
        r.Class,
        r.BadgeCount,
        r.BadgeRank
    FROM RecursiveUserBadgeSummary r
    WHERE r.BadgeRank < 3
), PopularQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 0) AS CommentCount,
        COALESCE((SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) FROM Votes v WHERE v.PostId = p.Id), 0) AS UpVotes,
        COALESCE((SELECT SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) FROM Votes v WHERE v.PostId = p.Id), 0) AS DownVotes
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only
      AND p.Score > 10
      AND p.ClosedDate IS NULL
), AnswerStats AS (
    SELECT 
        a.ParentId AS QuestionId,
        COUNT(*) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.CreationDate) AS LatestAnswerDate
    FROM Posts a
    WHERE a.PostTypeId = 2 -- Answers only
    GROUP BY a.ParentId
), UserPostRanks AS (
    SELECT
        p.OwnerUserId,
        p.Id AS PostId,
        p.Score,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS ScoreRank
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
), HighImpactUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS PostsCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1), 0) AS GoldBadges,
        COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2), 0) AS SilverBadges,
        COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3), 0) AS BronzeBadges,
        COALESCE(MAX(p.CreationDate), u.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
), DetailedPosts AS (
    SELECT 
        pq.Id,
        pq.Title,
        pq.OwnerUserId,
        u.DisplayName AS OwnerName,
        pq.Score,
        pq.ViewCount,
        pq.Tags,
        pq.CreationDate,
        ans.AnswerCount,
        ans.AvgAnswerScore,
        ans.LatestAnswerDate,
        pq.CommentCount,
        pq.UpVotes,
        pq.DownVotes,
        CASE 
            WHEN pq.ViewCount > 1000 THEN 'Highly Viewed'
            WHEN pq.ViewCount BETWEEN 500 AND 1000 THEN 'Moderately Viewed'
            ELSE 'Low Views'
        END AS ViewCategory,
        CONCAT(
            COALESCE(SUBSTRING(pq.Title, 1, 10), ''), '...',
            ' [Score:', pq.Score, 
            ', Answers:', COALESCE(ans.AnswerCount,0), 
            ', Comments:', pq.CommentCount, 
            ']'
        ) AS SummaryTitle
    FROM PopularQuestions pq
    LEFT JOIN AnswerStats ans ON ans.QuestionId = pq.Id
    LEFT JOIN Users u ON u.Id = pq.OwnerUserId
), CombinedRankedPosts AS (
    SELECT dp.*, upr.ScoreRank
    FROM DetailedPosts dp
    LEFT JOIN UserPostRanks upr ON upr.PostId = dp.Id
), FilteredPosts AS (
    SELECT *
    FROM CombinedRankedPosts
    WHERE ScoreRank <= 5 OR ScoreRank IS NULL
)
SELECT
    fp.Id AS QuestionId,
    fp.SummaryTitle,
    fp.OwnerUserId,
    fp.OwnerName,
    fp.Score,
    fp.ViewCount,
    fp.ViewCategory,
    fp.Tags,
    fp.CreationDate,
    fp.AnswerCount,
    ROUND(fp.AvgAnswerScore::numeric, 2) AS AvgAnswerScore,
    fp.LatestAnswerDate,
    fp.CommentCount,
    fp.UpVotes,
    fp.DownVotes,
    hu.Reputation,
    hu.PostsCount,
    hu.TotalScore,
    hu.GoldBadges,
    hu.SilverBadges,
    hu.BronzeBadges,
    -- Correlated subquery with NULL handling and string manipulation
    (SELECT STRING_AGG(CONCAT('Badge:', COALESCE(b.Name,'N/A'), '(', b.Class, ')'), ', ' ORDER BY b.Date DESC)
     FROM Badges b
     WHERE b.UserId = fp.OwnerUserId
       AND b.Date > fp.CreationDate - INTERVAL '1 year') AS RecentBadges,

    -- Window function example: rank questions by score partitioned by view category
    RANK() OVER (PARTITION BY fp.ViewCategory ORDER BY fp.Score DESC) AS RankInViewCategory,

    -- Complex expression in predicate simulated as a CASE expression returning a flag
    CASE 
        WHEN fp.UpVotes - fp.DownVotes > 10 AND fp.AnswerCount >= 3 THEN 'Hot Topic'
        WHEN fp.UpVotes - fp.DownVotes BETWEEN 1 AND 10 THEN 'Trending'
        ELSE 'Normal'
    END AS PopularityStatus,

    -- EXISTS subquery with correlated NULL logic
    EXISTS (
        SELECT 1 
        FROM PostLinks pl
        WHERE pl.PostId = fp.Id 
          AND pl.LinkTypeId = 3 -- duplicates
          AND pl.RelatedPostId IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM Posts p2 WHERE p2.Id = pl.RelatedPostId AND p2.Score > fp.Score
          )
    ) AS HasHigherScoredDuplicate

FROM FilteredPosts fp
LEFT JOIN HighImpactUsers hu ON hu.Id = fp.OwnerUserId
WHERE fp.Tags LIKE '%<sql>%'
ORDER BY fp.Score DESC, fp.ViewCount DESC
LIMIT 50

UNION

SELECT 
    p.Id AS QuestionId,
    p.Title AS SummaryTitle,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    p.Score,
    p.ViewCount,
    'Special Union Set' AS ViewCategory,
    p.Tags,
    p.CreationDate,
    0 AS AnswerCount,
    NULL::numeric AS AvgAnswerScore,
    NULL::timestamp AS LatestAnswerDate,
    0 AS CommentCount,
    0 AS UpVotes,
    0 AS DownVotes,
    u.Reputation,
    0 AS PostsCount,
    0 AS TotalScore,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    NULL AS RecentBadges,
    NULL AS RankInViewCategory,
    'New Questions' AS PopularityStatus,
    FALSE AS HasHigherScoredDuplicate
FROM posts p
JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.PostTypeId = 1
  AND p.CreationDate > now() - INTERVAL '7 days'
  AND NOT EXISTS (
      SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 15
  )
ORDER BY p.CreationDate DESC
LIMIT 20;
