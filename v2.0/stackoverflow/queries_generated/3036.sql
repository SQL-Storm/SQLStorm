-- {"query": "3036.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2341} 
WITH QuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score AS QuestionScore,
        COALESCE(p.FavoriteCount,0) AS Favorites,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AnswerCount,
        (SELECT AVG(a.Score) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS AvgAnswerScore,
        (SELECT STRING_AGG(t.TagName, ',')
         FROM UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tn(tag)
         JOIN Tags t ON t.TagName = tn.tag) AS TagList,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
      AND p.ClosedDate IS NULL
),
BadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
UserVotes AS (
    SELECT 
        v.UserId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
RecentDuplicates AS (
    SELECT 
        pl.PostId, 
        pl.RelatedPostId, 
        lt.Name AS LinkType
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Name = 'Duplicate'
      AND pl.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    qs.QuestionId,
    qs.Title,
    qs.QuestionScore,
    qs.Favorites,
    qs.AnswerCount,
    ROUND(qs.AvgAnswerScore::numeric,2) AS AvgAnswerScore,
    qs.TagList,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    uv.UpVotesGiven,
    uv.DownVotesGiven,
    COALESCE(rd.LinkType,'None') AS RecentDuplicateLink,
    CASE
        WHEN qs.AnswerCount = 0 THEN 'Unanswered'
        WHEN qs.AnswerCount > 0 AND qs.AvgAnswerScore IS NULL THEN 'NoScore'
        ELSE 'Answered'
    END AS AnswerStatus,
    qs.rn AS RecentQuestionRank
FROM QuestionStats qs
JOIN Users u ON u.Id = qs.OwnerUserId
LEFT JOIN BadgeCounts bc ON bc.UserId = u.Id
LEFT JOIN UserVotes uv ON uv.UserId = u.Id
LEFT JOIN RecentDuplicates rd ON rd.PostId = qs.QuestionId
WHERE qs.rn <= 10

UNION ALL

SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    a.Id AS QuestionId,
    SUBSTRING(a.Body FROM 1 FOR 100) || '...' AS Title,
    a.Score,
    0 AS Favorites,
    NULL AS AnswerCount,
    NULL AS AvgAnswerScore,
    NULL AS TagList,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    uv.UpVotesGiven,
    uv.DownVotesGiven,
    'None' AS RecentDuplicateLink,
    'Answer' AS AnswerStatus,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY a.CreationDate DESC) AS RecentQuestionRank
FROM Posts a
JOIN Users u ON u.Id = a.OwnerUserId
LEFT JOIN BadgeCounts bc ON bc.UserId = u.Id
LEFT JOIN UserVotes uv ON uv.UserId = u.Id
WHERE a.PostTypeId = 2
  AND a.CreationDate >= CURRENT_DATE - INTERVAL '180 days'
  AND a.Score > 5
ORDER BY Reputation DESC, QuestionScore DESC
LIMIT 150;