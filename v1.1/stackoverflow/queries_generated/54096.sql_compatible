WITH tag_stats AS (
    SELECT
        t.TagName,
        COUNT(p.Id)               AS post_count,
        SUM(p.Score)              AS total_score,
        SUM(p.ViewCount)          AS total_views,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_count,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_count
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE ('%' || t.TagName || '%')
    GROUP BY t.TagName
),
user_activity AS (
    SELECT
        u.Id                           AS UserId,
        u.Reputation,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)        AS upvotes_given,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)        AS downvotes_given,
        COUNT(p.Id)                    AS posts_written,
        COUNT(c.Id)                    AS comments_written
    FROM Users u
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.Reputation
),
duplicate_links AS (
    SELECT
        pl.PostId,
        COUNT(*)      AS dup_count
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Name = 'Duplicate'
    GROUP BY pl.PostId
),
top_tag_post AS (
    SELECT
        ts.TagName,
        ts.post_count,
        ts.total_score,
        ts.total_views,
        ts.question_count,
        ts.answer_count,
        ua.UserId,
        ua.Reputation,
        ua.upvotes_given,
        ua.downvotes_given,
        ua.posts_written,
        ua.comments_written,
        COALESCE(dl.dup_count, 0)                          AS duplicate_links,
        AVG(CASE WHEN ts.post_count = 0 THEN NULL ELSE CAST(ts.total_score AS NUMERIC) / ts.post_count END) OVER () AS global_avg_score,
        NTILE(10) OVER (ORDER BY ts.total_score DESC)     AS score_decile,
        ROW_NUMBER() OVER (ORDER BY ts.total_score DESC)  AS global_rank
    FROM tag_stats ts
    LEFT JOIN duplicate_links dl
      ON dl.PostId = (
            SELECT Id
            FROM Posts p
            WHERE p.Title = ts.TagName
              AND p.PostTypeId = 1
            FETCH FIRST 1 ROWS ONLY
       )
    JOIN LATERAL (
        SELECT ua.*
        FROM user_activity ua
        WHERE ua.UserId = (
            SELECT OwnerUserId
            FROM Posts p
            WHERE p.Tags LIKE ('%' || ts.TagName || '%')
            ORDER BY p.CreationDate DESC
            FETCH FIRST 1 ROWS ONLY
        )
    ) ua ON true
)
SELECT *
FROM top_tag_post
WHERE global_rank <= 100
ORDER BY total_score DESC, total_views DESC, global_rank
FETCH FIRST 1000 ROWS ONLY;