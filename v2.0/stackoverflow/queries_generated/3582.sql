-- {"query": "3582.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2086} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(v.CreationDate) FILTER (WHERE v.VoteTypeId = 2) AS LastUpvoteGiven,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, 
                                   COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) DESC) AS RankByRep
    FROM Users u
    LEFT JOIN Badges b      ON b.UserId = u.Id
    LEFT JOIN Posts p       ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v       ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),

TagInfo AS (
    SELECT 
        t.TagName,
        t.Count                               AS TagUseCount,
        COALESCE(e.Title,'')                  AS ExcerptTitle,
        COALESCE(w.Title,'')                  AS WikiTitle,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    LEFT JOIN Posts e ON e.Id = t.ExcerptPostId
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
),

RecentClosedQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        ph.CreationDate                        AS ClosedDate,
        CAST(ph.Comment AS INTEGER)           AS CloseReasonId,
        ROW_NUMBER() OVER (PARTITION BY ph.Comment 
                           ORDER BY ph.CreationDate DESC) AS ReasonRank
    FROM Posts p
    JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE p.PostTypeId = 1               -- Question
      AND ph.PostHistoryTypeId = 10      -- Post Closed
),

TopTags AS (
    SELECT TagName, TagUseCount
    FROM TagInfo
    WHERE TagRank = 1
    ORDER BY TagUseCount DESC
    FETCH FIRST 10 ROWS ONLY
)

SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.RankByRep,
    COALESCE(rcq.Title,'No recent closed Q')           AS RecentClosedQuestionTitle,
    COALESCE(rcq.ClosedDate, TIMESTAMP '1970-01-01')   AS RecentClosedDate,
    COALESCE(rcq.CloseReasonId,0)                     AS CloseReasonId,
    STRING_AGG(tt.TagName,', ') FILTER (WHERE tt.TagName IS NOT NULL) AS TopTags
FROM UserStats us
LEFT JOIN LATERAL (
    SELECT 
        rcq_inner.Title,
        rcq_inner.ClosedDate,
        rcq_inner.CloseReasonId
    FROM RecentClosedQuestions rcq_inner
    WHERE rcq_inner.Id IN (
        SELECT Id 
        FROM Posts 
        WHERE OwnerUserId = us.Id 
          AND PostTypeId = 1                     -- Question
        ORDER BY CreationDate DESC 
        LIMIT 1
    )
    ORDER BY rcq_inner.ClosedDate DESC 
    LIMIT 1
) rcq ON TRUE
LEFT JOIN TopTags tt ON TRUE
WHERE us.RankByRep <= 100
GROUP BY 
    us.Id, us.DisplayName, us.Reputation, us.NetVotes,
    us.GoldBadges, us.SilverBadges, us.BronzeBadges,
    us.RankByRep, rcq.Title, rcq.ClosedDate, rcq.CloseReasonId

UNION ALL

SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.NetVotes,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.RankByRep,
    NULL                                      AS RecentClosedQuestionTitle,
    NULL                                      AS RecentClosedDate,
    NULL                                      AS CloseReasonId,
    NULL                                      AS TopTags
FROM UserStats us
WHERE us.Reputation = 0
  AND (us.GoldBadges + us.SilverBadges + us.BronzeBadges) > 10

ORDER BY RankByRep;
