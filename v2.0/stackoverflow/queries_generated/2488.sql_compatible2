WITH RECURSIVE RecursiveCTE AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AcceptedAnswerId,
        1 AS Level,
        CAST(p.Id AS varchar) AS Path
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score > 5
      AND p.Tags LIKE '%<sql>%'

    UNION ALL

    SELECT
        c.Id,
        c.PostTypeId,
        c.OwnerUserId,
        c.Title,
        c.Score,
        c.ViewCount,
        c.CreationDate,
        c.AcceptedAnswerId,
        r.Level + 1,
        r.Path || '->' || CAST(c.Id AS varchar)
    FROM Posts c
    JOIN RecursiveCTE r ON c.ParentId = r.Id
    WHERE c.Score > 0
),
RankedPosts AS (
    SELECT
        r.Id,
        r.PostTypeId,
        r.OwnerUserId,
        r.Title,
        r.Score,
        r.ViewCount,
        r.CreationDate,
        r.AcceptedAnswerId,
        r.Level,
        r.Path,
        row_number() OVER (PARTITION BY r.OwnerUserId ORDER BY r.Score DESC, r.CreationDate DESC) AS rn,
        count(*) OVER (PARTITION BY r.OwnerUserId) AS total_posts,
        avg(r.Score) OVER (PARTITION BY r.OwnerUserId) AS avg_score,
        min(r.CreationDate) OVER (PARTITION BY r.OwnerUserId) AS first_post_date,
        max(r.CreationDate) OVER (PARTITION BY r.OwnerUserId) AS last_post_date
    FROM RecursiveCTE r
),
UserBadgesCount AS (
    SELECT 
        b.UserId,
        sum(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        sum(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        sum(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges
    FROM Badges b
    GROUP BY b.UserId
),
UserVotesAgg AS (
    SELECT
        v.UserId,
        sum(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS upvotes_cast,
        sum(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS downvotes_cast,
        coalesce(sum(v.BountyAmount), 0) AS total_bounty_given
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
TopPostsWithComments AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        count(distinct c.Id) AS comment_count,
        string_agg(
            CASE 
                WHEN c.UserDisplayName IS NOT NULL THEN concat(c.UserDisplayName, ': ', substring(c.Text,1,30))
                ELSE substring(c.Text,1,30)
            END, ' | ' ORDER BY c.CreationDate DESC
        ) AS recent_comments_snippet
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1 AND p.Score > 10
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount
    HAVING count(c.Id) > 2
),
DuplicateAndLinkInfo AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        p1.Score AS PostScore,
        p2.Score AS RelatedPostScore
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    JOIN Posts p1 ON p1.Id = pl.PostId
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    WHERE lt.Name IN ('Duplicate','Linked')
),
UserSummary AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(bcount.gold_badges,0) AS gold_badges,
        coalesce(bcount.silver_badges,0) AS silver_badges,
        coalesce(bcount.bronze_badges,0) AS bronze_badges,
        coalesce(uv.upvotes_cast,0) AS upvotes_cast,
        coalesce(uv.downvotes_cast,0) AS downvotes_cast,
        coalesce(uv.total_bounty_given, 0) AS total_bounty_given,
        count(distinct p.Id) FILTER (WHERE p.PostTypeId = 1) AS question_count,
        count(distinct p.Id) FILTER (WHERE p.PostTypeId = 2) AS answer_count,
        max(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS max_post_score,
        max(p.CreationDate) FILTER (WHERE p.PostTypeId IN (1,2)) AS last_post_date
    FROM Users u
    LEFT JOIN UserBadgesCount bcount ON bcount.UserId = u.Id
    LEFT JOIN UserVotesAgg uv ON uv.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        bcount.gold_badges, bcount.silver_badges, bcount.bronze_badges,
        uv.upvotes_cast, uv.downvotes_cast, uv.total_bounty_given
    ORDER BY u.Reputation DESC
    LIMIT 100
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.gold_badges,
    u.silver_badges,
    u.bronze_badges,
    u.upvotes_cast,
    u.downvotes_cast,
    u.total_bounty_given,
    u.question_count,
    u.answer_count,
    u.max_post_score,
    u.last_post_date,
    rp.Id AS PostId,
    rp.Title AS PostTitle,
    rp.Score AS PostScore,
    rp.ViewCount AS PostViewCount,
    rp.Level AS PostThreadLevel,
    rp.Path AS PostPath,
    topc.comment_count,
    topc.recent_comments_snippet,
    dl.PostId AS DuplicatePostId,
    dl.RelatedPostId,
    dl.LinkTypeName,
    dl.PostScore AS DuplicatePostScore,
    dl.RelatedPostScore
FROM UserSummary u
LEFT JOIN RankedPosts rp ON rp.OwnerUserId = u.Id AND rp.rn = 1
LEFT JOIN TopPostsWithComments topc ON topc.Id = rp.Id
LEFT JOIN DuplicateAndLinkInfo dl ON dl.PostId = rp.Id
WHERE (u.gold_badges + u.silver_badges + u.bronze_badges) > 10
  AND (rp.Score > 10 OR rp.ViewCount > 5000)
ORDER BY u.Reputation DESC, rp.Score DESC
LIMIT 50;