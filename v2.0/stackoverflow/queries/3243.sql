-- {"query": "3243.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2482}
WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)               AS VoteBalance,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
           (SELECT MAX(CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id)           AS LastPostDate
    FROM Users u
),
TagStats AS (
    SELECT t.TagName,
           t.Count                                 AS TagUseCount,
           COALESCE(e.ExcerptLength,0)             AS ExcerptLength,
           COALESCE(w.WikiLength,0)                AS WikiLength,
           t.IsModeratorOnly
    FROM Tags t
    LEFT JOIN (
        SELECT p.Id,
               LENGTH(p.Body) AS ExcerptLength
        FROM Posts p
        WHERE p.Id IN (SELECT ExcerptPostId FROM Tags WHERE ExcerptPostId IS NOT NULL)
    ) e ON e.Id = t.ExcerptPostId
    LEFT JOIN (
        SELECT p.Id,
               LENGTH(p.Body) AS WikiLength
        FROM Posts p
        WHERE p.Id IN (SELECT WikiPostId FROM Tags WHERE WikiPostId IS NOT NULL)
    ) w ON w.Id = t.WikiPostId
    WHERE t.IsModeratorOnly = FALSE
),
PostActivity AS (
    SELECT p.Id,
           p.Title,
           p.PostTypeId,
           p.OwnerUserId,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.AnswerCount,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
           COALESCE(v.UpVotes,0) - COALESCE(v.DownVotes,0)                     AS NetVotes,
           CASE
               WHEN p.Tags IS NULL THEN NULL
               ELSE array_to_string(
                        string_to_array(
                            substring(p.Tags FROM 2 FOR char_length(p.Tags)-2),
                            '><'
                        ),
                        ', '
                    )
           END                                                               AS TagList
    FROM Posts p
    LEFT JOIN (
        SELECT PostId,
               SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
               SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        GROUP BY PostId
    ) v ON v.PostId = p.Id
    WHERE p.PostTypeId IN (1,2)
),
RecentBadges AS (
    SELECT b.UserId,
           string_agg(b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadgeList,
           string_agg(b.Name, ', ') FILTER (WHERE b.Class = 2) AS SilverBadgeList,
           string_agg(b.Name, ', ') FILTER (WHERE b.Class = 3) AS BronzeBadgeList,
           MAX(b.Date)                                        AS LastBadgeDate
    FROM Badges b
    WHERE b.Date >= CAST('2024-10-01' AS date) - INTERVAL '180 days'
    GROUP BY b.UserId
)
SELECT us.Id,
       us.DisplayName,
       us.Reputation,
       us.VoteBalance,
       us.GoldBadges,
       us.SilverBadges,
       us.BronzeBadges,
       us.QuestionCount,
       us.AnswerCount,
       us.LastPostDate,
       rb.GoldBadgeList,
       rb.SilverBadgeList,
       rb.BronzeBadgeList,
       rb.LastBadgeDate,
       pa.Title,
       pa.PostTypeId,
       pa.Score,
       pa.ViewCount,
       pa.AnswerCount,
       pa.NetVotes,
       pa.TagList,
       ts.TagName,
       ts.TagUseCount,
       ts.ExcerptLength,
       ts.WikiLength
FROM UserStats us
LEFT JOIN RecentBadges rb
       ON rb.UserId = us.Id
LEFT JOIN PostActivity pa
       ON pa.OwnerUserId = us.Id AND pa.rn = 1
LEFT JOIN LATERAL (
    SELECT t.TagName,
           t.TagUseCount,
           t.ExcerptLength,
           t.WikiLength
    FROM TagStats t
    WHERE pa.TagList IS NOT NULL
      AND t.TagName = ANY (string_to_array(pa.TagList, ', '))
    ORDER BY t.TagUseCount DESC
    LIMIT 1
) ts ON TRUE
WHERE us.Reputation > 5000
  AND (us.GoldBadges + us.SilverBadges + us.BronzeBadges) >= 5
  AND (pa.Score IS NULL OR pa.Score >= 0)

UNION ALL

SELECT u.Id,
       u.DisplayName,
       u.Reputation,
       0 AS VoteBalance,
       0 AS GoldBadges,
       0 AS SilverBadges,
       0 AS BronzeBadges,
       0 AS QuestionCount,
       0 AS AnswerCount,
       NULL AS LastPostDate,
       NULL AS GoldBadgeList,
       NULL AS SilverBadgeList,
       NULL AS BronzeBadgeList,
       NULL AS LastBadgeDate,
       NULL AS Title,
       NULL AS PostTypeId,
       NULL AS Score,
       NULL AS ViewCount,
       NULL AS AnswerCount,
       NULL AS NetVotes,
       NULL AS TagList,
       NULL AS TagName,
       NULL AS TagUseCount,
       NULL AS ExcerptLength,
       NULL AS WikiLength
FROM Users u
WHERE u.Id NOT IN (SELECT Id FROM UserStats WHERE Reputation > 5000)

ORDER BY Reputation DESC
LIMIT 100;