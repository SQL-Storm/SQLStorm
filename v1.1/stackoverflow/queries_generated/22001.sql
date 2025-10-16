-- {"query": "22001.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 953} 

WITH UserActivity AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgScore,
        STRING_AGG(DISTINCT substring(t.TagName, 1, 5), ', ') AS TopTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN (
        SELECT p.Id AS PostId, t.TagName
        FROM Posts p
        CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName)
        JOIN Tags t ON t.TagName = t.TagName
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    ) AS pt ON p.Id = pt.PostId
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
BadgeMetrics AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 5 WHEN b.Class = 2 THEN 3 ELSE 1 END) AS BadgeValue,
        STRING_AGG(b.Name, '; ') AS BadgeList
    FROM Badges b
    WHERE b.TagBased = 1
    GROUP BY b.UserId
),
VoteAggregates AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesReceived,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesReceived,
        SUM(CASE WHEN v.BountyAmount IS NOT NULL THEN v.BountyAmount ELSE 0 END) AS TotalBounty
    FROM Votes v
    GROUP BY v.UserId
),
CommentStats AS (
    SELECT 
        c.UserId,
        COUNT(*) AS CommentCount,
        AVG(LENGTH(c.Text)) AS AvgCommentLength
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
)
SELECT 
    ua.Id,
    UPPER(LEFT(ua.DisplayName, 10)) || '...' AS ShortName,
    ua.Reputation,
    ua.TotalScore,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.AvgScore,
    ua.TopTags,
    COALESCE(bm.TotalBadges, 0) AS TotalBadges,
    COALESCE(bm.BadgeValue, 0) AS BadgeValue,
    bm.BadgeList,
    COALESCE(va.UpVotesReceived, 0) AS UpVotesReceived,
    COALESCE(va.DownVotesReceived, 0) AS DownVotesReceived,
    COALESCE(va.TotalBounty, 0) AS TotalBounty,
    COALESCE(cs.CommentCount, 0) AS CommentCount,
    COALESCE(cs.AvgCommentLength, 0) AS AvgCommentLength,
    (ua.Reputation * 1.2 + COALESCE(bm.BadgeValue, 0) + COALESCE(va.UpVotesReceived, 0) * 0.5 - COALESCE(va.DownVotesReceived, 0) * 0.3) AS CompositeScore,
    ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC, CompositeScore DESC) AS UserRank,
    RANK() OVER (PARTITION BY EXTRACT(YEAR FROM ua.CreationDate) ORDER BY ua.TotalScore DESC) AS YearRank
FROM UserActivity ua
LEFT JOIN BadgeMetrics bm ON ua.Id = bm.UserId
LEFT JOIN VoteAggregates va ON ua.Id = va.UserId
LEFT JOIN CommentStats cs ON ua.Id = cs.UserId
WHERE ua.Reputation > 500
  AND (ua.QuestionCount > 5 OR ua.AnswerCount > 10)
  AND ua.Id NOT IN (
      SELECT DISTINCT p.OwnerUserId
      FROM Posts p
      WHERE p.ClosedDate IS NOT NULL
        AND p.OwnerUserId IS NOT NULL
        AND (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10) > 0
  )
ORDER BY CompositeScore DESC, ua.Reputation DESC
LIMIT 100;
