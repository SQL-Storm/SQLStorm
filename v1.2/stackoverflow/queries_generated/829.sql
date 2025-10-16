-- {"query": "829.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1486} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.Id] AS Ancestry
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0
    UNION ALL
    SELECT
        child.Id,
        child.TagName,
        child.Count,
        parent.Ancestry || child.Id
    FROM Tags child
    JOIN Posts p ON p.PostTypeId = 1 AND p.Tags LIKE CONCAT('%<', child.TagName, '>%')
    JOIN RecursiveTagHierarchy parent ON parent.TagName = substring(p.Tags FROM '<([^>]+)>' FOR '#')
    WHERE NOT child.Id = ANY(parent.Ancestry)
),
RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.Reputation,
        u.DisplayName,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC NULLS LAST) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RecentRowNum
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
      AND p.CreationDate > CURRENT_DATE - INTERVAL '1 year'
),
AcceptedAnswerScores AS (
    SELECT
        q.Id AS QuestionId,
        COALESCE(a.Score, 0) AS AcceptedAnswerScore,
        (SELECT AVG(Score) FROM Posts ans WHERE ans.ParentId = q.Id) AS AvgAnswerScore,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id AND c.CreationDate > q.CreationDate) AS CommentsAfterQuestion
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    WHERE q.PostTypeId = 1
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
TopVoters AS (
    SELECT
        v.UserId,
        COUNT(*) AS VoteCount,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.CreationDate > CURRENT_DATE - INTERVAL '6 months'
    GROUP BY v.UserId
    HAVING COUNT(*) > 1000
),
PostLinkAnalysis AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateLinksCount,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE lt.Name = 'Linked') AS LinkedLinksCount
    FROM Posts p
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
)
SELECT 
    rp.Id AS PostId,
    rp.PostTypeId,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.DisplayName AS OwnerName,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    COALESCE(av.AcceptedAnswerScore, 0) AS AcceptedAnswerScore,
    COALESCE(av.AvgAnswerScore, 0) AS AvgAnswerScore,
    COALESCE(av.CommentsAfterQuestion, 0) AS CommentsAfterQuestion,
    COALESCE(tv.VoteCount, 0) AS UserVoteCount,
    COALESCE(tv.UpVotes, 0) AS UserUpVotes,
    COALESCE(tv.DownVotes, 0) AS UserDownVotes,
    pla.DuplicateLinksCount,
    pla.LinkedLinksCount,
    CASE 
        WHEN rp.Score > 10 AND rp.ViewCount > 5000 THEN 'High Impact'
        WHEN rp.Score > 0 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS ImpactCategory,
    CONCAT(
        'Tags: ',
        COALESCE(rp.Tags, '<none>'),
        ' | OwnerRep: ',
        COALESCE(CAST(rp.Reputation AS varchar), 'unknown')
    ) AS SummaryString,
    -- Correlated subquery with NULL logic: count badges awarded after post creation + 30 days
    (
        SELECT COUNT(*)
        FROM Badges bsub
        WHERE bsub.UserId = rp.OwnerUserId
          AND bsub.Date > rp.CreationDate + INTERVAL '30 days'
          AND bsub.Name IS NOT NULL
          AND (bsub.Class = 1 OR bsub.Class = 2)
    ) AS FutureValuableBadges,
    ROW_NUMBER() OVER (PARTITION BY rp.PostTypeId ORDER BY rp.CreationDate DESC) AS RecentPostRank
FROM RankedPosts rp
LEFT JOIN AcceptedAnswerScores av ON av.QuestionId = rp.Id
LEFT JOIN UserBadgeCounts ub ON ub.UserId = rp.OwnerUserId
LEFT JOIN TopVoters tv ON tv.UserId = rp.OwnerUserId
LEFT JOIN PostLinkAnalysis pla ON pla.PostId = rp.Id
WHERE rp.ScoreRank <= 100
  AND (rp.Tags IS NOT NULL AND rp.Tags <> '')
UNION
SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    u.DisplayName AS OwnerName,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS AcceptedAnswerScore,
    0 AS AvgAnswerScore,
    0 AS CommentsAfterQuestion,
    0 AS UserVoteCount,
    0 AS UserUpVotes,
    0 AS UserDownVotes,
    0 AS DuplicateLinksCount,
    0 AS LinkedLinksCount,
    'No Impact' AS ImpactCategory,
    'No Tags | Unknown Owner' AS SummaryString,
    0 AS FutureValuableBadges,
    999999 AS RecentPostRank
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1
  AND p.OwnerUserId IS NULL
ORDER BY ImpactCategory DESC, Score DESC, ViewCount DESC, CreationDate DESC
LIMIT 200;
