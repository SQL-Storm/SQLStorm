-- {"query": "3610.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2768} 

WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)               AS NetVotes,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
           (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
           (SELECT COUNT(*) FROM Posts p WHERE p.AcceptedAnswerId IS NOT NULL AND p.OwnerUserId = u.Id) AS AcceptedAnswers,
           (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVotesGiven,
           (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) AS DownVotesGiven
    FROM Users u
    WHERE u.Reputation > 1000
),
TagStats AS (
    SELECT t.TagName,
           t.Count                                           AS TagUseCount,
           COALESCE(e.ExcerptLength,0)                       AS ExcerptLen,
           COALESCE(w.WikiLength,0)                          AS WikiLen
    FROM Tags t
    LEFT JOIN LATERAL (
        SELECT length(p.Body) AS ExcerptLength
        FROM Posts p
        WHERE p.Id = t.ExcerptPostId
    ) e ON true
    LEFT JOIN LATERAL (
        SELECT length(p.Body) AS WikiLength
        FROM Posts p
        WHERE p.Id = t.WikiPostId
    ) w ON true
    WHERE t.IsModeratorOnly = 0
),
QuestionAnalytics AS (
    SELECT p.Id,
           p.Title,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.FavoriteCount,
           p.AnswerCount,
           COALESCE(p.Tags,'')                              AS RawTags,
           regexp_split_to_table(p.Tags, '[><]')            AS Tag,
           ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS RevRank,
           MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseReasonId,
           COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2)       AS UpVoteCount,
           COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3)       AS DownVoteCount,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeUserUpVotes
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN Votes v       ON v.PostId = p.Id
    WHERE p.PostTypeId = 1               -- questions
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount,
             p.FavoriteCount, p.AnswerCount, p.Tags, p.OwnerUserId
),
Combined AS (
    SELECT qa.Id,
           qa.Title,
           qa.CreationDate,
           qa.Score,
           qa.ViewCount,
           qa.FavoriteCount,
           qa.AnswerCount,
           qa.UpVoteCount,
           qa.DownVoteCount,
           qa.CumulativeUserUpVotes,
           CASE
               WHEN qa.CloseReasonId IS NOT NULL THEN 'Closed ('||qa.CloseReasonId||')'
               ELSE 'Open'
           END                                           AS Status,
           COALESCE(string_agg(DISTINCT ts.TagName, ', '), 'none')       AS TagNames,
           COALESCE(string_agg(DISTINCT ts.TagUseCount::text, ', '), '0') AS TagUseCounts
    FROM QuestionAnalytics qa
    LEFT JOIN TagStats ts ON ts.TagName = qa.Tag
    GROUP BY qa.Id, qa.Title, qa.CreationDate, qa.Score, qa.ViewCount,
             qa.FavoriteCount, qa.AnswerCount, qa.UpVoteCount, qa.DownVoteCount,
             qa.CumulativeUserUpVotes, qa.CloseReasonId
)
SELECT c.Id,
       c.Title,
       c.Status,
       c.Score,
       c.ViewCount,
       c.FavoriteCount,
       c.AnswerCount,
       c.UpVoteCount,
       c.DownVoteCount,
       c.CumulativeUserUpVotes,
       c.TagNames,
       c.TagUseCounts,
       u.DisplayName,
       u.Reputation,
       u.GoldBadges,
       u.SilverBadges,
       u.BronzeBadges,
       u.NetVotes,
       (u.AcceptedAnswers::decimal / NULLIF(u.AnswerCount,0)) * 100   AS AcceptanceRatePct,
       CASE
           WHEN u.Reputation > 20000 THEN 'Elite'
           WHEN u.Reputation BETWEEN 10000 AND 20000 THEN 'Pro'
           ELSE 'Rising'
       END                                                          AS ReputationTier
FROM Combined c
JOIN UserStats u ON u.Id = (
    SELECT OwnerUserId FROM Posts WHERE Id = c.Id
)
WHERE c.Score > 5
  AND c.ViewCount > 100
  AND (c.AnswerCount = 0 OR c.AnswerCount > 2)
  AND c.TagUseCounts <> '0'
ORDER BY c.CumulativeUserUpVotes DESC NULLS LAST
LIMIT 100
OFFSET 0

UNION ALL

SELECT NULL,NULL,'--- Summary ---',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
       NULL,NULL,
       SUM(u.Reputation) OVER ()                               AS TotalReputation,
       NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
FROM (SELECT 1) s
LIMIT 1;
