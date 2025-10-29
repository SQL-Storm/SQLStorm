-- {"query": "3639.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2004} 

WITH 
UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges
    FROM Users u
),
TopPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.OwnerUserId,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankInType
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)               -- 1 = Question, 2 = Answer
),
PostVotesAgg AS (
    SELECT 
        p.Id,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id
),
TagMetrics AS (
    SELECT 
        t.TagName,
        t.Count AS TagUseCount,
        COALESCE(LENGTH(e.Body),0) AS ExcerptLength,
        COALESCE(LENGTH(w.Body),0) AS WikiLength
    FROM Tags t
    LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
),
Combined AS (
    SELECT
        us.Id                       AS UserId,
        us.DisplayName,
        us.Reputation,
        us.NetVotes,
        us.RepRank,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        tp.Id                       AS PostId,
        tp.Title,
        tp.PostTypeId,
        tp.Score,
        tp.ViewCount,
        COALESCE(tp.FavoriteCount,0) AS Favorites,
        tp.RankInType,
        COALESCE(pv.UpVotes,0)      AS PostUpVotes,
        COALESCE(pv.DownVotes,0)    AS PostDownVotes,
        CASE 
            WHEN tp.PostTypeId = 1 THEN 
                (SELECT string_agg(tg.TagName, ',')
                 FROM unnest(string_to_array(substring(tp.Tags FROM 2 FOR length(tp.Tags)-2), '><')) AS t(tag)
                 JOIN Tags tg ON tg.TagName = t.tag)
            ELSE NULL
        END                        AS TagList,
        COALESCE(tm.TagUseCount,0)  AS TagUseCount
    FROM UserStats us
    LEFT JOIN TopPosts tp       ON tp.OwnerUserId = us.Id AND tp.RankInType = 1
    LEFT JOIN PostVotesAgg pv   ON pv.Id = tp.Id
    LEFT JOIN TagMetrics tm     ON tm.TagName = ANY (string_to_array(substring(tp.Tags FROM 2 FOR length(tp.Tags)-2), '><'))
)
SELECT *
FROM Combined
WHERE (Reputation > 10000 OR GoldBadges > 0)
  AND Score IS NOT NULL AND Score > 0
  AND (TagUseCount > 0 OR TagList IS NOT NULL)
ORDER BY RepRank ASC, Score DESC
LIMIT 100
UNION ALL
SELECT NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
WHERE FALSE;
