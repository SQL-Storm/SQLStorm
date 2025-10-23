-- {"query": "1361.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1052} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST, p.CreationDate DESC) AS UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalUserPosts
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions or Answers
), UserBadgesCount AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
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
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
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
            WHERE v.PostId = p1.Id AND v.VoteTypeId = 2 -- UpMod
            AND v.CreationDate > p1.CreationDate + interval '30 days'
        ) AS HasLateUpvotes
    FROM Posts p1 
    LEFT JOIN (
        SELECT a.ParentId, length(a.Body) AS Len FROM Posts a WHERE a.PostTypeId = 2
    ) AS best_ans ON best_ans.ParentId = p1.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p1.Id AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes clt ON clt.Id = ph.Comment::int
    WHERE p1.PostTypeId = 1
      AND p1.CreationDate >= cast('2024-10-01' as date) - interval '365 days' -- last 1 year
), DuplicateQuestions AS (
    SELECT pl.PostId, count(*) AS DuplicateCount
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
    LEAST(NULLIF(rp.ViewCount, 0), rp.Score * 10) AS PopularityIndex,
    CASE
        WHEN u.Reputation > 10000 THEN 'Expert'
        WHEN u.Reputation BETWEEN 1000 AND 10000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserLevel,
    REGEXP_REPLACE(
        COALESCE(rp.Tags, '<non-tag>'),
        '^<|>$', '', -- remove edge < and >
        'g'
    ) AS TagsClean,
    CASE 
        WHEN aq.CloseReason IS NOT NULL THEN 'Closed' 
        ELSE 'Open' 
    END AS QuestionStatus
FROM RankedPosts rp
INNER JOIN Users u ON u.Id = rp.OwnerUserId
LEFT JOIN UserBadgesCount ubc ON ubc.UserId = u.Id
LEFT JOIN LatestUserActivity ua ON ua.UserId = u.Id
LEFT JOIN ActiveQuestions aq ON aq.Id = rp.Id
LEFT JOIN DuplicateQuestions dq ON dq.PostId = rp.Id
WHERE rp.UserPostRank <= 3
  AND COALESCE(u.Reputation, 0) > 100
  AND (rp.Score > 0 OR rp.ViewCount > 1000)
ORDER BY u.Reputation DESC NULLS LAST, rp.Score DESC NULLS LAST, aq.CreationDate DESC NULLS LAST
LIMIT 100;