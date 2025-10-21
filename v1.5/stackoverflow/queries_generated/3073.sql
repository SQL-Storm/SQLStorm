-- {"query": "3073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1385} 
WITH post_summary AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.PostTypeId,
        p.OwnerUserId,
        p.AnswerCount,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        p.LastActivityDate,
        p.ContentLicense,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RankByDate
    FROM
        Posts p
),
user_stats AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.DisplayName,
        u.Location,
        u.AboutMe,
        u.ProfileImageUrl,
        u.EmailHash,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM
        Users u
        LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.Views, u.UpVotes, u.DownVotes,
        u.DisplayName, u.Location, u.AboutMe, u.ProfileImageUrl, u.EmailHash
),
recent_posts AS (
    SELECT
        ps.PostId,
        ps.Title,
        ps.Tags,
        ps.CreationDate,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.AnswerCount,
        ps.Score,
        ps.ViewCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.AcceptedAnswerId,
        ps.LastActivityDate,
        ps.ContentLicense
    FROM
        post_summary ps
    WHERE
        ps.RankByDate <= 5
),
question_answers AS (
    SELECT
        pq.PostId AS QuestionId,
        pq.Title AS QuestionTitle,
        pa.Id AS AnswerId,
        pa.CreationDate AS AnswerCreationDate,
        pa.Score AS AnswerScore,
        pa.OwnerUserId AS AnswerOwnerUserId
    FROM
        recent_posts pq
        LEFT JOIN Posts pa ON pa.ParentId = pq.PostId AND pa.PostTypeId = 2
),
vote_counts AS (
    SELECT
        p.Id AS PostId,
        COUNT(v1.Id) FILTER (WHERE v1.VoteTypeId = 2) AS UpvoteCount,
        COUNT(v2.Id) FILTER (WHERE v2.VoteTypeId = 3) AS DownvoteCount,
        COUNT(v3.Id) FILTER (WHERE v3.VoteTypeId = 10) AS CloseVoteCount,
        COUNT(v4.Id) FILTER (WHERE v4.VoteTypeId = 12) AS SpamVotes
    FROM
        Posts p
        LEFT JOIN Votes v1 ON v1.PostId = p.Id AND v1.VoteTypeId = 2
        LEFT JOIN Votes v2 ON v2.PostId = p.Id AND v2.VoteTypeId = 3
        LEFT JOIN Votes v3 ON v3.PostId = p.Id AND v3.VoteTypeId = 10
        LEFT JOIN Votes v4 ON v4.PostId = p.Id AND v4.VoteTypeId = 12
    GROUP BY p.Id
),
linked_posts AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        pl.CreationDate
    FROM
        PostLinks pl
        JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
most_active_tags AS (
    SELECT
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag,
        COUNT(*) AS TagCount
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
    GROUP BY
        Tag
)
SELECT
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.BadgeCount,
    us.GoldBadgeCount,
    us.SilverBadgeCount,
    us.BronzeBadgeCount,
    us.UserCreationDate,
    us.LastAccessDate,
    us.Views,
    us.UpVotes,
    us.DownVotes,
    COALESCE(rp.PostId, -1) AS RecentPostId,
    COALESCE(rp.Title, 'N/A') AS RecentPostTitle,
    COALESCE(rp.CreationDate, '1970-01-01') AS RecentPostDate,
    qa.QuestionId,
    qa.QuestionTitle,
    qa.AnswerId,
    qa.AnswerCreationDate,
    qa.AnswerScore,
    qa.AnswerOwnerUserId,
    vc.UpvoteCount,
    vc.DownvoteCount,
    vc.CloseVoteCount,
    vc.SpamVotes,
    array_agg(DISTINCT lt.Name) FILTER (WHERE lt.Name IS NOT NULL) AS LinkedLinkTypes,
    array_agg(DISTINCT tp.Tag) AS TopTags,
    COUNT(DISTINCT l.PostId) AS TotalLinks,
    COUNT(DISTINCT l.RelatedPostId) FILTER (WHERE l.LinkTypeName = 'Duplicate') AS DuplicateLinks
FROM
    user_stats us
    LEFT JOIN recent_posts rp ON us.UserId = rp.OwnerUserId AND rp.PostTypeId = 1
    LEFT JOIN question_answers qa ON us.UserId = qa.AnswerOwnerUserId
    LEFT JOIN vote_counts vc ON us.UserId = vc.PostId
    LEFT JOIN linked_posts l ON l.PostId = us.UserId OR l.RelatedPostId = us.UserId
    LEFT JOIN most_active_tags tp ON true
GROUP BY
    us.UserId, us.DisplayName, us.Reputation, us.BadgeCount, us.GoldBadgeCount, us.SilverBadgeCount, us.BronzeBadgeCount,
    us.UserCreationDate, us.LastAccessDate, us.Views, us.UpVotes, us.DownVotes,
    rp.PostId, rp.Title, rp.CreationDate,
    qa.QuestionId, qa.QuestionTitle, qa.AnswerId, qa.AnswerCreationDate, qa.AnswerScore, qa.AnswerOwnerUserId
ORDER BY
    us.Reputation DESC
LIMIT 100;