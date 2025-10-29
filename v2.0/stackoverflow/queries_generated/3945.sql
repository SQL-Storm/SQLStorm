-- {"query": "3945.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2321} 
WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           NTILE(100) OVER (ORDER BY u.Reputation) AS RepPercentile,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
           COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteTotal,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteTotal
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT *
    FROM UserStats
    WHERE RepPercentile >= 95
      AND QuestionCount >= 5
),
PostActivity AS (
    SELECT p.Id,
           p.Title,
           p.CreationDate,
           p.LastActivityDate,
           p.Tags,
           COALESCE(p.ViewCount,0) AS Views,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCnt,
           (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
           (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentRank,
           p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserBadges AS (
    SELECT b.UserId,
           COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
           COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
           COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
           STRING_AGG(DISTINCT b.Name, '; ') AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),
TagStats AS (
    SELECT t.TagName,
           t.Count AS TagUseCount,
           COUNT(p.Id) AS QuestionWithTag
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName, t.Count
)
SELECT
    tu.Id AS UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.RepPercentile,
    tu.QuestionCount,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.BadgeList,
    pa.Id AS QuestionId,
    pa.Title,
    pa.CreationDate,
    pa.Views,
    pa.CommentCnt,
    pa.UpVotes,
    pa.DownVotes,
    COALESCE(ts.TagName, 'no-tag') AS PrimaryTag,
    ts.TagUseCount,
    ts.QuestionWithTag,
    CASE
        WHEN pa.UpVotes - pa.DownVotes > 0 THEN 'Positive'
        WHEN pa.UpVotes - pa.DownVotes = 0 THEN 'Neutral'
        ELSE 'Negative'
    END AS Sentiment,
    CASE
        WHEN pa.Views IS NULL OR pa.Views = 0 THEN NULL
        ELSE ROUND(pa.Views::numeric / (EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - pa.CreationDate))/86400), 2)
    END AS ViewsPerDay
FROM TopUsers tu
LEFT JOIN UserBadges ub ON ub.UserId = tu.Id
INNER JOIN PostActivity pa ON pa.OwnerUserId = tu.Id AND pa.RecentRank = 1
LEFT JOIN LATERAL (
    SELECT UNNEST(string_to_array(REPLACE(REPLACE(pa.Tags, '<', ''), '>', ''), '')) AS TagName
) lt ON TRUE
LEFT JOIN TagStats ts ON ts.TagName = lt.TagName
WHERE pa.RecentRank = 1

UNION ALL

SELECT
    NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL,
    NULL,
    p.Id, p.Title, p.CreationDate,
    p.ViewCount, 0, 0, 0,
    'Unanswered', 0, 0,
    CASE WHEN p.ViewCount IS NULL THEN NULL ELSE 'N/A' END,
    NULL
FROM Posts p
WHERE p.PostTypeId = 1
  AND NOT EXISTS (SELECT 1 FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId = 2)
  AND p.CreationDate > CURRENT_DATE - INTERVAL '30 days'
ORDER BY Reputation DESC NULLS LAST, ViewsPerDay DESC NULLS LAST
LIMIT 100;