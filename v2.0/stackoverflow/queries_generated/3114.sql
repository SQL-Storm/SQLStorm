-- {"query": "3114.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2457} 

WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)          AS NetVotes,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)                  AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2)                  AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3)                  AS BronzeBadges,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)             AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)             AS AnswerCount,
        MAX(p.CreationDate)                                    AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b      ON b.UserId = u.Id
    LEFT JOIN Posts  p      ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
RecentVotes AS (
    SELECT
        v.UserId,
        COUNT(*)                                            AS VoteCount,
        SUM(CASE WHEN vt.Name = 'UpMod'   THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(v.CreationDate)                                 AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.UserId
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count                           AS TagUseCount,
        COALESCE(e.ExcerptLength,0) + COALESCE(w.WikiLength,0) AS ContentLength,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    LEFT JOIN LATERAL (
        SELECT LENGTH(p.Body) AS ExcerptLength
        FROM Posts p
        WHERE p.Id = t.ExcerptPostId
    ) e ON true
    LEFT JOIN LATERAL (
        SELECT LENGTH(p.Body) AS WikiLength
        FROM Posts p
        WHERE p.Id = t.WikiPostId
    ) w ON true
    WHERE t.IsModeratorOnly = 0
),
TopPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankInType
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)          -- questions & answers
      AND p.Score IS NOT NULL
)
SELECT
    us.Id                                     AS UserId,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.QuestionCount,
    us.AnswerCount,
    us.LastPostDate,
    COALESCE(rv.VoteCount,0)                  AS RecentVoteCount,
    COALESCE(rv.UpVoteCount,0)                AS RecentUpVotes,
    COALESCE(rv.DownVoteCount,0)              AS RecentDownVotes,
    rv.LastVoteDate,
    tp.Id                                     AS TopQuestionId,
    tp.Title                                  AS TopQuestionTitle,
    tp.Score                                  AS TopQuestionScore,
    tp.ViewCount                              AS TopQuestionViews,
    tp.CreationDate                           AS TopQuestionDate,
    CASE
        WHEN tp.RankInType = 1 THEN 'Top Question'
        WHEN tp.RankInType = 2 THEN 'Second Question'
        ELSE NULL
    END                                        AS QuestionTier,
    STRING_AGG(DISTINCT tg.TagName, ', ') FILTER (WHERE tg.TagRank <= 5) AS PopularTags
FROM UserStats us
LEFT JOIN RecentVotes rv      ON rv.UserId = us.Id
LEFT JOIN TopPosts tp         ON tp.OwnerUserId = us.Id
                               AND tp.PostTypeId = 1      -- only questions
                               AND tp.RankInType <= 2
LEFT JOIN (
    SELECT
        p.OwnerUserId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL
) ptg ON ptg.OwnerUserId = us.Id
LEFT JOIN TagPopularity tg    ON tg.TagName = ptg.TagName
GROUP BY
    us.Id, us.DisplayName, us.Reputation, us.NetVotes,
    us.GoldBadges, us.SilverBadges, us.BronzeBadges,
    us.QuestionCount, us.AnswerCount, us.LastPostDate,
    rv.VoteCount, rv.UpVoteCount, rv.DownVoteCount, rv.LastVoteDate,
    tp.Id, tp.Title, tp.Score, tp.ViewCount, tp.CreationDate, tp.RankInType
HAVING COUNT(*) FILTER (WHERE us.Reputation > 10000) > 0
ORDER BY us.Reputation DESC NULLS LAST
LIMIT 100
UNION ALL
SELECT
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL;
