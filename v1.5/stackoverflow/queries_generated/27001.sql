-- {"query": "27001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 2078} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.DisplayName,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS TotalAnswers,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostActivity AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        COALESCE(p.ParentId, -1) AS ParentId,
        pt.Name AS PostTypeName,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT ph.Id) AS TotalPostHistory,
        COUNT(DISTINCT pl.Id) AS TotalPostLinks,
        MAX(ph.CreationDate) AS LastEditDate,
        STRING_AGG(DISTINCT t.TagName, ', ') AS AllTags
    FROM
        Posts p
    LEFT JOIN
        PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN
        PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN
        Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.Title, p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate, p.AcceptedAnswerId, p.ParentId, pt.Name
),
ActiveUsers AS (
    SELECT
        ua.UserId,
        ua.Reputation,
        ua.UserCreationDate,
        ua.DisplayName,
        ua.LastAccessDate,
        ua.Views,
        ua.UpVotes,
        ua.DownVotes,
        ua.TotalPosts,
        ua.TotalComments,
        ua.TotalVotes,
        ua.TotalBadges,
        ua.GoldBadges,
        ua.BronzeBadges,
        ua.TotalQuestions,
        ua.TotalAnswers,
        ua.LastPostDate,
        ua.LastCommentDate,
        ROW_NUMBER() OVER (PARTITION BY ua.UserId ORDER BY ua.LastAccessDate DESC) AS ActivityRank
    FROM
        UserActivity ua
)
SELECT
    au.UserId,
    au.Reputation,
    au.UserCreationDate,
    au.DisplayName,
    au.LastAccessDate,
    au.Views,
    au.UpVotes,
    au.DownVotes,
    au.TotalPosts,
    au.TotalComments,
    au.TotalVotes,
    au.TotalBadges,
    au.GoldBadges,
    au.BronzeBadges,
    au.TotalQuestions,
    au.TotalAnswers,
    au.LastPostDate,
    au.LastCommentDate,
    pa.PostId,
    pa.PostTypeId,
    pa.PostCreationDate,
    pa.Score,
    pa.ViewCount,
    pa.OwnerUserId,
    pa.Title,
    pa.Tags,
    pa.AnswerCount,
    pa.CommentCount,
    pa.FavoriteCount,
    pa.ClosedDate,
    pa.CommunityOwnedDate,
    pa.AcceptedAnswerId,
    pa.ParentId,
    pa.PostTypeName,
    pa.TotalVotes AS PostVotes,
    pa.TotalComments AS PostComments,
    pa.TotalPostHistory,
    pa.TotalPostLinks,
    pa.LastEditDate,
    pa.AllTags,
    COALESCE(pa.AcceptedAnswerId, -1) AS AcceptedAnswerId,
    COALESCE(pa.ParentId, -1) AS ParentId,
    NVL(au.ActivityRank, 0) AS ActivityRank,
    CASE
        WHEN pa.PostTypeId = 1 THEN 'Question'
        WHEN pa.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END AS PostCategory,
    CASE
        WHEN pa.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS PostStatus,
    CASE
        WHEN pa.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'User Owned'
    END AS OwnershipStatus,
    SUBSTRING(pa.Tags, 2, LENGTH(pa.Tags) - 2) AS TagList,
    STRING_AGG(DISTINCT t.TagName, ', ') OVER (PARTITION BY pa.PostId) AS AllTagsInPost,
    COUNT(DISTINCT v.Id) OVER (PARTITION BY pa.PostId) AS TotalPostInteractions,
    SUM(v.VoteTypeId) OVER (PARTITION BY pa.PostId) AS TotalVoteScore,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = pa.PostId AND ph.PostHistoryTypeId = 10) AS CloseVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = pa.PostId AND ph.PostHistoryTypeId = 11) AS ReopenVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = pa.PostId AND ph.PostHistoryTypeId = 12) AS DeleteVotes
FROM
    ActiveUsers au
LEFT JOIN
    PostActivity pa ON au.UserId = pa.OwnerUserId
LEFT JOIN
    Votes v ON pa.PostId = v.PostId
LEFT JOIN
    Tags t ON pa.Tags LIKE CONCAT('%<', t.TagName, '>%')
WHERE
    au.ActivityRank <= 100
    AND pa.PostCreationDate BETWEEN DATEADD(MONTH, -12, CURRENT_TIMESTAMP())  AND CURRENT_TIMESTAMP
ORDER BY
    au.Reputation DESC,
    pa.Score DESC,
    pa.ViewCount DESC;
