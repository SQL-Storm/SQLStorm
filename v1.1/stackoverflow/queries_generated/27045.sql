-- {"query": "27045.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 945} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(p.Id) AS PostCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(v.CreationDate) AS LastVoteDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes
), TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        p.Title,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.ViewCount DESC) AS Rank
    FROM
        Tags t
    JOIN
        Posts p ON t.ExcerptPostId = p.Id OR t.WikiPostId = p.Id
    WHERE
        p.PostTypeId IN (1, 5)
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    (ua.Views + ua.UpVotes) / NULLIF(ua.DownVotes, 0) AS EngagementRatio,
    ua.PostCount,
    ua.CommentCount,
    ua.VoteCount,
    GREATEST(ua.LastPostDate, ua.LastCommentDate, ua.LastVoteDate) AS LastActivityDate,
    tt.TagName,
    tt.Title AS TopTagPostTitle,
    tt.ViewCount AS TopTagPostViewCount,
    tt.Rank,
    ph.PostHistoryTypeId,
    ph.CreationDate AS PostHistoryDate,
    ph.Text,
    LAG(ph.PostHistoryTypeId, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousPostHistoryTypeId,
    SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) AS TagList,
    STRING_AGG(t.TagName, ', ') WITHIN GROUP (ORDER BY t.Count DESC) AS RelatedTags
FROM
    UserActivity ua
LEFT JOIN
    TopTags tt ON ua.UserId = (SELECT TOP 1 p.OwnerUserId FROM Posts p WHERE p.Id = tt.ExcerptPostId OR p.Id = tt.WikiPostId) /*uses the post referencing a tag*/
LEFT JOIN
    PostHistory ph ON ua.UserId = ph.UserId
LEFT JOIN
    Posts p ON ph.PostId = p.Id
LEFT JOIN
    Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
WHERE
    ua.PostCount > 0 OR ua.CommentCount > 0 OR ua.VoteCount > 0
GROUP BY
    ua.UserId, ua.DisplayName, ua.Reputation, ua.EngagementRatio, ua.PostCount, ua.CommentCount, ua.VoteCount, ua.LastActivityDate, tt.TagName, tt.Title, tt.ViewCount, tt.Rank, ph.PostHistoryTypeId, ph.PostHistoryDate, ph.Text, ph.PreviousPostHistoryTypeId, p.Tags
ORDER BY
    ua.Reputation DESC, tt.Rank ASC
LIMIT 100;
