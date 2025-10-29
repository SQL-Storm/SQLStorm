WITH
recent_user_activity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(p.Id) FILTER (WHERE p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days') AS NewPosts,
        MAX(p.LastActivityDate) AS LastPostActivity
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.Location, u.Views, u.UpVotes, u.DownVotes, u.AccountId
),
top_tags AS (
    SELECT
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
    FROM Tags t
    WHERE COALESCE(t.IsModeratorOnly, FALSE) = FALSE
),
tag_wiki AS (
    SELECT
        t.TagName,
        t.Count,
        t.WikiPostId,
        w.Title AS WikiTitle,
        w.Body AS WikiBody,
        w.CreationDate AS WikiCreated
    FROM top_tags t
    LEFT JOIN Posts w ON w.Id = t.WikiPostId
    GROUP BY
        t.TagName, t.Count, t.WikiPostId, w.Title, w.Body, w.CreationDate
),
activity_metrics AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 14 THEN 1 ELSE 0 END) AS ModVotes,
        COUNT(*) AS TotalVotes
    FROM Votes v
    GROUP BY v.PostId
),
complex_post_analysis AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        p.CreationDate,
        p.LastActivityDate,
        p.ViewCount,
        p.Score,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        -- removed p.Status because column does not exist; if needed, replace with correct column name
        a.UpVotes AS UpVotes,
        a.DownVotes AS DownVotes,
        a.TotalVotes,
        row_number() OVER (
            PARTITION BY p.OwnerUserId
            ORDER BY p.Score DESC, p.ViewCount DESC
        ) AS rk_per_author
    FROM Posts p
    LEFT JOIN activity_metrics a ON a.PostId = p.Id
    GROUP BY
        p.Id, p.Title, p.PostTypeId, p.CreationDate, p.LastActivityDate,
        p.ViewCount, p.Score, p.Tags, p.OwnerUserId, p.AcceptedAnswerId,
        p.AnswerCount, p.CommentCount, a.UpVotes, a.DownVotes, a.TotalVotes
),
correlated_subquery AS (
    SELECT
        c.Id AS PostId,
        c.Title,
        c.CreationDate,
        c.LastActivityDate,
        c.ViewCount,
        c.Score,
        c.Tags,
        c.OwnerUserId,
        (SELECT STRING_AGG(co.UserDisplayName, ', ')
         FROM Comments co
         WHERE co.PostId = c.Id AND co.UserDisplayName IS NOT NULL) AS CommentAuthors,
        (SELECT COUNT(*) FROM Comments co2 WHERE co2.PostId = c.Id) AS CommentCount
    FROM Posts c
    WHERE c.PostTypeId = 1
    GROUP BY
        c.Id, c.Title, c.CreationDate, c.LastActivityDate, c.ViewCount, c.Score, c.Tags, c.OwnerUserId
),
final AS (
    SELECT
        cp.PostId,
        cp.Title,
        cp.PostTypeId,
        cp.CreationDate,
        cp.LastActivityDate,
        cp.ViewCount,
        cp.Score,
        cp.Tags,
        cp.OwnerUserId,
        cp.AcceptedAnswerId,
        cp.AnswerCount,
        cp.CommentCount,
        cp.UpVotes,
        cp.DownVotes,
        cp.TotalVotes,
        ca.CommentAuthors,
        ca.CommentCount AS TotalComments,
        ROW_NUMBER() OVER (ORDER BY cp.Score DESC, cp.ViewCount DESC) AS overall_rank,
        CASE
            WHEN cp.Score > 0 THEN 'positive'
            WHEN cp.Score < 0 THEN 'negative'
            ELSE 'neutral'
        END AS sentiment
    FROM complex_post_analysis cp
    LEFT JOIN correlated_subquery ca ON ca.PostId = cp.PostId
    GROUP BY
        cp.PostId, cp.Title, cp.PostTypeId, cp.CreationDate, cp.LastActivityDate,
        cp.ViewCount, cp.Score, cp.Tags, cp.OwnerUserId, cp.AcceptedAnswerId,
        cp.AnswerCount, cp.CommentCount, cp.UpVotes, cp.DownVotes, cp.TotalVotes,
        ca.CommentAuthors, ca.CommentCount
)
SELECT
    f.overall_rank,
    f.PostId,
    f.Title,
    f.PostTypeId,
    pt.Name AS PostTypeName,
    f.CreationDate,
    f.LastActivityDate,
    f.ViewCount,
    f.Score,
    f.UpVotes,
    f.DownVotes,
    f.TotalVotes,
    f.Tags,
    f.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    f.AcceptedAnswerId,
    f.AnswerCount,
    f.CommentCount,
    f.CommentAuthors,
    f.sentiment,
    u.Reputation,
    u.Location,
    u.Views,
    u.UpVotes AS UserUpVotes,
    u.DownVotes AS UserDownVotes,
    u.LastAccessDate,
    b2.BadgeCount
FROM final f
LEFT JOIN Users u ON u.Id = f.OwnerUserId
LEFT JOIN PostTypes pt ON pt.Id = f.PostTypeId
LEFT JOIN (
    SELECT
        UserId,
        COUNT(*) AS BadgeCount
    FROM Badges
    GROUP BY UserId
) b2 ON b2.UserId = u.Id
WHERE f.overall_rank <= 100
ORDER BY f.overall_rank ASC;