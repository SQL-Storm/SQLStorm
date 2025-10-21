-- {"query": "24018.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 4595} 

WITH
    RecentQ AS (
        SELECT
            p.Id,
            p.Title,
            p.CreationDate,
            p.Score,
            p.OwnerUserId,
            p.AcceptedAnswerId,
            p.Tags,
            p.ViewCount,
            CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS is_closed
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.CreationDate >= NOW() - INTERVAL '30 days'
    ),
    TagList AS (
        SELECT
            rq.Id,
            string_agg(t.TagName, ', ') AS tags
        FROM RecentQ rq
        CROSS JOIN LATERAL (
            SELECT unnest(
                string_to_array(
                    substring(rq.Tags, 2, length(rq.Tags) - 2), '><'
                )
            ) AS TagName
        ) t
        GROUP BY rq.Id
    ),
    VoteStats AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS upvotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS downvotes
        FROM Votes v
        GROUP BY v.PostId
    ),
    DupCount AS (
        SELECT
            pl.PostId,
            COUNT(*) AS dup_cnt
        FROM PostLinks pl
        WHERE pl.LinkTypeId = 3
        GROUP BY pl.PostId
    ),
    UserStats AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COUNT(p.Id) AS user_q_count,
            COALESCE(SUM(p.ViewCount),0) AS user_views
        FROM Users u
        LEFT JOIN Posts p
            ON p.OwnerUserId = u.Id
            AND p.PostTypeId = 1
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),
    Combine AS (
        SELECT
            oq.Id,
            oq.Title,
            oq.CreationDate,
            oq.Score,
            oq.is_closed,
            tq.tags,
            vs.upvotes,
            vs.downvotes,
            COALESCE(dc.dup_cnt,0) AS dup_cnt,
            us.DisplayName,
            us.Reputation,
            us.user_q_count,
            us.user_views
        FROM RecentQ oq
        LEFT JOIN TagList tq   ON tq.Id = oq.Id
        LEFT JOIN VoteStats vs ON vs.PostId = oq.Id
        LEFT JOIN DupCount dc  ON dc.PostId = oq.Id
        INNER JOIN UserStats us ON us.Id = oq.OwnerUserId
    ),
    OpenQ AS (
        SELECT *
        FROM Combine
        WHERE is_closed = 0
    ),
    ClosedQ AS (
        SELECT *
        FROM Combine
        WHERE is_closed = 1
    ),
    Unified AS (
        SELECT * FROM OpenQ
        UNION ALL
        SELECT * FROM ClosedQ
    )
SELECT
    u.Id,
    u.Title,
    u.CreationDate,
    u.Score,
    u.is_closed,
    u.tags,
    u.upvotes,
    u.downvotes,
    u.dup_cnt,
    u.DisplayName,
    u.Reputation,
    u.user_q_count,
    u.user_views,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = u.Id) AS comment_cnt,
    PERCENT_RANK() OVER (ORDER BY u.upvotes DESC, u.Score DESC) AS percent_upvotes_rank,
    ROW_NUMBER() OVER (ORDER BY u.upvotes DESC, u.Score DESC) AS row_num
FROM Unified u
WHERE u.upvotes + u.Score > 15
  AND u.Reputation > 1000
  AND (u.is_closed = 0 OR (u.is_closed = 1 AND u.dup_cnt < 2))
ORDER BY u.upvotes DESC, u.Score DESC
LIMIT 20;
