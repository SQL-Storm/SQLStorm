-- {"query": "2461.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1477} 
WITH RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, COALESCE(t.Count,0) AS TagCount, t.IsModeratorOnly, t.IsRequired,
           ARRAY[t.TagName] AS TagPath,
           1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = 0

    UNION ALL

    SELECT t2.Id, t2.TagName, COALESCE(t2.Count,0), t2.IsModeratorOnly, t2.IsRequired,
           rth.TagPath || t2.TagName,
           rth.Level + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy rth ON t2.Id <> ALL(
        SELECT Id FROM Tags WHERE TagName = ANY(rth.TagPath)
    )
    WHERE t2.IsModeratorOnly = 0 AND rth.Level < 3
),

RecentHighRepUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate,
      COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
      COUNT(DISTINCT p2.Id) FILTER (WHERE p2.PostTypeId = 2) AS AnswerCount,
      COALESCE(SUM(v.VoteTypeId = 2)::int, 0) AS UpVotesReceived,
      COALESCE(SUM(v.VoteTypeId = 3)::int, 0) AS DownVotesReceived,
      RANK() OVER (ORDER BY u.Reputation DESC, u.CreationDate) AS RepRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Posts p2 ON p2.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId IN (p.Id, p2.Id)
    WHERE u.Reputation >= 1000 AND u.CreationDate > NOW() - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),

QuestionWithAcceptedAnswer AS (
    SELECT q.Id AS QuestionId, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags,
      q.AcceptedAnswerId,
      a.Id AS AnswerId, a.OwnerUserId AS AnswerOwner, a.Score AS AnswerScore,
      u.DisplayName AS AnswererName,
      EXISTS (
        SELECT 1 FROM Votes v
        WHERE v.PostId = a.Id AND v.VoteTypeId = 2 AND v.CreationDate > NOW() - INTERVAL '90 days'
      ) AS RecentUpvotedAnswer,
      ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC NULLS LAST, a.CreationDate) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
    WHERE q.PostTypeId = 1
),

BadgesPerUser AS (
    SELECT b.UserId, 
           COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
           COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
           COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
           STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Name) AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),

PostCommentStats AS (
    SELECT p.Id AS PostId,
           COUNT(c.Id) AS TotalComments,
           AVG(LENGTH(c.Text)) FILTER (WHERE c.Text IS NOT NULL) AS AvgCommentLength,
           COUNT(DISTINCT c.UserId) FILTER (WHERE c.UserId IS NOT NULL) AS UniqueCommenters
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    GROUP BY p.Id
)

SELECT
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.Tags,
    q.AcceptedAnswerId,
    q.AnswerId,
    q.AnswerOwner,
    COALESCE(u.DisplayName, 'Anonymous') AS AnswererName,
    q.AnswerScore,
    q.RecentUpvotedAnswer,
    COALESCE(b.GoldBadges, 0) AS GoldBadges,
    COALESCE(b.SilverBadges, 0) AS SilverBadges,
    COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
    b.BadgeNames,
    pcs.TotalComments,
    pcs.AvgCommentLength,
    pcs.UniqueCommenters,
    rth.TagPath,
    rth.Level,
    ru.Reputation AS AnswererReputation,
    ru.RepRank AS AnswererRepRank,
    ru.QuestionCount AS AnswererQuestionCount,
    ru.AnswerCount AS AnswererAnswerCount,
    ru.UpVotesReceived AS AnswererUpVotes,
    ru.DownVotesReceived AS AnswererDownVotes,
    CASE 
        WHEN q.ViewCount > 10000 THEN 'Popular'
        WHEN q.ViewCount BETWEEN 1000 AND 10000 THEN 'Moderate'
        WHEN q.ViewCount < 1000 THEN 'Low'
        ELSE 'Unknown'
    END AS PopularityClass,
    ROW_NUMBER() OVER (PARTITION BY q.QuestionId ORDER BY q.AnswerScore DESC NULLS LAST) AS AnswerPosition
FROM QuestionWithAcceptedAnswer q
LEFT JOIN Users u ON u.Id = q.AnswerOwner
LEFT JOIN BadgesPerUser b ON b.UserId = q.AnswerOwner
LEFT JOIN PostCommentStats pcs ON pcs.PostId = q.QuestionId
LEFT JOIN RecursiveTagHierarchy rth ON rth.TagName = ANY(string_to_array(REGEXP_REPLACE(q.Tags, '[<>]', '', 'g'), ',', '')) 
LEFT JOIN RecentHighRepUsers ru ON ru.Id = q.AnswerOwner
WHERE q.AnswerRank <= 3
AND q.CreationDate > NOW() - INTERVAL '1 year'
AND (q.Score > 0 OR q.ViewCount > 500)
ORDER BY q.CreationDate DESC, q.Score DESC

UNION

SELECT 
    u.Id AS QuestionId,
    CONCAT('User Profile: ', COALESCE(u.DisplayName, 'N/A')) AS Title,
    u.CreationDate,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    u.DisplayName,
    NULL,
    NULL,
    COALESCE(b.GoldBadges, 0),
    COALESCE(b.SilverBadges, 0),
    COALESCE(b.BronzeBadges, 0),
    b.BadgeNames,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM Users u
LEFT JOIN BadgesPerUser b ON b.UserId = u.Id
WHERE u.Reputation > 20000

ORDER BY 1 DESC
LIMIT 100;